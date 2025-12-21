"""Database access for Rails SQLite."""

import sqlite3
from . import config

# All fields useful for RAG embedding
SCORE_FIELDS = """
    id, title, composer, instruments, voicing, genres, tags, description,

    -- Key and time
    key_signature, time_signature,

    -- Complexity metrics
    complexity, melodic_complexity, chromatic_complexity,
    rhythmic_variety, syncopation_level,

    -- Texture and structure
    texture_type, polyphonic_density, voice_independence,
    measure_count, note_count, note_density, num_parts,

    -- Range
    lowest_pitch, highest_pitch, ambitus_semitones,

    -- Tempo and duration
    tempo_bpm, tempo_marking, duration_seconds,

    -- Melodic characteristics
    melodic_contour, largest_interval, stepwise_motion_ratio,

    -- Expression and notation
    has_dynamics, dynamic_range, has_articulations, has_ornaments,
    has_fermatas, has_tempo_changes, expression_markings,

    -- Harmony
    modulation_count, final_cadence, harmonic_rhythm,

    -- Instrumentation
    is_vocal, is_instrumental, has_accompaniment,
    detected_instruments, instrument_families, part_names,

    -- Lyrics
    has_extracted_lyrics, lyrics_language,

    -- Extraction status
    extraction_status
"""


def get_connection():
    """Get SQLite connection to Rails database."""
    return sqlite3.connect(config.RAILS_DB_PATH)


def get_extracted_scores(limit: int = 100) -> list[dict]:
    """Fetch extracted scores with all music21 fields.

    Args:
        limit: Maximum scores to return

    Returns:
        List of score dicts with rich metadata
    """
    conn = get_connection()
    conn.row_factory = sqlite3.Row

    cursor = conn.execute(f"""
        SELECT {SCORE_FIELDS}
        FROM scores
        WHERE extraction_status = 'extracted'
        ORDER BY id
        LIMIT ?
    """, [limit])

    scores = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return scores


def get_all_extracted_scores() -> list[dict]:
    """Fetch all extracted scores (for full indexing)."""
    conn = get_connection()
    conn.row_factory = sqlite3.Row

    cursor = conn.execute(f"""
        SELECT {SCORE_FIELDS}
        FROM scores
        WHERE extraction_status = 'extracted'
        ORDER BY id
    """)

    scores = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return scores


def get_scores(limit: int = 100) -> list[dict]:
    """Fetch scores from database (legacy, basic fields only).

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


def get_score_count() -> int:
    """Get total score count."""
    conn = get_connection()
    count = conn.execute("SELECT COUNT(*) FROM scores").fetchone()[0]
    conn.close()
    return count


def get_extracted_count() -> int:
    """Get count of extracted scores."""
    conn = get_connection()
    count = conn.execute(
        "SELECT COUNT(*) FROM scores WHERE extraction_status = 'extracted'"
    ).fetchone()[0]
    conn.close()
    return count
