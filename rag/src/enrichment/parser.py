"""MusicXML parser using music21.

Extracts musical features from .mxl files:
- Tempo (BPM and text marking)
- Key signature
- Duration
- Pitch ranges per part
"""

from pathlib import Path
from music21 import converter


def parse_mxl(file_path: str | Path) -> dict | None:
    """Parse a MusicXML file and extract features.

    Args:
        file_path: Path to .mxl file

    Returns:
        Dict with extracted features, or None if failed
    """
    path = Path(file_path)

    if not path.exists():
        print(f"File not found: {path}")
        return None

    try:
        score = converter.parse(str(path))
    except Exception as e:
        print(f"Parse error: {e}")
        return None

    result = {}

    # Tempo (BPM)
    try:
        tempos = list(score.metronomeMarkBoundaries())
        if tempos:
            result["tempo_bpm"] = int(tempos[0][2].number)
    except Exception:
        pass

    # Key signature
    try:
        analyzed_key = score.analyze("key")
        result["key"] = str(analyzed_key)
    except Exception:
        pass

    # Duration in seconds
    try:
        quarter_notes = score.duration.quarterLength
        bpm = result.get("tempo_bpm", 120)  # Default 120 if no tempo
        result["duration_seconds"] = int((quarter_notes / bpm) * 60)
    except Exception:
        pass

    # Part ranges
    result["parts"] = []
    for part in score.parts:
        try:
            pitches = [n.pitch for n in part.recurse().notes if hasattr(n, "pitch")]
            if pitches:
                result["parts"].append({
                    "name": part.partName or "Unknown",
                    "lowest": str(min(pitches)),
                    "highest": str(max(pitches)),
                })
        except Exception:
            continue

    # Overall range (across all parts)
    all_pitches = []
    for part in score.parts:
        try:
            pitches = [n.pitch for n in part.recurse().notes if hasattr(n, "pitch")]
            all_pitches.extend(pitches)
        except Exception:
            continue

    if all_pitches:
        result["range_low"] = str(min(all_pitches))
        result["range_high"] = str(max(all_pitches))

    return result
