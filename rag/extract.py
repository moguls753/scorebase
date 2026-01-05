#!/usr/bin/env python3
"""
Music21 Feature Extractor for ScoreBase Pro
============================================

Pure function: takes MusicXML file path, outputs JSON to stdout.
No database access - Rails handles all DB operations.

Usage:
    python3 extract.py /path/to/score.mxl
    python3 extract.py /path/to/score.xml

Output:
    JSON object with all extracted features (or error info)
"""

import json
import sys
from collections import Counter
from pathlib import Path

import music21
from music21 import (
    analysis,
    bar,
    chord,
    clef,
    converter,
    dynamics,
    expressions,
    interval,
    meter,
    note,
    pitch,
    roman,
    stream,
    tempo,
)


# ─────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────

VOCAL_KEYWORDS = {
    "soprano", "alto", "tenor", "bass", "baritone", "mezzo",
    "voice", "vocal", "choir", "chorus", "satb", "ssaa", "ttbb",
    "cantus", "discant", "s.", "a.", "t.", "b."
}

KEYBOARD_KEYWORDS = {"piano", "organ", "harpsichord", "keyboard", "clavichord"}

DURATION_NAMES = {
    0.25: "sixteenth",
    0.5: "eighth",
    0.75: "dotted_eighth",
    1.0: "quarter",
    1.5: "dotted_quarter",
    2.0: "half",
    3.0: "dotted_half",
    4.0: "whole",
}


# ─────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────

def get_part_name(part):
    """Extract part name from a Part object."""
    if part.partName:
        return part.partName
    if hasattr(part, "partAbbreviation") and part.partAbbreviation:
        return part.partAbbreviation
    inst = part.getInstrument()
    if inst:
        if inst.partName:
            return inst.partName
        if inst.instrumentName:
            return inst.instrumentName
    return f"Part {part.id}" if part.id else "Unknown"


def safe_round(value, decimals=2):
    """Safely round a value, returning None if not a number."""
    if value is None:
        return None
    try:
        return round(float(value), decimals)
    except (TypeError, ValueError):
        return None


# ─────────────────────────────────────────────────────────────────
# EXTRACTION FUNCTIONS
# ─────────────────────────────────────────────────────────────────

def extract_pitch_range(score, result):
    """Analyze pitch ranges across the score and per part."""
    try:
        all_pitches = list(score.flatten().pitches)
        if not all_pitches:
            return

        sorted_pitches = sorted(all_pitches, key=lambda p: p.ps)
        result["lowest_pitch"] = sorted_pitches[0].nameWithOctave
        result["highest_pitch"] = sorted_pitches[-1].nameWithOctave
        result["ambitus_semitones"] = int(sorted_pitches[-1].ps - sorted_pitches[0].ps)
        result["unique_pitches"] = len(set(p.nameWithOctave for p in all_pitches))

        # Per-part analysis
        pitch_range_per_part = {}
        voice_ranges = {}

        for part in score.parts:
            part_name = get_part_name(part)
            part_pitches = list(part.flatten().pitches)

            if part_pitches:
                sorted_part = sorted(part_pitches, key=lambda p: p.ps)
                low, high = sorted_part[0], sorted_part[-1]
                pitch_range_per_part[part_name] = {
                    "low": low.nameWithOctave,
                    "high": high.nameWithOctave,
                }
                voice_ranges[part_name] = int(high.ps - low.ps)

        result["pitch_range_per_part"] = pitch_range_per_part
        result["voice_ranges"] = voice_ranges

    except Exception as e:
        result["_warnings"].append(f"pitch_range: {e}")


