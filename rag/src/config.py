"""Configuration for RAG system.

Adjust these paths to match your setup.
"""

from pathlib import Path

# Base directory (rag/)
BASE_DIR = Path(__file__).parent.parent

# Rails database (Rails 8 uses storage/ for SQLite)
# From rag/rag/, go up one level to worktree root, then into storage/
RAILS_DB_PATH = BASE_DIR.parent / "storage" / "development.sqlite3"

# PDMX data directory (contains mxl/, pdf/, etc.)
PDMX_PATH = Path.home() / "data" / "pdmx"

# Vector database storage
CHROMA_PATH = BASE_DIR / "data" / "chroma"

# Embedding model (small, fast, good quality)
EMBEDDING_MODEL = "all-MiniLM-L6-v2"

# Search defaults
DEFAULT_TOP_K = 20
