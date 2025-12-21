"""Build vector index from scores using Haystack + LLM descriptions."""

import logging
import os
import sys

from haystack import Document
from haystack.components.embedders import SentenceTransformersDocumentEmbedder
from haystack_integrations.document_stores.chroma import ChromaDocumentStore

from .. import config, db
from ..llm import DescriptionGeneratorAgent

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)


def build_index(limit: int = 100):
    """Build vector index from extracted scores.

    Args:
        limit: Number of scores to index (use -1 for all)
    """
    # Check for API key
    if not os.environ.get("GROQ_API_KEY"):
        print("Error: GROQ_API_KEY not set. Get one at https://console.groq.com/keys")
        sys.exit(1)

    print(f"Fetching extracted scores (limit={limit})...")
    if limit == -1:
        scores = db.get_all_extracted_scores()
    else:
        scores = db.get_extracted_scores(limit=limit)
    print(f"Got {len(scores)} extracted scores")

    if not scores:
        print("No extracted scores found. Run music21 extraction first.")
        return

    # Generate descriptions with LLM agent
    print("\nGenerating descriptions with LLM...")
    agent = DescriptionGeneratorAgent()
    results = agent.generate_batch(scores)

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
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    build_index(limit=limit)


if __name__ == "__main__":
    main()