def extract_tempo_duration(score, result):
    """Analyze tempo markings and estimate duration."""
    try:
        # Find tempo markings
        tempos = list(score.flatten().getElementsByClass(tempo.MetronomeMark))
        if tempos:
            first_tempo = tempos[0]
            result["tempo_bpm"] = int(first_tempo.number) if first_tempo.number else None
            if hasattr(first_tempo, "text") and first_tempo.text:
                result["tempo_marking"] = first_tempo.text

        # Fallback: look for tempo text
        if not result.get("tempo_marking"):
            tempo_texts = list(score.flatten().getElementsByClass(tempo.TempoText))
            if tempo_texts:
                result["tempo_marking"] = tempo_texts[0].text

        # Count measures
        if score.parts:
            measures = list(score.parts[0].getElementsByClass(stream.Measure))
            result["measure_count"] = len(measures) if measures else None

        # Estimate duration
        if result.get("tempo_bpm") and result.get("measure_count"):
            ts = list(score.flatten().getElementsByClass(meter.TimeSignature))
            beats_per_measure = ts[0].numerator if ts else 4
            total_beats = result["measure_count"] * beats_per_measure
            result["duration_seconds"] = safe_round((total_beats / result["tempo_bpm"]) * 60)

    except Exception as e:
        result["_warnings"].append(f"tempo_duration: {e}")


def extract_complexity(score, result):
    """Analyze complexity metrics."""
    try:
        notes_list = list(score.flatten().notes)
        result["note_count"] = len(notes_list)

        # Note density
        if result.get("measure_count") and result["measure_count"] > 0:
            result["note_density"] = safe_round(result["note_count"] / result["measure_count"])

        # Count accidentals
        accidental_count = 0
        for n in notes_list:
            if isinstance(n, note.Note) and n.pitch.accidental:
                if n.pitch.accidental.name != "natural":
                    accidental_count += 1
            elif isinstance(n, chord.Chord):
                for p in n.pitches:
                    if p.accidental and p.accidental.name != "natural":
                        accidental_count += 1

        result["accidental_count"] = accidental_count

        # Chromatic complexity
        if result["note_count"] and result["note_count"] > 0:
            result["chromatic_complexity"] = safe_round(
                min(1.0, accidental_count / result["note_count"] * 3)
            )

    except Exception as e:
        result["_warnings"].append(f"complexity: {e}")


def extract_rhythm(score, result):
    """Analyze rhythmic features."""
    try:
        notes_list = list(score.flatten().notes)

        # Duration distribution
        duration_counts = Counter()
        for n in notes_list:
            ql = n.quarterLength
            name = DURATION_NAMES.get(ql, f"other_{ql}")
            duration_counts[name] += 1

        if duration_counts:
            result["rhythm_distribution"] = dict(duration_counts.most_common())
            result["predominant_rhythm"] = duration_counts.most_common(1)[0][0]
            result["rhythmic_variety"] = safe_round(min(1.0, len(duration_counts) / 8))

        # Syncopation estimation
        syncopated = 0
        for n in notes_list:
            if hasattr(n, "beat") and n.beat:
                beat_frac = n.beat % 1
                if beat_frac > 0.1:
                    syncopated += 1

        if notes_list:
            result["syncopation_level"] = safe_round(syncopated / len(notes_list))

    except Exception as e:
        result["_warnings"].append(f"rhythm: {e}")


