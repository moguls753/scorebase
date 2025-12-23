"""Database access for Rails SQLite."""

import sqlite3
from . import config


def get_connection():
    """Get SQLite connection to Rails database."""
    return sqlite3.connect(config.RAILS_DB_PATH)


def get_templated_scores(limit: int = 100) -> list[dict]:
    """Fetch scores with search_text ready for indexing.

    Args:
        limit: Maximum scores to return (-1 for all)

    Returns:
        List of score dicts with id, title, search_text
    """
    conn = get_connection()
    conn.row_factory = sqlite3.Row

    if limit > 0:
        cursor = conn.execute("""
            SELECT id, title, search_text
            FROM scores
            WHERE rag_status = 'templated'
            AND search_text IS NOT NULL
            AND search_text != ''
            ORDER BY id
            LIMIT ?
        """, [limit])
    else:
        cursor = conn.execute("""
            SELECT id, title, search_text
            FROM scores
            WHERE rag_status = 'templated'
            AND search_text IS NOT NULL
            AND search_text != ''
            ORDER BY id
        """)

    scores = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return scores


def get_scores_by_ids(ids: list[int]) -> list[dict]:
    """Fetch specific scores by ID.

    Args:
        ids: List of score IDs to fetch

    Returns:
        List of score dicts with id, title, search_text
    """
    if not ids:
        return []

    conn = get_connection()
    conn.row_factory = sqlite3.Row

    placeholders = ",".join("?" * len(ids))
    cursor = conn.execute(f"""
        SELECT id, title, search_text
        FROM scores
        WHERE id IN ({placeholders})
        AND search_text IS NOT NULL
        ORDER BY id
    """, ids)

    scores = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return scores


def mark_indexed(score_ids: list[int]) -> int:
    """Mark scores as indexed in Rails database.

    Args:
        score_ids: List of score IDs to mark

    Returns:
        Number of rows updated
    """
    if not score_ids:
        return 0

    conn = get_connection()
    placeholders = ",".join("?" * len(score_ids))
    cursor = conn.execute(f"""
        UPDATE scores
        SET rag_status = 'indexed', indexed_at = datetime('now')
        WHERE id IN ({placeholders})
    """, score_ids)
    conn.commit()
    count = cursor.rowcount
    conn.close()
    return count


def get_stats() -> dict:
    """Get RAG pipeline stats."""
    conn = get_connection()

    stats = {}
    cursor = conn.execute("""
        SELECT rag_status, COUNT(*) as count
        FROM scores
        GROUP BY rag_status
    """)
    for row in cursor.fetchall():
        stats[row[0] or "null"] = row[1]

    conn.close()
    return stats
