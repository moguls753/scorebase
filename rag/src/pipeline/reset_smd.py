"""Delete SMD entries from ChromaDB so they can be re-embedded with new prose.

Identifies SMD score IDs via Rails SQLite, then deletes the corresponding
Chroma documents (doc IDs follow the `score_{id}` pattern set by indexer.py).

Use `--check` to report what would be deleted without committing.

Why we batch instead of doing one collection.get(): ChromaDB's Rust backend
uses SQLite internally, and a full-collection scan or a large `ids` filter
can exceed SQLite's SQLITE_LIMIT_VARIABLE_NUMBER (default 999), producing
"too many SQL variables" errors. BATCH_SIZE=500 keeps each query well under
that ceiling.
"""

import logging
import sqlite3
import sys

from haystack_integrations.document_stores.chroma import ChromaDocumentStore

from .. import config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

BATCH_SIZE = 500


def reset_smd(check_only: bool = False) -> int:
    """Delete SMD docs from ChromaDB. Returns count of docs that were (or would be) deleted."""
    conn = sqlite3.connect(str(config.RAILS_DB_PATH))
    smd_ids = [row[0] for row in conn.execute(
        "SELECT id FROM scores WHERE source = ?", ("smd",)
    )]
    conn.close()
    logger.info(f"Found {len(smd_ids)} SMD scores in SQLite")

    if not smd_ids:
        logger.info("No SMD scores in SQLite; nothing to delete.")
        return 0

    document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    total_docs = document_store.count_documents()
    if total_docs == 0:
        logger.info("ChromaDB is empty; nothing to delete.")
        return 0
    logger.info(f"ChromaDB contains {total_docs} total documents")

    collection = document_store._collection
    doc_ids = [f"score_{sid}" for sid in smd_ids]

    existing = _find_existing(collection, doc_ids)
    logger.info(f"Found {len(existing)} SMD docs in ChromaDB")

    if not existing:
        return 0

    if check_only:
        logger.info(f"--check mode: would delete {len(existing)} SMD docs (no changes made)")
        return len(existing)

    _delete_in_batches(collection, existing)
    logger.info(f"Deleted {len(existing)} SMD docs from ChromaDB")
    return len(existing)


def _find_existing(collection, doc_ids: list[str]) -> list[str]:
    existing: list[str] = []
    total = len(doc_ids)
    for i in range(0, total, BATCH_SIZE):
        batch = doc_ids[i:i + BATCH_SIZE]
        result = collection.get(ids=batch)
        existing.extend(result["ids"])
        progress = i + len(batch)
        if progress % (BATCH_SIZE * 50) == 0 or progress == total:
            logger.info(f"  scanned {progress}/{total}, {len(existing)} matches so far")
    return existing


def _delete_in_batches(collection, ids: list[str]) -> None:
    for i in range(0, len(ids), BATCH_SIZE):
        batch = ids[i:i + BATCH_SIZE]
        collection.delete(ids=batch)


if __name__ == "__main__":
    reset_smd(check_only="--check" in sys.argv)
