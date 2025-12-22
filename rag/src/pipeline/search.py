"""Search pipeline using Haystack + LLM result selection."""

import os
from haystack import Pipeline
from haystack.components.embedders import SentenceTransformersTextEmbedder
from haystack_integrations.document_stores.chroma import ChromaDocumentStore
from haystack_integrations.components.retrievers.chroma import ChromaEmbeddingRetriever

from .. import config
from ..llm import ResultSelector

# Cache the pipeline to avoid reloading on every search
_pipeline = None


def get_pipeline() -> Pipeline:
    """Get or create search pipeline (cached)."""
    global _pipeline

    if _pipeline is not None:
        return _pipeline

    # Connect to ChromaDB
    document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    # Build pipeline
    pipeline = Pipeline()

    # Text -> Embedding
    pipeline.add_component(
        "embedder",
        SentenceTransformersTextEmbedder(model=config.EMBEDDING_MODEL, progress_bar=False)
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
    pipeline = get_pipeline()

    result = pipeline.run({
        "embedder": {"text": query},
        "retriever": {"top_k": top_k}
    })

    documents = result["retriever"]["documents"]

    return [
        {
            "score_id": doc.meta.get("score_id"),
            "title": doc.meta.get("title", "Untitled"),
            "content": doc.content,
            "similarity": doc.score,
        }
        for doc in documents
    ]


def smart_search(query: str, top_k: int = 15, num_recommendations: int = 3) -> dict:
    """Search with LLM-powered result selection and explanations.

    Args:
        query: Natural language search (e.g., "easy Bach for piano")
        top_k: Number of candidates for LLM to consider (default 15)
        num_recommendations: Number of final recommendations (default 3)

    Returns:
        Dict with:
        - recommendations: list of {score_id, title, explanation, rank}
        - summary: conversational summary string
        - success: bool
        - raw_results: original vector search results (for debugging)
    """
    # Step 1: Vector search for candidates
    raw_results = search(query, top_k=top_k)

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


def main():
    """CLI entry point - test search."""
    import argparse

    parser = argparse.ArgumentParser(description="Search for sheet music")
    parser.add_argument("query", nargs="*", default=["easy", "Bach", "for", "piano"],
                        help="Search query")
    parser.add_argument("--smart", action="store_true",
                        help="Use LLM-powered smart search with explanations")
    parser.add_argument("--top-k", type=int, default=15,
                        help="Number of candidates (default 15)")
    args = parser.parse_args()

    query = " ".join(args.query)
    print(f"Searching: '{query}'\n")

    if args.smart:
        # Smart search with LLM selection
        if not os.environ.get("GROQ_API_KEY"):
            print("Error: GROQ_API_KEY not set for smart search")
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
        results = search(query, top_k=args.top_k)

        for i, r in enumerate(results, 1):
            print(f"{i}. Score ID: {r['score_id']}")
            print(f"   Similarity: {r['similarity']:.3f}")
            print(f"   {r.get('content', '')[:200]}...")
            print()


if __name__ == "__main__":
    main()
