"""Remove ChromaDB vectors whose score has left the live catalogue.

A keep-set reconcile: every vector in Chroma whose `score_id` is not among the
non-deleted scores in Rails SQLite is an orphan, and gets dropped. It catches
soft-deleted and fully-purged scores in one pass, because it depends only on
the current state of both stores, never on observing a deletion as it happens.
A score hard-deleted before this ever runs is still pruned: its id is simply
absent from the keep-set.

indexer.py runs this as the first step of every index build, so the vector
index self-heals on every run. Run standalone with `--check` to report orphans
without deleting anything.

Doc IDs follow the `score_{id}` convention from indexer.py. Deletes are batched
at BATCH_SIZE to stay under SQLite's SQLITE_LIMIT_VARIABLE_NUMBER (default 999),
the same constraint reset_smd.py documents.
"""

import logging
import sys

from haystack_integrations.document_stores.chroma import ChromaDocumentStore

from .. import config, db

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

BATCH_SIZE = 500


def prune_deleted(
    check_only: bool = False,
    document_store: ChromaDocumentStore | None = None,
) -> int:
    """Drop Chroma vectors whose score is no longer in the live catalogue.

    Args:
        check_only: report what would be deleted, without changing anything.
        document_store: reuse an already-open store (the indexer passes its
            own); when omitted, one is opened for the configured Chroma path.

    Returns:
        Count of vectors that were (or, in check mode, would be) deleted.
    """
    if document_store is None:
        document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    if document_store.count_documents() == 0:
        logger.info("ChromaDB is empty; nothing to reconcile.")
        return 0

    collection = document_store._collection
    indexed = _indexed_doc_ids(collection)
    logger.info(f"ChromaDB holds {len(indexed)} vectors")

    active_ids = db.get_active_score_ids()
    logger.info(f"SQLite holds {len(active_ids)} live (non-deleted) scores")

    # Safety rail: an empty keep-set against a non-empty index means the DB
    # read came back wrong (missing file / wrong path). Pruning every orphan
    # would wipe the whole index -- refuse instead.
    if indexed and not active_ids:
        raise RuntimeError(
            "Refusing to prune: no live scores found while ChromaDB is non-empty "
            "-- the database read looks broken; aborting before deleting everything."
        )

    orphans = _orphans(indexed, active_ids)
    logger.info(f"Found {len(orphans)} orphaned vectors")

    if not orphans:
        return 0

    if check_only:
        logger.info(
            f"--check mode: would delete {len(orphans)} orphaned vectors (no changes made)"
        )
        return len(orphans)

    _delete_in_batches(collection, orphans)
    logger.info(f"Deleted {len(orphans)} orphaned vectors from ChromaDB")
    return len(orphans)


def _indexed_doc_ids(collection) -> dict[int, str]:
    """Map score_id -> Chroma document id for every vector that carries a score_id."""
    result = collection.get(include=["metadatas"])
    ids = result.get("ids") or []
    metadatas = result.get("metadatas") or []

    indexed: dict[int, str] = {}
    for doc_id, meta in zip(ids, metadatas):
        if meta and "score_id" in meta:
            indexed[meta["score_id"]] = doc_id
    return indexed


def _orphans(indexed: dict[int, str], active_ids: set[int]) -> list[str]:
    """Doc IDs whose score_id is not in the live-scores keep-set."""
    return [doc_id for score_id, doc_id in indexed.items() if score_id not in active_ids]


def _delete_in_batches(collection, doc_ids: list[str]) -> None:
    for i in range(0, len(doc_ids), BATCH_SIZE):
        collection.delete(ids=doc_ids[i:i + BATCH_SIZE])


if __name__ == "__main__":
    prune_deleted(check_only="--check" in sys.argv)
