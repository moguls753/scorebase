"""Enrich scores with MXL-extracted features."""

import sys
from pathlib import Path

from .. import config

# Add parent directory to path for extract module
sys.path.insert(0, str(Path(__file__).parent.parent.parent))
from extract import extract


def get_mxl_path(mxl_path: str) -> Path:
    """Convert database mxl_path to full filesystem path.

    Args:
        mxl_path: Path from database (e.g., "./mxl/1/11/Qmbb...mxl")

    Returns:
        Full path to MXL file
    """
    clean_path = mxl_path.lstrip("./")
    return config.PDMX_PATH / clean_path


def enrich_one(mxl_path: str) -> dict | None:
    """Parse one MXL file and return extracted features.

    Args:
        mxl_path: Path from database

    Returns:
        Dict with features, or None if failed
    """
    full_path = get_mxl_path(mxl_path)
    result = extract(str(full_path))

    if result.get("extraction_status") == "extracted":
        return result
    return None