def extract_harmony(score, result, get_chordified=None):
    """Analyze key, harmony, and chord progressions."""
    try:
        # Key analysis
        analyzed_key = score.analyze("key")
        if analyzed_key:
            result["key_signature"] = f"{analyzed_key.tonic.name} {analyzed_key.mode}"
            result["key_confidence"] = safe_round(analyzed_key.correlationCoefficient, 3)

            # Key correlations (top 5)
            try:
                ka = analysis.discrete.KrumhanslSchmuckler(score)
                ka.getSolution(score)
                if hasattr(ka, "alternativeSolutions"):
                    alts = ka.alternativeSolutions[:5]
                    result["key_correlations"] = {
                        f"{sol.tonic.name} {sol.mode}": safe_round(sol.correlationCoefficient, 3)
                        for sol in alts
                    }
            except Exception:
                pass

        # Modulation detection (analyze key every 8 measures)
        modulations = []
        current_key = None
        if score.parts:
            measures = list(score.parts[0].getElementsByClass(stream.Measure))
            for i in range(0, len(measures), 8):
                chunk = stream.Score()
                for part in score.parts:
                    part_chunk = stream.Part()
                    part_measures = list(part.getElementsByClass(stream.Measure))
                    for m in part_measures[i:i+8]:
                        part_chunk.append(m)
                    if part_chunk.notes:
                        chunk.append(part_chunk)

                if chunk.parts:
                    try:
                        chunk_key = chunk.analyze("key")
                        if chunk_key:
                            key_str = f"{chunk_key.tonic.name} {chunk_key.mode}"
                            if current_key and key_str != current_key:
                                modulations.append(key_str)
                            current_key = key_str
                    except Exception:
                        pass

        if modulations:
            result["modulations"] = " -> ".join([result.get("key_signature", "")] + modulations)
            result["modulation_count"] = len(modulations)

        # Chord analysis
        try:
            chordified = get_chordified() if get_chordified else score.chordify()
            chords = list(chordified.flatten().getElementsByClass(chord.Chord))[:50]
            chord_names = []
            for c in chords:
                try:
                    if analyzed_key:
                        rn = roman.romanNumeralFromChord(c, analyzed_key)
                        chord_names.append(rn.figure)
                except Exception:
                    pass

            if chord_names:
                result["chord_symbols"] = chord_names

            if result.get("measure_count") and result["measure_count"] > 0:
                result["harmonic_rhythm"] = safe_round(len(chords) / result["measure_count"])

        except Exception:
            pass

    except Exception as e:
        result["_warnings"].append(f"harmony: {e}")


def extract_melody(score, result):
    """Analyze melodic features."""
    try:
        if not score.parts:
            return

        melody_part = score.parts[0]
        melody_notes = [n for n in melody_part.flatten().notes if isinstance(n, note.Note)]

        if len(melody_notes) < 2:
            return

        # Interval analysis
        intervals = Counter()
        interval_semitones = []
        stepwise = 0

        for i in range(1, len(melody_notes)):
            try:
                intv = interval.Interval(melody_notes[i-1], melody_notes[i])
                intervals[intv.simpleName] += 1
                semitones = abs(intv.semitones)
                interval_semitones.append(semitones)
                if semitones <= 2:
                    stepwise += 1
            except Exception:
                pass

        if intervals:
            result["interval_distribution"] = dict(intervals.most_common())

        if interval_semitones:
            result["largest_interval"] = max(interval_semitones)
            result["stepwise_motion_ratio"] = safe_round(stepwise / len(interval_semitones))

        # Melodic contour
        if melody_notes:
            first_pitch = melody_notes[0].pitch.ps
            last_pitch = melody_notes[-1].pitch.ps
            middle_idx = len(melody_notes) // 2
            middle_pitch = melody_notes[middle_idx].pitch.ps

            if middle_pitch > first_pitch and middle_pitch > last_pitch:
                result["melodic_contour"] = "arch"
            elif middle_pitch < first_pitch and middle_pitch < last_pitch:
                result["melodic_contour"] = "wave"
            elif last_pitch > first_pitch + 3:
                result["melodic_contour"] = "ascending"
            elif last_pitch < first_pitch - 3:
                result["melodic_contour"] = "descending"
            else:
                result["melodic_contour"] = "static"

        # Melodic complexity score
        complexity_factors = []
        if result.get("largest_interval"):
            complexity_factors.append(min(1.0, result["largest_interval"] / 12))
        if result.get("stepwise_motion_ratio") is not None:
            complexity_factors.append(1.0 - result["stepwise_motion_ratio"])
        if result.get("unique_pitches"):
            complexity_factors.append(min(1.0, result["unique_pitches"] / 20))

        if complexity_factors:
            result["melodic_complexity"] = safe_round(sum(complexity_factors) / len(complexity_factors))

    except Exception as e:
        result["_warnings"].append(f"melody: {e}")


