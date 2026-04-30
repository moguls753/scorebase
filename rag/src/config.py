"""Configuration for RAG system.

Adjust these paths to match your setup. Production overrides via env vars.
"""

import os
from pathlib import Path

# Base directory (rag/)
BASE_DIR = Path(__file__).parent.parent

# Rails database — defaults to local dev SQLite; prod sets RAG_DB_PATH.
RAILS_DB_PATH = Path(
    os.environ.get(
        "RAG_DB_PATH",
        str(BASE_DIR.parent / "storage" / "development.sqlite3"),
    )
)

# PDMX data directory (contains mxl/, pdf/, etc.)
PDMX_PATH = Path.home() / "data" / "pdmx"

# Vector database storage — defaults to rag/data/chroma; prod sets CHROMA_PATH.
CHROMA_PATH = Path(
    os.environ.get("CHROMA_PATH", str(BASE_DIR / "data" / "chroma"))
)

# Embedding model (multilingual for German/French/Italian queries)
EMBEDDING_MODEL = "paraphrase-multilingual-MiniLM-L12-v2"

# Search defaults
DEFAULT_TOP_K = 20


def get_mxl_path(mxl_path: str) -> Path:
    """Convert database mxl_path to full filesystem path.

    Args:
        mxl_path: Path from database (e.g., "./mxl/1/11/Qmbb...mxl")

    Returns:
        Full path to MXL file
    """
    clean_path = mxl_path.lstrip("./")
    return PDMX_PATH / clean_path
