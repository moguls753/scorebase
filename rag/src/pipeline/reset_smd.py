"""Delete SMD entries from ChromaDB so they can be re-embedded with new prose.

Identifies SMD score IDs via the Rails SQLite, then deletes the corresponding
Chroma documents (doc IDs follow the `score_{id}` pattern set by indexer.py).
"""

import logging
import sqlite3

from haystack_integrations.document_stores.chroma import ChromaDocumentStore

from .. import config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def reset_smd():
    conn = sqlite3.connect(str(config.RAILS_DB_PATH))
    smd_ids = {row[0] for row in conn.execute(
        "SELECT id FROM scores WHERE source = ?", ("smd",)
    )}
    conn.close()
    logger.info(f"Found {len(smd_ids)} SMD scores in SQLite")

    if not smd_ids:
        logger.info("No SMD scores in SQLite; nothing to delete.")
        return

    document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    if document_store.count_documents() == 0:
        logger.info("ChromaDB is empty; nothing to delete.")
        return

    collection = document_store._collection
    all_indexed = collection.get(include=["metadatas"])

    docs_to_delete = [
        doc_id for doc_id, meta in zip(all_indexed["ids"], all_indexed["metadatas"])
        if meta and meta.get("score_id") in smd_ids
    ]
    logger.info(f"Found {len(docs_to_delete)} SMD docs in ChromaDB to delete")

    if docs_to_delete:
        collection.delete(ids=docs_to_delete)
        logger.info(f"Deleted {len(docs_to_delete)} SMD docs from ChromaDB")
    else:
        logger.info("No SMD docs in ChromaDB; nothing to delete.")


if __name__ == "__main__":
    reset_smd()
