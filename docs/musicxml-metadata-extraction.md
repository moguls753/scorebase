# MusicXML Metadata Extraction for RAG

## Overview

MusicXML files (`.mxl`, `.musicxml`) contain rich musical data that can fill metadata gaps in the RAG system. This enables queries that require duration, vocal ranges, and difficulty analysis.

## Available Data

| Field | Extraction Method | Use Case |
|-------|-------------------|----------|
| Duration | Sum measures × tempo | "pieces around 10 minutes" |
| Vocal range per part | Min/max pitch | "soprano not above A4" |
| Tempo | Metronome markings | "slow piece", "allegro" |
| Note density | Notes per measure | Difficulty estimation |
| Rhythm complexity | Tuplets, syncopation | Difficulty estimation |
| Interval jumps | Consecutive pitch distance | "no large leaps" |
| Key changes | Key signature events | Difficulty signal |
| Dynamics range | pp to ff markings | "dramatic", "subtle" |

## Python Libraries

### music21 (recommended)
Most comprehensive, music-theory aware:
```bash
pip install music21
```

### lxml (alternative)
Raw XML parsing, faster but manual:
```bash
pip install lxml
```

## Code Examples

### Basic Parsing with music21

```python
from music21 import converter, pitch

def extract_metadata(mxl_path: str) -> dict:
    score = converter.parse(mxl_path)

    return {
        "duration_seconds": get_duration(score),
        "part_ranges": get_part_ranges(score),
        "tempo_bpm": get_tempo(score),
        "difficulty_score": estimate_difficulty(score),
    }
```

### Duration Extraction

```python
def get_duration(score) -> float:
    """Returns duration in seconds."""
    # Get tempo (default 120 if not specified)
    tempo_marks = score.metronomeMarkBoundaries()
    bpm = tempo_marks[0][2].number if tempo_marks else 120

    # Quarter notes to seconds
    quarter_notes = score.duration.quarterLength
    seconds = (quarter_notes / bpm) * 60

    return round(seconds, 1)
```

### Vocal/Instrument Range Extraction

```python
def get_part_ranges(score) -> dict:
    """Returns pitch range for each part."""
    ranges = {}

    for part in score.parts:
        pitches = [n.pitch for n in part.recurse().notes]
        if pitches:
            ranges[part.partName or f"Part {part.id}"] = {
                "low": str(min(pitches)),   # e.g., "C4"
                "high": str(max(pitches)),  # e.g., "A5"
                "low_midi": min(p.midi for p in pitches),
                "high_midi": max(p.midi for p in pitches),
            }

    return ranges
```

### Tempo Extraction

```python
def get_tempo(score) -> int | None:
    """Returns primary tempo in BPM."""
    for el in score.recurse():
        if hasattr(el, 'number') and el.classes[0] == 'MetronomeMark':
            return int(el.number)
    return None
```

### Difficulty Estimation

```python
def estimate_difficulty(score) -> int:
    """
    Returns difficulty 1-5 based on musical features.
    This is a heuristic - adjust weights as needed.
    """
    factors = {
        "note_density": 0,
        "rhythm_complexity": 0,
        "range_span": 0,
        "accidentals": 0,
        "key_changes": 0,
    }

    notes = list(score.recurse().notes)
    measures = len(list(score.parts[0].getElementsByClass('Measure')))

    # Note density (notes per measure)
    density = len(notes) / max(measures, 1)
    if density > 20:
        factors["note_density"] = 2
    elif density > 10:
        factors["note_density"] = 1

    # Rhythm complexity (tuplets, dotted rhythms)
    tuplets = sum(1 for n in notes if n.duration.tuplets)
    if tuplets > len(notes) * 0.1:
        factors["rhythm_complexity"] = 1

    # Range span per part
    for part in score.parts:
        pitches = [n.pitch.midi for n in part.recurse().notes]
        if pitches:
            span = max(pitches) - min(pitches)
            if span > 24:  # More than 2 octaves
                factors["range_span"] = 1
                break

    # Accidentals count
    accidentals = sum(1 for n in notes if n.pitch.accidental)
    if accidentals > len(notes) * 0.15:
        factors["accidentals"] = 1

    # Map to 1-5 scale
    total = sum(factors.values())
    if total <= 1:
        return 1  # Beginner
    elif total <= 2:
        return 2  # Easy
    elif total <= 3:
        return 3  # Intermediate
    elif total <= 4:
        return 4  # Advanced
    else:
        return 5  # Expert

```

## Schema Fields to Add

```ruby
# Migration suggestion
add_column :scores, :duration_seconds, :integer
add_column :scores, :tempo_bpm, :integer
add_column :scores, :range_low, :string   # e.g., "C4"
add_column :scores, :range_high, :string  # e.g., "A5"
add_column :scores, :range_low_midi, :integer
add_column :scores, :range_high_midi, :integer
add_column :scores, :computed_difficulty, :integer
```

## Batch Processing

```python
import os
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor

def process_all_scores(mxl_directory: str, output_csv: str):
    """Process all MusicXML files in parallel."""
    mxl_files = list(Path(mxl_directory).glob("**/*.mxl"))

    with ProcessPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(extract_metadata, mxl_files))

    # Save to CSV for import into Rails
    import csv
    with open(output_csv, 'w') as f:
        writer = csv.DictWriter(f, fieldnames=results[0].keys())
        writer.writeheader()
        writer.writerows(results)
```

## RAG Query Examples This Enables

With extracted metadata, these queries become answerable:

- "Pieces around 5 minutes long" → filter by `duration_seconds`
- "Soprano part stays below B5" → filter by `range_high_midi < 83`
- "Easy Bach for beginners" → filter by `computed_difficulty <= 2`
- "Fast, virtuosic piece" → filter by `tempo_bpm > 140` + high difficulty
- "Comfortable range for alto" → filter `range_low_midi >= 53` (F3) AND `range_high_midi <= 77` (F5)

## MIDI Note Reference

| Note | MIDI |
|------|------|
| C4 (middle C) | 60 |
| A4 (concert pitch) | 69 |
| C5 | 72 |
| A5 | 81 |
| B5 | 83 |

## Notes

- Not all scores have MusicXML files - check `mxl_path` presence
- music21 is slow for large files; consider caching parsed results
- Some MusicXML files may be malformed - wrap parsing in try/except
- Duration calculation assumes constant tempo; multi-tempo pieces need more logic
