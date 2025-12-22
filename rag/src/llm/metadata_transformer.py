"""Transform raw score metadata to prompt-ready categorical values.

Converts numeric values to descriptive categories that work well in LLM prompts.
This is the single source of truth for metadata → prompt transformation.
"""

from typing import Any


# Difficulty words by level - used directly in prompts
DIFFICULTY_WORDS = {
    "beginner": ["easy", "beginner", "simple"],
    "intermediate": ["intermediate", "moderate"],
    "advanced": ["advanced", "challenging"],
    "virtuoso": ["virtuoso", "technically demanding", "expert"],
}

# Human-readable mappings
CLEF_NAMES = {"f": "bass", "g": "treble", "c": "alto"}
CADENCE_NAMES = {
    "PAC": "perfect authentic cadence",
    "IAC": "imperfect authentic cadence",
    "HC": "half cadence",
    "plagal": "plagal cadence",
}
TIME_SIG_NAMES = {
    "4/4": "four-four (common time)",
    "3/4": "three-four (waltz time)",
    "2/4": "two-four",
    "6/8": "six-eight",
    "2/2": "cut time",
}


def _bucket(value: float | int | None, cuts: list, labels: list) -> str | None:
    """Map numeric value to categorical label based on thresholds."""
    if value is None or not labels:
        return None
    for cut, label in zip(cuts, labels):
        if value <= cut:
            return label
    return labels[-1]


def _bucket_01(value: float | None) -> str | None:
    """Map 0-1 float to low/medium/high."""
    if value is None:
        return None
    if value < 0.33:
        return "low"
    if value < 0.66:
        return "medium"
    return "high"


def _get_difficulty(melodic_complexity: float | None) -> list[str]:
    """Map melodic_complexity (0-1) directly to difficulty words."""
    if melodic_complexity is None:
        return DIFFICULTY_WORDS["intermediate"]
    if melodic_complexity < 0.3:
        return DIFFICULTY_WORDS["beginner"]
    if melodic_complexity < 0.5:
        return DIFFICULTY_WORDS["intermediate"]
    if melodic_complexity < 0.7:
        return DIFFICULTY_WORDS["advanced"]
    return DIFFICULTY_WORDS["virtuoso"]


def _top_items(dist: dict | None, k: int = 3, prefix: str = "predominantly") -> str | None:
    """Summarize distribution dict as 'predominantly X with frequent Y and Z'."""
    if not dist:
        return None
    items = sorted(dist.items(), key=lambda kv: kv[1], reverse=True)[:k]
    names = [name for name, _ in items]
    if len(names) == 1:
        return f"{prefix} {names[0]}"
    if len(names) == 2:
        return f"{prefix} {names[0]} with frequent {names[1]}"
    return f"{prefix} {names[0]} with frequent {names[1]} and {names[2]}"


def _map_clefs(clefs: str | None) -> str | None:
    """Convert 'f, g' to 'bass and treble'."""
    if not clefs:
        return None
    parts = [c.strip().lower() for c in clefs.split(",")]
    names = [CLEF_NAMES.get(p, p) for p in parts]
    return " and ".join(names)


def _map_cadence(cadence: str | None) -> str | None:
    """Convert 'PAC' to 'perfect authentic cadence'."""
    if not cadence:
        return None
    return CADENCE_NAMES.get(cadence, cadence)


def _map_time_sig(ts: str | None) -> str | None:
    """Convert '4/4' to 'four-four (common time)'."""
    if not ts:
        return None
    return TIME_SIG_NAMES.get(ts, ts)


def _map_interval(code: str) -> str:
    """Convert 'M2' to 'major second'."""
    quality_map = {"M": "major", "m": "minor", "P": "perfect", "A": "augmented", "d": "diminished"}
    interval_map = {"1": "unison", "2": "second", "3": "third", "4": "fourth",
                    "5": "fifth", "6": "sixth", "7": "seventh", "8": "octave"}
    if len(code) >= 2:
        quality = quality_map.get(code[0], code[0])
        interval = interval_map.get(code[1:], code[1:])
        return f"{quality} {interval}"
    return code


