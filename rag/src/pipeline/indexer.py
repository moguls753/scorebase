"""Build vector index from scores.

Simple: read search_text from SQLite, embed, store in ChromaDB.
Rails generates search_text. Python just indexes it.
"""

import logging

from haystack import Document
from haystack.components.embedders import SentenceTransformersDocumentEmbedder
from haystack_integrations.document_stores.chroma import ChromaDocumentStore

from .. import config, db

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)


def get_indexed_score_ids(document_store: ChromaDocumentStore) -> set[int]:
    """Get score IDs already in ChromaDB."""
    try:
        if document_store.count_documents() == 0:
            return set()

        collection = document_store._collection
        results = collection.get(include=["metadatas"])

        return {
            meta["score_id"]
            for meta in results.get("metadatas", [])
            if meta and "score_id" in meta
        }
    except Exception as e:
        logger.warning(f"Could not fetch existing IDs: {e}")
        return set()


def build_index(limit: int = 100, ids: list[int] | None = None):
    """Build vector index from templated scores.

    Args:
        limit: Number of scores to index (-1 for all)
        ids: Optional specific score IDs to index
    """
    # Setup ChromaDB
    config.CHROMA_PATH.mkdir(parents=True, exist_ok=True)
    document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    # Get already indexed
    existing_ids = get_indexed_score_ids(document_store)
    if existing_ids:
        logger.info(f"Found {len(existing_ids)} already indexed scores")

    # Fetch scores with search_text
    if ids:
        logger.info(f"Fetching scores by IDs: {ids}")
        scores = db.get_scores_by_ids(ids)
    else:
        logger.info(f"Fetching templated scores (limit={limit})")
        scores = db.get_templated_scores(limit=limit)

    logger.info(f"Got {len(scores)} scores from database")

    # Filter already indexed
    if existing_ids:
        scores = [s for s in scores if s["id"] not in existing_ids]
        logger.info(f"After filtering: {len(scores)} new scores to index")

    if not scores:
        logger.info("No new scores to index.")
        return

    # Create documents from search_text
    documents = []
    for score in scores:
        doc = Document(
            id=f"score_{score['id']}",
            content=score["search_text"],
            meta={"score_id": score["id"], "title": score["title"] or "Untitled"}
        )
        documents.append(doc)

    logger.info(f"Created {len(documents)} documents")

    # Embed
    logger.info(f"Loading embedding model: {config.EMBEDDING_MODEL}")
    embedder = SentenceTransformersDocumentEmbedder(model=config.EMBEDDING_MODEL)
    embedder.warm_up()

    logger.info("Embedding documents...")
    result = embedder.run(documents)
    embedded_docs = result["documents"]

    # Store
    logger.info("Storing in ChromaDB...")
    document_store.write_documents(embedded_docs, policy="skip")

    # Mark as indexed in Rails DB
    indexed_ids = [s["id"] for s in scores]
    db.mark_indexed(indexed_ids)

    logger.info(f"Done! Indexed {len(embedded_docs)} documents to {config.CHROMA_PATH}")

    # Show stats
    stats = db.get_stats()
    logger.info(f"RAG stats: {stats}")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Index scores to ChromaDB")
    parser.add_argument("limit", type=int, nargs="?", default=100,
                        help="Number of scores (-1 for all)")
    parser.add_argument("--ids", type=str,
                        help="Comma-separated score IDs (e.g., '1951,2449')")
    args = parser.parse_args()

    ids = None
    if args.ids:
        ids = [int(x.strip()) for x in args.ids.split(",")]

    build_index(limit=args.limit, ids=ids)


if __name__ == "__main__":
    main()