def extract_structure(score, result, get_chordified=None):
    """Analyze structural elements."""
    try:
        # Time signature
        time_sigs = list(score.flatten().getElementsByClass(meter.TimeSignature))
        if time_sigs:
            result["time_signature"] = time_sigs[0].ratioString

        # Count repeats
        repeats = list(score.flatten().getElementsByClass(bar.Repeat))
        result["repeats_count"] = len(repeats)

        # Section detection
        double_bars = list(score.flatten().getElementsByClass(bar.Barline))
        section_markers = [b for b in double_bars if hasattr(b, "type") and "double" in str(b.type).lower()]
        if section_markers:
            result["sections_count"] = len(section_markers) + 1

        # Final cadence detection
        try:
            chordified = get_chordified() if get_chordified else score.chordify()
            final_chords = list(chordified.flatten().getElementsByClass(chord.Chord))[-4:]

            if len(final_chords) >= 2:
                analyzed_key = score.analyze("key")
                if analyzed_key:
                    last_rn = roman.romanNumeralFromChord(final_chords[-1], analyzed_key)
                    second_last_rn = roman.romanNumeralFromChord(final_chords[-2], analyzed_key)

                    if last_rn.romanNumeral == "I" and second_last_rn.romanNumeral in ("V", "V7"):
                        result["final_cadence"] = "PAC"
                    elif last_rn.romanNumeral == "I" and second_last_rn.romanNumeral == "IV":
                        result["final_cadence"] = "plagal"
                    elif last_rn.romanNumeral == "V":
                        result["final_cadence"] = "HC"
                    elif last_rn.romanNumeral == "I":
                        result["final_cadence"] = "IAC"
                    else:
                        result["final_cadence"] = f"{second_last_rn.figure}-{last_rn.figure}"
        except Exception:
            pass

    except Exception as e:
        result["_warnings"].append(f"structure: {e}")


def extract_notation(score, result):
    """Analyze notation features and expressions."""
    try:
        flat = score.flatten()

        # Clefs
        clefs_list = list(flat.getElementsByClass(clef.Clef))
        if clefs_list:
            clef_names = set()
            for c in clefs_list:
                if hasattr(c, "sign"):
                    clef_names.add(c.sign.lower())
            result["clefs_used"] = ", ".join(sorted(clef_names))

        # Dynamics
        dynamics_list = list(flat.getElementsByClass(dynamics.Dynamic))
        result["has_dynamics"] = len(dynamics_list) > 0

        if dynamics_list:
            dyn_values = [d.volumeScalar for d in dynamics_list if hasattr(d, "volumeScalar") and d.volumeScalar]
            if dyn_values:
                min_dyn, max_dyn = min(dyn_values), max(dyn_values)
                dyn_map = {0.1: "ppp", 0.2: "pp", 0.3: "p", 0.5: "mp", 0.6: "mf", 0.75: "f", 0.9: "ff", 1.0: "fff"}

                def closest_dyn(val):
                    return min(dyn_map.keys(), key=lambda x: abs(x - val))

                result["dynamic_range"] = f"{dyn_map[closest_dyn(min_dyn)]}-{dyn_map[closest_dyn(max_dyn)]}"

        # Articulations
        notes_with_artic = [n for n in flat.notes if hasattr(n, "articulations") and n.articulations]
        result["has_articulations"] = len(notes_with_artic) > 0

        # Ornaments
        ornaments = list(flat.getElementsByClass((expressions.Trill, expressions.Mordent, expressions.Turn)))
        result["has_ornaments"] = len(ornaments) > 0

        # Fermatas
        fermatas = list(flat.getElementsByClass(expressions.Fermata))
        result["has_fermatas"] = len(fermatas) > 0

        # Tempo changes
        tempo_changes = list(flat.getElementsByClass(tempo.TempoIndication))
        result["has_tempo_changes"] = len(tempo_changes) > 1

        # Expression text
        text_expressions = list(flat.getElementsByClass(expressions.TextExpression))
        if text_expressions:
            expr_texts = [t.content for t in text_expressions[:10] if hasattr(t, "content") and t.content]
            if expr_texts:
                result["expression_markings"] = ", ".join(expr_texts)

    except Exception as e:
        result["_warnings"].append(f"notation: {e}")


