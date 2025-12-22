"""Build vector index from scores using Haystack + LLM descriptions."""

import logging
import os
import sys

from haystack import Document
from haystack.components.embedders import SentenceTransformersDocumentEmbedder
from haystack_integrations.document_stores.chroma import ChromaDocumentStore

from .. import config, db
from ..llm import DescriptionGenerator, LMStudioClient

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)


def get_existing_score_ids(document_store: ChromaDocumentStore) -> set[int]:
    """Get score IDs already indexed in ChromaDB."""
    try:
        count = document_store.count_documents()
        if count == 0:
            return set()

        # Access underlying Chroma collection directly for reliable ID retrieval
        collection = document_store._collection
        results = collection.get(include=["metadatas"])

        score_ids = set()
        for meta in results.get("metadatas", []):
            if meta and "score_id" in meta:
                score_ids.add(meta["score_id"])

        return score_ids
    except Exception as e:
        print(f"Warning: Could not fetch existing IDs: {e}")
        return set()


def build_index(limit: int = 100, backend: str = "groq", ids: list[int] | None = None):
    """Build vector index from extracted scores.

    Args:
        limit: Number of scores to index (use -1 for all)
        backend: LLM backend - "groq" or "lmstudio"
        ids: Optional list of specific score IDs to index
    """
    # Setup LLM client based on backend
    if backend == "lmstudio":
        print("Using LM Studio backend")
        client = LMStudioClient()
    else:
        if not os.environ.get("GROQ_API_KEY"):
            print("Error: GROQ_API_KEY not set. Get one at https://console.groq.com/keys")
            sys.exit(1)
        print("Using Groq backend")
        client = None  # DescriptionGenerator defaults to Groq

    # Initialize ChromaDB early to check existing
    config.CHROMA_PATH.mkdir(parents=True, exist_ok=True)
    document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    # Get already indexed score IDs
    existing_ids = get_existing_score_ids(document_store)
    if existing_ids:
        print(f"Found {len(existing_ids)} already indexed scores")

    # Fetch scores
    if ids:
        print(f"Fetching scores by IDs: {ids}")
        scores = db.get_scores_by_ids(ids)
    elif limit == -1:
        print("Fetching all extracted scores...")
        scores = db.get_all_extracted_scores()
    else:
        print(f"Fetching extracted scores (limit={limit})...")
        scores = db.get_extracted_scores(limit=limit)
    print(f"Got {len(scores)} scores from database")

    # Filter out already indexed scores BEFORE API calls
    if existing_ids:
        scores = [s for s in scores if s.get("id") not in existing_ids]
        print(f"After filtering: {len(scores)} new scores to index")

    if not scores:
        print("No new scores to index.")
        return

    # Generate descriptions with LLM
    print("\nGenerating descriptions with LLM...")
    generator = DescriptionGenerator(client=client)
    results = generator.generate_batch(scores)

    # Create documents from successful generations
    documents = []
    failed = 0
    for result in results:
        if result.success and result.description:
            doc = Document(
                id=f"score_{result.score_id}",  # Unique ID prevents duplicates
                content=result.description,
                meta={"score_id": result.score_id}
            )
            documents.append(doc)
        else:
            failed += 1

    print(f"\nGenerated {len(documents)} descriptions ({failed} failed)")

    if not documents:
        print("No descriptions generated. Check GROQ_API_KEY and rate limits.")
        return

    # Embed
    print(f"Loading embedding model: {config.EMBEDDING_MODEL}")
    embedder = SentenceTransformersDocumentEmbedder(model=config.EMBEDDING_MODEL)
    embedder.warm_up()

    print("Embedding descriptions...")
    result = embedder.run(documents)
    embedded_docs = result["documents"]

    # Store (skip existing - won't overwrite already indexed scores)
    print("Storing in ChromaDB...")
    document_store.write_documents(embedded_docs, policy="skip")

    print(f"\nDone! Indexed {len(embedded_docs)} documents to {config.CHROMA_PATH}")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Build vector index from scores")
    parser.add_argument("limit", type=int, nargs="?", default=100, help="Number of scores (-1 for all)")
    parser.add_argument("--backend", choices=["groq", "lmstudio"], default="groq", help="LLM backend")
    parser.add_argument("--ids", type=str, help="Comma-separated score IDs (e.g., '1951,2449,2523')")
    args = parser.parse_args()

    ids = None
    if args.ids:
        ids = [int(x.strip()) for x in args.ids.split(",")]

    build_index(limit=args.limit, backend=args.backend, ids=ids)


if __name__ == "__main__":
    main()
