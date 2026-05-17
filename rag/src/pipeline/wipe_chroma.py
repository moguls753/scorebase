"""Drop ALL Chroma collections in the persist path.

Use only when migrating embedding models — once a collection contains vectors,
its dimension is fixed; the only way to re-embed with a different-sized model
is to drop the collection and rebuild from scratch.

Idempotent. Safe to re-run.
"""

import logging
import sys

import chromadb

from .. import config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def wipe_chroma(check_only: bool = False) -> int:
    """Drop every collection in the persist path. Returns count of collections dropped."""
    client = chromadb.PersistentClient(path=str(config.CHROMA_PATH))
    collections = client.list_collections()
    logger.info(f"Found {len(collections)} Chroma collections at {config.CHROMA_PATH}")

    for col in collections:
        count = col.count()
        logger.info(f"  - '{col.name}' ({count} documents)")

    if not collections:
        return 0

    if check_only:
        logger.info(f"--check mode: would drop {len(collections)} collections (no changes made)")
        return len(collections)

    for col in collections:
        client.delete_collection(col.name)
        logger.info(f"Dropped collection '{col.name}'")

    return len(collections)


if __name__ == "__main__":
    wipe_chroma(check_only="--check" in sys.argv)