def extract_lyrics(score, result):
    """Extract and analyze lyrics."""
    try:
        all_lyrics = []
        syllable_count = 0

        for part in score.parts:
            for n in part.flatten().notes:
                if hasattr(n, "lyrics") and n.lyrics:
                    for lyric in n.lyrics:
                        if lyric and hasattr(lyric, "text") and lyric.text:
                            all_lyrics.append(lyric.text)
                            syllable_count += 1

        if all_lyrics:
            result["has_extracted_lyrics"] = True
            result["extracted_lyrics"] = " ".join(all_lyrics)
            result["syllable_count"] = syllable_count

            # Detect language
            try:
                from langdetect import detect
                text = result["extracted_lyrics"][:500]
                result["lyrics_language"] = detect(text)
            except Exception:
                # Fallback heuristics
                text_lower = result["extracted_lyrics"].lower()
                if any(w in text_lower for w in ["kyrie", "sanctus", "agnus", "gloria", "amen"]):
                    result["lyrics_language"] = "la"
                elif any(w in text_lower for w in ["the", "and", "of", "to", "lord"]):
                    result["lyrics_language"] = "en"
                elif any(w in text_lower for w in ["und", "der", "die", "das"]):
                    result["lyrics_language"] = "de"
        else:
            result["has_extracted_lyrics"] = False

    except Exception as e:
        result["_warnings"].append(f"lyrics: {e}")


def extract_instrumentation(score, result):
    """Analyze instrumentation and part classification."""
    try:
        result["num_parts"] = len(score.parts)

        part_names = []
        instruments = []
        families = set()

        vocal_parts = 0
        instrumental_parts = 0
        keyboard_parts = 0

        for part in score.parts:
            name = get_part_name(part)
            part_names.append(name)

            inst = part.getInstrument()
            if inst:
                inst_name = inst.instrumentName or inst.partName or name
                instruments.append(inst_name)
                if hasattr(inst, "instrumentFamily") and inst.instrumentFamily:
                    families.add(inst.instrumentFamily)

            name_lower = name.lower()
            if any(v in name_lower for v in VOCAL_KEYWORDS):
                vocal_parts += 1
            elif any(k in name_lower for k in KEYBOARD_KEYWORDS):
                keyboard_parts += 1
            else:
                instrumental_parts += 1

        result["part_names"] = ", ".join(part_names)
        if instruments:
            result["detected_instruments"] = ", ".join(set(instruments))
        if families:
            result["instrument_families"] = ", ".join(families)

        total = len(score.parts)
        result["has_vocal"] = vocal_parts > 0  # Any vocal parts = has_vocal
        result["is_instrumental"] = instrumental_parts > 0 and vocal_parts == 0
        result["has_accompaniment"] = vocal_parts > 0 and (keyboard_parts > 0 or instrumental_parts > 0)

    except Exception as e:
        result["_warnings"].append(f"instrumentation: {e}")


def extract_texture(score, result, get_chordified=None):
    """Analyze musical texture."""
    try:
        if not score.parts:
            return

        num_parts = len(score.parts)

        if num_parts == 1:
            result["texture_type"] = "monophonic"
            result["polyphonic_density"] = 0.0
            result["voice_independence"] = 0.0
            return

        chordified = get_chordified() if get_chordified else score.chordify()
        chords = list(chordified.flatten().getElementsByClass(chord.Chord))[:100]

        if not chords:
            return

        avg_notes = sum(len(c.pitches) for c in chords) / len(chords)
        result["polyphonic_density"] = safe_round(avg_notes / num_parts)

        # Voice independence
        parallel_motion = 0
        for i in range(1, min(len(chords), 50)):
            prev_pitches = sorted(chords[i-1].pitches, key=lambda p: p.ps)
            curr_pitches = sorted(chords[i].pitches, key=lambda p: p.ps)

            if len(prev_pitches) == len(curr_pitches) and len(prev_pitches) > 1:
                movements = [curr_pitches[j].ps - prev_pitches[j].ps for j in range(len(prev_pitches))]
                if movements and (all(m > 0 for m in movements) or all(m < 0 for m in movements)):
                    parallel_motion += 1

        independence = 1.0 - (parallel_motion / max(1, min(len(chords) - 1, 49)))
        result["voice_independence"] = safe_round(independence)

        # Classify texture
        if num_parts == 1:
            result["texture_type"] = "monophonic"
        elif result["polyphonic_density"] < 0.3:
            result["texture_type"] = "monophonic"
        elif result["voice_independence"] < 0.3:
            result["texture_type"] = "homophonic"
        elif result["voice_independence"] > 0.7:
            result["texture_type"] = "polyphonic"
        else:
            result["texture_type"] = "mixed"

    except Exception as e:
        result["_warnings"].append(f"texture: {e}")


