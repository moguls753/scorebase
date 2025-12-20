"""Database access for Rails SQLite."""

import sqlite3
from . import config


def get_connection():
    """Get SQLite connection to Rails database."""
    return sqlite3.connect(config.RAILS_DB_PATH)


def get_scores(limit: int = 100) -> list[dict]:
    """Fetch scores from database.

    Args:
        limit: Maximum scores to return

    Returns:
        List of score dicts
    """
    conn = get_connection()
    conn.row_factory = sqlite3.Row

    cursor = conn.execute("""
        SELECT id, title, composer, instruments, voicing,
               genres, tags, description, mxl_path
        FROM scores
        WHERE mxl_path IS NOT NULL AND mxl_path != ''
        LIMIT ?
    """, [limit])

    scores = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return scores


def get_all_scores() -> list[dict]:
    """Fetch all scores (for full indexing)."""
    conn = get_connection()
    conn.row_factory = sqlite3.Row

    cursor = conn.execute("""
        SELECT id, title, composer, instruments, voicing,
               genres, tags, description, mxl_path
        FROM scores
    """)

    scores = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return scores


def get_score_count() -> int:
    """Get total score count."""
    conn = get_connection()
    count = conn.execute("SELECT COUNT(*) FROM scores").fetchone()[0]
    conn.close()
    return count
