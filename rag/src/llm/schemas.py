"""Pydantic schemas for score description generation.

ScoreMetadata: Input schema matching Rails Score model + music21 extraction.
DifficultyMapping: Maps melodic_complexity (0-1) to difficulty levels.
"""

from pydantic import BaseModel
from typing import Any


class ScoreMetadata(BaseModel):
    """Score metadata from Rails database + music21 extraction.

    All fields optional except id - not every score has all metadata.
    """

    # Required
    id: int

    # Basic info
    title: str | None = None
    composer: str | None = None
    description: str | None = None
    genres: str | None = None
    tags: str | None = None

    # Instrumentation
    instruments: str | None = None
    voicing: str | None = None
    is_vocal: bool | None = None
    is_instrumental: bool | None = None
    has_accompaniment: bool | None = None
    num_parts: int | None = None
    part_names: str | None = None
    detected_instruments: str | None = None
    instrument_families: str | None = None

    # Key & time
    key_signature: str | None = None
    time_signature: str | None = None
    key_confidence: float | None = None

    # Tempo & duration
    tempo_bpm: int | None = None
    tempo_marking: str | None = None
    duration_seconds: float | None = None
    measure_count: int | None = None

    # Complexity (melodic_complexity is primary for difficulty)
    complexity: int | None = None
    melodic_complexity: float | None = None
    chromatic_complexity: float | None = None
    rhythmic_variety: float | None = None
    syncopation_level: float | None = None
    note_count: int | None = None
    note_density: float | None = None
    unique_pitches: int | None = None
    accidental_count: int | None = None

    # Range
    highest_pitch: str | None = None
    lowest_pitch: str | None = None
    ambitus_semitones: int | None = None
    voice_ranges: dict | None = None
    pitch_range_per_part: dict | None = None

    # Rhythm
    predominant_rhythm: str | None = None
    rhythm_distribution: dict | None = None

    # Melody
    melodic_contour: str | None = None
    largest_interval: int | None = None
    stepwise_motion_ratio: float | None = None

    # Texture
    texture_type: str | None = None
    polyphonic_density: float | None = None
    voice_independence: float | None = None

    # Notation & expression
    has_dynamics: bool | None = None
    dynamic_range: str | None = None
    has_articulations: bool | None = None
    has_ornaments: bool | None = None
    has_tempo_changes: bool | None = None
    has_fermatas: bool | None = None
    expression_markings: str | None = None
    clefs_used: str | None = None

    # Harmony
    modulation_count: int | None = None
    modulations: str | None = None
    final_cadence: str | None = None
    harmonic_rhythm: float | None = None
    key_correlations: dict | None = None
    chord_symbols: list | None = None

    # Form & structure
    form_analysis: str | None = None
    sections_count: int | None = None
    repeats_count: int | None = None
    cadence_types: str | None = None

    # Lyrics
    has_extracted_lyrics: bool | None = None
    extracted_lyrics: str | None = None
    syllable_count: int | None = None
    lyrics_language: str | None = None

    def get_non_null_fields(self) -> dict[str, Any]:
        """Return dict of only non-null fields for LLM prompt."""
        return {k: v for k, v in self.model_dump().items() if v is not None}


class DifficultyMapping:
    """Map melodic_complexity (0-1) to difficulty level.

    Thresholds based on music21 melodic complexity analysis:
    - < 0.3: Beginner (easy, simple)
    - 0.3-0.5: Intermediate (moderate)
    - 0.5-0.7: Advanced (challenging)
    - > 0.7: Virtuoso (demanding)
    """

    THRESHOLDS = {
        "beginner": (0.0, 0.3),
        "intermediate": (0.3, 0.5),
        "advanced": (0.5, 0.7),
        "virtuoso": (0.7, 1.0),
    }

    WORDS = {
        "beginner": ["easy", "beginner", "simple", "accessible"],
        "intermediate": ["intermediate", "moderate", "developing"],
        "advanced": ["advanced", "challenging", "demanding"],
        "virtuoso": ["virtuoso", "technically demanding", "expert"],
    }

    @classmethod
    def get_level(cls, melodic_complexity: float | None) -> str:
        """Get difficulty level from melodic_complexity score."""
        if melodic_complexity is None:
            return "intermediate"

        for level, (low, high) in cls.THRESHOLDS.items():
            if low <= melodic_complexity < high:
                return level
        return "virtuoso"

    @classmethod
    def get_words(cls, level: str) -> list[str]:
        """Get difficulty words for a level."""
        return cls.WORDS.get(level, cls.WORDS["intermediate"])