def extract_hand_span(score, result):
    """
    Find the largest simultaneous chord span in semitones.
    Only relevant for keyboard instruments.

    Use cases:
        - "Piano pieces for small hands" (span < 9)
        - "No large stretches" (span < 12)
    """
    try:
        max_span = 0

        for part in score.parts:
            part_name = get_part_name(part).lower()
            if not any(k in part_name for k in KEYBOARD_KEYWORDS):
                continue

            for c in part.flatten().getElementsByClass(chord.Chord):
                if len(c.pitches) >= 2:
                    pitches_sorted = sorted(c.pitches, key=lambda p: p.ps)
                    span = int(pitches_sorted[-1].ps - pitches_sorted[0].ps)
                    max_span = max(max_span, span)

        if max_span > 0:
            result["max_chord_span"] = max_span

    except Exception as e:
        result["_warnings"].append(f"hand_span: {e}")


def extract_tessitura(score, result):
    """
    Calculate average pitch (tessitura) for each part.
    More useful than just min/max range for vocal queries.

    Use cases:
        - "Comfortable for alto" (tessitura avg 60-72 MIDI)
        - "Doesn't sit too high for soprano"
    """
    try:
        tessitura = {}

        for part in score.parts:
            part_name = get_part_name(part)
            pitches = [n.pitch.ps for n in part.flatten().notes if isinstance(n, note.Note)]

            if pitches:
                avg_pitch = sum(pitches) / len(pitches)
                avg_note = pitch.Pitch()
                avg_note.ps = avg_pitch

                tessitura[part_name] = {
                    "average_pitch": avg_note.nameWithOctave,
                    "average_midi": round(avg_pitch, 1)
                }

        if tessitura:
            result["tessitura"] = tessitura

    except Exception as e:
        result["_warnings"].append(f"tessitura: {e}")


def extract_register_shifts(score, result):
    """
    Count large melodic jumps (>5 semitones) that indicate position changes.
    Relevant for strings, winds, brass - indicates technical difficulty.

    Use cases:
        - "No position changes" (beginner pieces)
        - "Stays in one position" (shift_count low)
    """
    try:
        shift_count = 0

        for part in score.parts:
            notes_list = [n for n in part.flatten().notes if isinstance(n, note.Note)]

            for i in range(1, len(notes_list)):
                interval_size = abs(notes_list[i].pitch.ps - notes_list[i-1].pitch.ps)
                if interval_size > 5:  # Larger than fourth
                    shift_count += 1

        if shift_count > 0:
            result["position_shift_count"] = shift_count

            if result.get("measure_count") and result["measure_count"] > 0:
                result["position_shifts_per_measure"] = round(
                    shift_count / result["measure_count"], 2
                )

    except Exception as e:
        result["_warnings"].append(f"register_shifts: {e}")