def transform_metadata(raw: dict[str, Any]) -> dict[str, Any]:
    """Transform raw metadata to prompt-ready categorical format.

    Args:
        raw: Raw metadata dict from database/extraction

    Returns:
        Dict with categorical values ready for LLM prompt
    """
    def get(key: str, default=None):
        return raw.get(key, default)

    out = {}

    # Pass through text fields as-is
    for key in ["title", "composer", "genres", "tags"]:
        val = get(key)
        if val and val != "NA":
            out[key] = val

    # Transformed text fields
    out["key_signature"] = get("key_signature")
    out["time_signature"] = _map_time_sig(get("time_signature"))
    out["clefs_used"] = _map_clefs(get("clefs_used"))
    out["final_cadence"] = _map_cadence(get("final_cadence"))

    # Difficulty - the key field
    out["difficulty_level"] = _get_difficulty(get("melodic_complexity"))

    # Categorical conversions
    out["num_parts"] = _bucket(get("num_parts"), [1, 2, 4, 8],
                               ["solo", "duo", "small_ensemble", "ensemble", "large_ensemble"])
    out["page_count"] = _bucket(get("page_count"), [1, 3, 7, 15],
                                ["very_short", "short", "medium", "long", "very_long"])
    out["ambitus"] = _bucket(get("ambitus_semitones"), [12, 24, 36],
                             ["narrow", "moderate", "wide", "very_wide"])
    out["length_in_measures"] = _bucket(get("measure_count"), [32, 80, 160],
                                        ["short", "medium", "long", "very_long"])
    out["note_event_density"] = _bucket(get("note_density"), [8, 16, 32],
                                        ["low", "medium", "high", "very_high"])
    out["pitch_palette"] = _bucket(get("unique_pitches"), [12, 24, 36],
                                   ["limited", "moderate", "wide", "very_wide"])
    out["accidentals_usage"] = _bucket(get("accidental_count"), [20, 100, 300],
                                       ["low", "medium", "high", "very_high"])

    # 0-1 scale fields
    out["chromaticism"] = _bucket_01(get("chromatic_complexity"))
    out["syncopation"] = _bucket_01(get("syncopation_level"))
    out["rhythmic_variety"] = _bucket_01(get("rhythmic_variety"))
    out["melodic_complexity"] = _bucket_01(get("melodic_complexity"))
    out["polyphonic_density"] = _bucket(get("polyphonic_density"), [1.1, 1.4, 1.8],
                                        ["low", "medium", "high", "very_high"])
    out["voice_independence"] = _bucket_01(get("voice_independence"))

    # Distribution summaries
    out["rhythm_distribution"] = _top_items(get("rhythm_distribution"), prefix="predominantly")

    interval_dist = get("interval_distribution")
    if interval_dist:
        # Convert codes to readable names
        readable = {_map_interval(k): v for k, v in interval_dist.items()}
        out["interval_profile"] = _top_items(readable, prefix="mostly")

    # Stepwise motion
    smr = get("stepwise_motion_ratio")
    if smr is not None:
        out["melodic_motion"] = "stepwise" if smr >= 0.6 else ("mixed" if smr >= 0.4 else "leapy")

    # Largest melodic leap
    out["largest_leap"] = _bucket(get("largest_interval"), [4, 9, 12],
                                  ["small", "medium", "large", "very_large"])

    # Other categoricals
    out["predominant_rhythm"] = get("predominant_rhythm")
    out["melodic_contour"] = get("melodic_contour")
    out["texture_type"] = get("texture_type")

    # Repeats
    rc = get("repeats_count")
    if rc is not None:
        out["repeats"] = "none" if rc == 0 else ("few" if rc <= 2 else "some")

    # Register info - use pitch names to determine register
    hp, lp = get("highest_pitch"), get("lowest_pitch")
    if hp:
        out["highest_register"] = "very_high" if "6" in hp or "7" in hp else ("high" if "5" in hp else "moderate")
    if lp:
        out["lowest_register"] = "very_low" if "1" in lp or "2" in lp else ("low" if "3" in lp else "moderate")

    # Voice ranges per part
    vr = get("voice_ranges")
    if vr:
        out["voice_ranges"] = {
            part: _bucket(semitones, [12, 24, 36], ["narrow", "moderate", "wide", "very_wide"])
            for part, semitones in vr.items()
        }

    # Pitch range per part
    prpp = get("pitch_range_per_part")
    if prpp:
        out["pitch_range_per_part"] = {}
        for part, rng in prpp.items():
            if isinstance(rng, dict):
                low, high = rng.get("low"), rng.get("high")
                range_semitones = vr.get(part) if vr else None
                out["pitch_range_per_part"][part] = {
                    "range": _bucket(range_semitones, [12, 24, 36],
                                     ["narrow", "moderate", "wide", "very_wide"]),
                    "low_register": "very_low" if low and ("1" in low or "2" in low) else "low",
                    "high_register": "very_high" if high and ("6" in high or "7" in high) else "high",
                }

    # Boolean fields
    for key in ["has_dynamics", "has_articulations", "has_ornaments",
                "has_tempo_changes", "has_fermatas", "has_extracted_lyrics",
                "is_vocal", "is_instrumental", "has_accompaniment"]:
        val = get(key)
        if val is not None:
            out[key] = val

    # Instrumentation
    out["part_names"] = get("part_names")
    out["detected_instruments"] = get("detected_instruments")

    # Remove None values
    return {k: v for k, v in out.items() if v is not None}
