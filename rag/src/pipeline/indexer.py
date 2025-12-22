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
    print(f"Got {len(scores)} scores")

    if not scores:
        print("No extracted scores found. Run music21 extraction first.")
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

    # Initialize ChromaDB
    config.CHROMA_PATH.mkdir(parents=True, exist_ok=True)
    document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    # Embed
    print(f"Loading embedding model: {config.EMBEDDING_MODEL}")
    embedder = SentenceTransformersDocumentEmbedder(model=config.EMBEDDING_MODEL)
    embedder.warm_up()

    print("Embedding descriptions...")
    result = embedder.run(documents)
    embedded_docs = result["documents"]

    # Store
    print("Storing in ChromaDB...")
    document_store.write_documents(embedded_docs)

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
