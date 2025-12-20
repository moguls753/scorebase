"""Configuration for RAG system.

Adjust these paths to match your setup.
"""

from pathlib import Path

# Base directory (rag/)
BASE_DIR = Path(__file__).parent.parent

# Rails database
# From rag/, go up one level to main/, then into db/
RAILS_DB_PATH = BASE_DIR.parent / "db" / "development.sqlite3"

# PDMX data directory (contains mxl/, pdf/, etc.)
PDMX_PATH = Path.home() / "data" / "pdmx"

# Vector database storage
CHROMA_PATH = BASE_DIR / "data" / "chroma"

# Embedding model (small, fast, good quality)
EMBEDDING_MODEL = "all-MiniLM-L6-v2"

# Search defaults
DEFAULT_TOP_K = 20
