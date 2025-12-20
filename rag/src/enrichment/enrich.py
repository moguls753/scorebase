"""Enrich scores with MXL-extracted features."""

from pathlib import Path
from . import parser
from .. import config


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
    return parser.parse_mxl(full_path)
