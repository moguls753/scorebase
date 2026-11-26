"""Candidate retrieval and LLM result selection."""

import logging
import os

from .. import config, db
from ..llm import ResultSelector
from .query_normalizer import normalize_for_embedding

logger = logging.getLogger(__name__)

# Cache the pipeline to avoid reloading on every search
_pipeline = None


def get_pipeline():
    """Legacy Chroma path for development without an mLateOn snapshot."""
    global _pipeline

    if _pipeline is not None:
        return _pipeline

    from haystack import Pipeline
    from haystack.components.embedders import SentenceTransformersTextEmbedder
    from haystack_integrations.document_stores.chroma import ChromaDocumentStore
    from haystack_integrations.components.retrievers.chroma import ChromaEmbeddingRetriever

    # Connect to ChromaDB
    document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    # Build pipeline
    pipeline = Pipeline()

    # Text -> Embedding
    pipeline.add_component(
        "embedder",
        SentenceTransformersTextEmbedder(
            model=config.EMBEDDING_MODEL,
            progress_bar=False,
            tokenizer_kwargs={"model_max_length": 512},
        )
    )

    # Embedding -> Similar documents
    pipeline.add_component(
        "retriever",
        ChromaEmbeddingRetriever(document_store=document_store, top_k=config.DEFAULT_TOP_K)
    )

    # Connect components
    pipeline.connect("embedder.embedding", "retriever.query_embedding")

    _pipeline = pipeline
    return pipeline


def search(query: str, top_k: int = 10) -> list[dict]:
    """Search for scores matching query (vector search only).

    Args:
        query: Natural language search (e.g., "easy Bach for piano")
        top_k: Number of results

    Returns:
        List of results with score_id, content (LLM description), similarity
    """
    if path := os.environ.get("MLATEON_INDEX_PATH"):
        from . import mlateon
        return mlateon.search(path, query, top_k)

    pipeline = get_pipeline()
    embed_query = normalize_for_embedding(query)
    if embed_query != query:
        logger.debug("Normalized query for embedding: %r -> %r", query, embed_query)

    result = pipeline.run({
        "embedder": {"text": embed_query},
        "retriever": {"top_k": top_k}
    })

    documents = result["retriever"]["documents"]

    score_ids = [doc.meta.get("score_id") for doc in documents if doc.meta.get("score_id")]
    metadata_by_id = db.get_score_metadata(score_ids)

    return [
        {
            "score_id": doc.meta.get("score_id"),
            "title": doc.meta.get("title", "Untitled"),
            "content": doc.content,
            "similarity": doc.score,
            **metadata_by_id.get(doc.meta.get("score_id"), {"source": "unknown", "commercial": False}),
        }
        for doc in documents
    ]


def smart_candidates(query: str, top_k: int | None = None) -> list[dict]:
    if os.environ.get("MLATEON_INDEX_PATH"):
        limit = 30 if top_k is None else min(top_k, 30)
    else:
        limit = 15 if top_k is None else top_k
    return search(query, top_k=limit)


def smart_search(query: str, top_k: int | None = None, num_recommendations: int = 3) -> dict:
    """Search with LLM-powered result selection and explanations.

    Args:
        query: Natural language search (e.g., "easy Bach for piano")
        top_k: Candidate limit (default 30 for mLateOn, 15 for Chroma)
        num_recommendations: Number of final recommendations (default 3)

    Returns:
        Dict with:
        - recommendations: list of {score_id, title, explanation, rank}
        - summary: conversational summary string
        - success: bool
        - raw_results: original vector search results (for debugging)
    """
    # Step 1: Vector search for candidates
    raw_results = smart_candidates(query, top_k=top_k)

    if not raw_results:
        return {
            "recommendations": [],
            "summary": "No scores found matching your search.",
            "success": True,
            "raw_results": []
        }

    # Step 2: LLM selects and explains best matches
    selector = ResultSelector()
    selection = selector.select(
        query=query,
        search_results=raw_results,
        num_recommendations=num_recommendations
    )

    return {
        "recommendations": [
            {
                "score_id": rec.score_id,
                "title": rec.title,
                "explanation": rec.explanation,
                "rank": rec.rank
            }
            for rec in selection.recommendations
        ],
        "summary": selection.summary,
        "success": selection.success,
        "raw_results": raw_results  # Include for debugging/fallback
    }


def smart_refine(
    *,
    original_query: str,
    refinement: str,
    previous_summary: str,
    previous_recommendations: list[dict],
    top_k: int | None = None,
) -> dict:
    """LLM-powered refinement: re-search with the enriched query, rerank with previous-turn context.

    Same return shape as smart_search().
    """
    enriched_query = f"{original_query} {refinement}"
    candidates = smart_candidates(enriched_query, top_k=top_k)

    selector = ResultSelector()
    selection = selector.select_with_refinement(
        original_query=original_query,
        refinement=refinement,
        previous_summary=previous_summary,
        previous_recommendations=previous_recommendations,
        search_results=candidates,
    )

    return {
        "recommendations": [
            {
                "score_id": r.score_id,
                "title": r.title,
                "explanation": r.explanation,
                "rank": r.rank,
            }
            for r in selection.recommendations
        ],
        "summary": selection.summary,
        "success": selection.success,
    }


def main():
    """CLI entry point - test search."""
    import argparse

    parser = argparse.ArgumentParser(description="Search for sheet music")
    parser.add_argument("query", nargs="*", default=["easy", "Bach", "for", "piano"],
                        help="Search query")
    parser.add_argument("--smart", action="store_true",
                        help="Use LLM-powered smart search with explanations")
    parser.add_argument("--top-k", type=int, help="Override the default candidate count")
    args = parser.parse_args()

    query = " ".join(args.query)
    print(f"Searching: '{query}'\n")

    if args.smart:
        from ..llm.factory import required_api_key_env_var
        key = required_api_key_env_var()
        if key and not os.environ.get(key):
            print(f"Error: {key} not set for smart search")
            return

        print("Using smart search (LLM-powered)...\n")
        result = smart_search(query, top_k=args.top_k)

        print(f"{result['summary']}\n")

        for rec in result["recommendations"]:
            print(f"{rec['rank']}. **{rec['title']}** (ID: {rec['score_id']})")
            print(f"   {rec['explanation']}")
            print()

        print(f"\n(Selected from {len(result['raw_results'])} candidates)")
    else:
        # Basic vector search
        results = search(query, top_k=args.top_k if args.top_k is not None else 15)

        for i, r in enumerate(results, 1):
            print(f"{i}. Score ID: {r['score_id']}")
            print(f"   Similarity: {r['similarity']:.3f}")
            print(f"   {r.get('content', '')[:200]}...")
            print()


if __name__ == "__main__":
    main()