def compute_difficulty_score(result) -> int:
    """
    Compute difficulty score (1-5) based on ALL extracted metrics.

    Returns:
        1 = Beginner, 2 = Easy, 3 = Intermediate, 4 = Advanced, 5 = Expert

    Scoring (0-13 points):
        - Note density: 0-2, Chromatic: 0-2, Rhythm: 0-2, Melodic: 0-2
        - Tempo: 0-1, Modulations: 0-1, Polyphony: 0-1, Hand span: 0-1, Shifts: 0-1
    """
    def get(key, default=0):
        """Get value from result, treating None as default."""
        val = result.get(key)
        return default if val is None else val

    points = 0

    # Note Density (0-2)
    density = get("note_density")
    if density > 20:
        points += 2
    elif density > 10:
        points += 1

    # Chromatic Complexity (0-2)
    chromatic = get("chromatic_complexity")
    if chromatic > 0.3:
        points += 2
    elif chromatic > 0.15:
        points += 1

    # Rhythm Complexity (0-2)
    if get("syncopation_level") > 0.3:
        points += 1
    if get("rhythmic_variety") > 0.7:
        points += 1

    # Melodic Intervals (0-2)
    largest = get("largest_interval")
    if largest > 12:
        points += 2
    elif largest > 7:
        points += 1

    # Tempo (0-1)
    if get("tempo_bpm", 120) > 150:
        points += 1

    # Modulations (0-1)
    if get("modulation_count") > 2:
        points += 1

    # Polyphony (0-1)
    if get("voice_independence") > 0.7:
        points += 1

    # Hand Span - Piano (0-1)
    if get("max_chord_span") > 12:
        points += 1

    # Position Shifts (0-1)
    if get("position_shifts_per_measure") > 0.5:
        points += 1

    # Map to 1-5
    if points <= 2:
        return 1
    elif points <= 5:
        return 2
    elif points <= 8:
        return 3
    elif points <= 11:
        return 4
    else:
        return 5


# ─────────────────────────────────────────────────────────────────
# MAIN EXTRACTION
# ─────────────────────────────────────────────────────────────────

def extract(file_path: str) -> dict:
    """
    Extract all features from a MusicXML file.

    Args:
        file_path: Path to MusicXML file (.mxl, .xml, .musicxml)

    Returns:
        Dictionary with all extracted features
    """
    result = {
        "extraction_status": "pending",
        "extraction_error": None,
        "music21_version": music21.VERSION_STR,
        "musicxml_source": Path(file_path).suffix.lstrip("."),
        "_warnings": [],
    }

    try:
        score = converter.parse(file_path)

        if not isinstance(score, stream.Score):
            wrapper = stream.Score()
            wrapper.append(score)
            score = wrapper

        # Cache chordify - expensive operation used by 3 functions
        _chordified_cache = None

        def get_chordified():
            nonlocal _chordified_cache
            if _chordified_cache is None:
                _chordified_cache = score.chordify()
            return _chordified_cache

        # Run all extractions
        extract_pitch_range(score, result)
        extract_tempo_duration(score, result)
        extract_complexity(score, result)
        extract_rhythm(score, result)
        extract_harmony(score, result, get_chordified)
        extract_melody(score, result)
        extract_structure(score, result, get_chordified)
        extract_notation(score, result)
        extract_lyrics(score, result)
        extract_instrumentation(score, result)
        extract_texture(score, result, get_chordified)

        # New extractions
        extract_hand_span(score, result)
        extract_tessitura(score, result)
        extract_register_shifts(score, result)

        # Compute final difficulty from all metrics
        result["computed_difficulty"] = compute_difficulty_score(result)

        result["extraction_status"] = "extracted"

    except Exception as e:
        result["extraction_status"] = "failed"
        result["extraction_error"] = str(e)[:1000]

    # Clean up internal fields
    warnings = result.pop("_warnings", [])
    if warnings:
        result["_extraction_warnings"] = warnings

    return result


# ─────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(json.dumps({
            "extraction_status": "failed",
            "extraction_error": "Usage: python3 extract.py <path_to_musicxml>"
        }))
        sys.exit(1)

    file_path = sys.argv[1]

    if not Path(file_path).exists():
        print(json.dumps({
            "extraction_status": "failed",
            "extraction_error": f"File not found: {file_path}"
        }))
        sys.exit(1)

    result = extract(file_path)
    print(json.dumps(result, ensure_ascii=False))
