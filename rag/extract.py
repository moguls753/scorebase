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
    spanner,
    stream,
    tempo,
)


# ─────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────

# Movement/section names that indicate multi-movement works.
# If these appear in expression_markings, tempo/duration are unreliable
# because they only refer to one movement, not the whole piece.
MOVEMENT_NAMES = {
    "allemande", "courante", "sarabande", "gigue", "menuet", "menuetto",
    "minuet", "gavotte", "bourree", "bourrée", "prelude", "fugue",
    "praeludium", "fuga", "air", "trio", "rondo", "scherzo", "finale",
    "toccata", "passepied", "loure", "anglaise", "polonaise", "badinerie",
    "overture", "ouverture", "intermezzo", "siciliano", "sicilienne",
    "passacaglia", "chaconne", "fantasia", "ricercar", "invention", "sinfonia",
}

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
# CACHING
# ─────────────────────────────────────────────────────────────────

class ScoreCache:
    """
    Cache expensive operations for a single score.
    Dramatically reduces redundant computation.

    Usage:
        cache = ScoreCache(score)
        flat = cache.flat          # Cached after first access
        notes = cache.notes        # Cached after first access
        chordified = cache.chordified
        key = cache.analyzed_key
    """

    def __init__(self, score):
        self.score = score
        self._flat = None
        self._flat_notes = None
        self._chordified = None
        self._analyzed_key = None

    @property
    def flat(self):
        """Cached flattened score."""
        if self._flat is None:
            self._flat = self.score.flatten()
        return self._flat

    @property
    def notes(self):
        """Cached notes from flattened score."""
        if self._flat_notes is None:
            self._flat_notes = list(self.flat.notes)
        return self._flat_notes

    @property
    def chordified(self):
        """Cached chordified score."""
        if self._chordified is None:
            self._chordified = self.score.chordify()
        return self._chordified

    @property
    def analyzed_key(self):
        """Cached key analysis."""
        if self._analyzed_key is None:
            try:
                self._analyzed_key = self.score.analyze("key")
            except Exception:
                self._analyzed_key = False  # Distinguish from "not cached yet"
        return self._analyzed_key if self._analyzed_key is not False else None


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
        cache = result.get("_cache")
        flat = cache.flat if cache else score.flatten()
        all_pitches = list(flat.pitches)
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


def is_multi_movement(score, result):
    """
    Detect if score is a multi-movement work where tempo/duration are unreliable.

    Detection methods (in order of reliability):
    1. Movement names in expressions (Allemande, Courante, etc.) - definitive
    2. Internal final barlines (light-heavy barline before last measure) - strong indicator

    For multi-movement works, tempo_bpm only refers to one movement's tempo,
    and duration_seconds calculated from it is meaningless.

    Note: We intentionally do NOT check for multiple MetronomeMark objects.
    Many single-movement pieces have tempo changes (Erlkönig: Schnell → Andante)
    that create multiple MetronomeMark objects but are NOT multi-movement works.
    Using MetronomeMark count caused 97% false positives in testing.
    """
    cache = result.get("_cache")
    flat = cache.flat if cache else score.flatten()

    # 1. Movement names in expressions = suite/multi-movement
    text_exprs = list(flat.getElementsByClass(expressions.TextExpression))
    all_text = " ".join(e.content.lower() for e in text_exprs if hasattr(e, "content") and e.content)

    movement_count = sum(1 for name in MOVEMENT_NAMES if name in all_text)
    if movement_count >= 2:
        return True

    # 2. Internal final barlines indicate movement boundaries
    # A "final" or "light-heavy" barline before the last measure = movement end
    try:
        parts = list(score.parts) if hasattr(score, 'parts') else [score]
        for p in parts[:1]:  # Check first part only
            measures = list(p.getElementsByClass(stream.Measure))
            if len(measures) > 2:
                for m in measures[:-1]:  # Exclude last measure
                    if m.rightBarline and m.rightBarline.type in ['final', 'light-heavy']:
                        return True
    except Exception:
        pass  # If barline check fails, continue without it

    return False


def extract_tempo_duration(score, result):
    """
    Analyze tempo markings and calculate duration.

    Extracts:
    - tempo_bpm: the numeric tempo value (None for multi-movement works)
    - tempo_marking: text like "Allegro" (None for multi-movement works)
    - tempo_referent: quarterLength of the beat unit (None for multi-movement works)
    - duration_seconds: accurate duration (None for multi-movement works)
    - total_quarter_length: raw score length in quarter note units (always extracted)
    - measure_count: number of measures (always extracted)
    - is_multi_movement: True if multiple tempos detected

    For multi-movement works (suites, sonatas with multiple movements):
    - tempo_bpm only refers to one movement
    - duration_seconds would be calculated from wrong single tempo
    - These fields are omitted (None) to avoid misleading RAG results

    Duration formula (single-movement only):
        duration = (total_quarter_length / (tempo_bpm * tempo_referent)) * 60

    Example - 6/8, dotted-quarter = 120, 10 measures:
        total_quarter_length = 30 (10 measures × 3 QL each)
        tempo_referent = 1.5 (dotted quarter)
        duration = 30 / (120 × 1.5) × 60 = 10 seconds
    """
    try:
        cache = result.get("_cache")
        flat = cache.flat if cache else score.flatten()

        # Count measures (always useful)
        if score.parts:
            measures = list(score.parts[0].getElementsByClass(stream.Measure))
            result["measure_count"] = len(measures) if measures else None

        # Total score length in quarter note units (always useful)
        total_ql = score.duration.quarterLength
        if total_ql:
            result["total_quarter_length"] = safe_round(total_ql, 2)

        # Detect multi-movement works - tempo/duration would be misleading
        multi_movement = is_multi_movement(score, result)
        result["is_multi_movement"] = multi_movement

        if multi_movement:
            # Don't extract tempo_bpm, tempo_marking, tempo_referent, duration_seconds
            # These would be misleading (only refer to one movement)
            return

        # Single-movement: safe to extract tempo and duration
        tempos = list(flat.getElementsByClass(tempo.MetronomeMark))
        if tempos:
            first_tempo = tempos[0]
            result["tempo_bpm"] = int(first_tempo.number) if first_tempo.number else None

            # Extract the beat unit (referent) as quarterLength
            # quarter = 1.0, half = 2.0, dotted quarter = 1.5, eighth = 0.5
            if hasattr(first_tempo, "referent") and first_tempo.referent:
                result["tempo_referent"] = safe_round(first_tempo.referent.quarterLength, 3)

            if hasattr(first_tempo, "text") and first_tempo.text:
                result["tempo_marking"] = first_tempo.text

        # Fallback: look for tempo text (no referent available for plain text)
        if not result.get("tempo_marking"):
            tempo_texts = list(flat.getElementsByClass(tempo.TempoText))
            if tempo_texts:
                result["tempo_marking"] = tempo_texts[0].text

        # Calculate duration using accurate formula
        tempo_bpm = result.get("tempo_bpm")
        tempo_referent = result.get("tempo_referent")
        total_quarter_length = result.get("total_quarter_length")

        if tempo_bpm and tempo_bpm > 0 and total_quarter_length and total_quarter_length > 0:
            # Use referent if available, default to quarter note (1.0)
            referent = tempo_referent if tempo_referent and tempo_referent > 0 else 1.0
            # duration = total_ql / (bpm * referent) * 60
            duration = (total_quarter_length / (tempo_bpm * referent)) * 60
            result["duration_seconds"] = safe_round(duration, 1)

    except Exception as e:
        result["_warnings"].append(f"tempo_duration: {e}")


def extract_complexity(score, result):
    """Analyze complexity metrics (raw counts only)."""
    try:
        cache = result.get("_cache")
        notes_list = cache.notes if cache else list(score.flatten().notes)

        # event_count = rhythmic events (note or chord objects)
        # pitch_count = individual pitched sounds (chord with 4 notes = 4 pitches)
        result["event_count"] = len(notes_list)

        pitch_count = 0
        accidental_count = 0
        for n in notes_list:
            if isinstance(n, note.Note):
                pitch_count += 1
                if n.pitch.accidental and n.pitch.accidental.name != "natural":
                    accidental_count += 1
            elif isinstance(n, chord.Chord):
                pitch_count += len(n.pitches)
                for p in n.pitches:
                    if p.accidental and p.accidental.name != "natural":
                        accidental_count += 1

        result["pitch_count"] = pitch_count
        result["accidental_count"] = accidental_count

    except Exception as e:
        result["_warnings"].append(f"complexity: {e}")


def extract_rhythm(score, result):
    """Analyze rhythmic features (raw counts only)."""
    try:
        cache = result.get("_cache")
        notes_list = cache.notes if cache else list(score.flatten().notes)

        # Duration distribution
        duration_counts = Counter()
        for n in notes_list:
            ql = n.quarterLength
            name = DURATION_NAMES.get(ql, f"other_{ql}")
            duration_counts[name] += 1

        if duration_counts:
            result["rhythm_distribution"] = dict(duration_counts.most_common())
            result["predominant_rhythm"] = duration_counts.most_common(1)[0][0]
            result["unique_duration_count"] = len(duration_counts)

        # Off-beat note count (for syncopation calculation in Ruby)
        off_beat_count = 0
        for n in notes_list:
            if hasattr(n, "beat") and n.beat:
                beat_frac = n.beat % 1
                if beat_frac > 0.1:
                    off_beat_count += 1

        result["off_beat_count"] = off_beat_count

    except Exception as e:
        result["_warnings"].append(f"rhythm: {e}")


def extract_harmony(score, result, get_chordified=None):
    """Analyze key, harmony, and chord progressions."""
    try:
        # Key analysis (use cached if available)
        analyzed_key = result.get("_analyzed_key") or score.analyze("key")
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
            result["modulation_targets"] = modulations  # Raw list for Ruby

        # Chord count for harmonic rhythm calculation (all chords in piece)
        try:
            chordified = get_chordified() if get_chordified else score.chordify()
            result["chord_count"] = sum(1 for _ in chordified.flatten().getElementsByClass(chord.Chord))
        except Exception:
            pass

    except Exception as e:
        result["_warnings"].append(f"harmony: {e}")


def extract_melody(score, result):
    """Analyze melodic features (raw data only)."""
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
        stepwise_count = 0

        for i in range(1, len(melody_notes)):
            try:
                intv = interval.Interval(melody_notes[i-1], melody_notes[i])
                intervals[intv.simpleName] += 1
                semitones = abs(intv.semitones)
                interval_semitones.append(semitones)
                if semitones <= 2:
                    stepwise_count += 1
            except Exception:
                pass

        if intervals:
            result["interval_distribution"] = dict(intervals.most_common())
            result["interval_count"] = len(interval_semitones)

        if interval_semitones:
            result["largest_interval"] = max(interval_semitones)
            result["stepwise_count"] = stepwise_count

    except Exception as e:
        result["_warnings"].append(f"melody: {e}")


def extract_structure(score, result, get_chordified=None):
    """Analyze structural elements."""
    try:
        cache = result.get("_cache")
        flat = cache.flat if cache else score.flatten()

        # Time signature
        time_sigs = list(flat.getElementsByClass(meter.TimeSignature))
        if time_sigs:
            result["time_signature"] = time_sigs[0].ratioString

        # Count repeats
        repeats = list(flat.getElementsByClass(bar.Repeat))
        result["repeats_count"] = len(repeats)

        # Section detection
        double_bars = list(flat.getElementsByClass(bar.Barline))
        section_markers = [b for b in double_bars if hasattr(b, "type") and "double" in str(b.type).lower()]
        if section_markers:
            result["sections_count"] = len(section_markers) + 1

        # Final cadence detection
        try:
            chordified = get_chordified() if get_chordified else score.chordify()
            final_chords = list(chordified.flatten().getElementsByClass(chord.Chord))[-4:]

            if len(final_chords) >= 2:
                analyzed_key = result.get("_analyzed_key") or score.analyze("key")
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
        cache = result.get("_cache")
        flat = cache.flat if cache else score.flatten()

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
    """Extract raw instrumentation data. No heuristics - Ruby/LLM interprets."""
    try:
        result["num_parts"] = len(score.parts)

        part_names = []
        instruments = []
        families = set()

        for part in score.parts:
            name = get_part_name(part)
            part_names.append(name)

            inst = part.getInstrument()
            if inst:
                inst_name = inst.instrumentName or inst.partName or name
                instruments.append(inst_name)
                if hasattr(inst, "instrumentFamily") and inst.instrumentFamily:
                    families.add(inst.instrumentFamily)

        result["part_names"] = ", ".join(part_names)
        if instruments:
            result["detected_instruments"] = ", ".join(set(instruments))
        if families:
            result["instrument_families"] = ", ".join(families)

        # NOTE: has_vocal, is_instrumental, has_accompaniment are determined
        # by LLM normalizers (NormalizeHasVocalJob), not here.

    except Exception as e:
        result["_warnings"].append(f"instrumentation: {e}")


def extract_texture(score, result, get_chordified=None):
    """
    Analyze texture from chordified score.

    Extracts raw facts for RAG search:
    - simultaneous_note_avg: texture density (thick vs sparse)
    - texture_variation: how much density changes (builds vs steady)
    - avg_chord_span: voicing width in semitones (open vs close harmony)
    - contrary_motion_ratio: outer voices moving opposite (polyphonic indicator)
    - parallel_motion_ratio: outer voices moving same direction (homophonic indicator)
    - oblique_motion_ratio: one voice holds, other moves
    - unique_chord_count: distinct triads/7ths (harmonic variety)
    """
    try:
        if not score.parts:
            return

        chordified = get_chordified() if get_chordified else score.chordify()
        chord_stream = chordified.flatten().getElementsByClass(chord.Chord)

        # Collect data in single pass
        note_counts = []      # For avg and std dev
        chord_spans = []      # For voicing width
        unique_chords = set() # For harmonic variety (pitch class sets of triads/7ths)
        prev_bass = None
        prev_soprano = None
        contrary_count = 0
        parallel_count = 0
        oblique_count = 0
        total_transitions = 0

        for c in chord_stream:
            pitches = sorted(c.pitches, key=lambda p: p.ps)
            if not pitches:
                continue

            # Texture density (count all, including single notes)
            note_counts.append(len(pitches))

            # Unique chord detection: triads (3) and 7th chords (4) only
            # Uses pitch class (0-11), so inversions = same chord
            pc_set = frozenset(p.pitchClass for p in pitches)
            if 3 <= len(pc_set) <= 4:
                unique_chords.add(pc_set)

            # Chord span and motion analysis - only meaningful for 2+ notes
            if len(pitches) >= 2:
                span = pitches[-1].ps - pitches[0].ps  # soprano - bass in semitones
                chord_spans.append(span)

                # Outer voice motion analysis
                bass = pitches[0].ps
                soprano = pitches[-1].ps

                if prev_bass is not None and prev_soprano is not None:
                    bass_motion = bass - prev_bass      # + = up, - = down, 0 = static
                    soprano_motion = soprano - prev_soprano

                    # Count all transitions where at least one voice moves
                    if bass_motion != 0 or soprano_motion != 0:
                        total_transitions += 1

                        # Contrary: opposite directions (both must move)
                        if bass_motion != 0 and soprano_motion != 0:
                            if (bass_motion > 0) != (soprano_motion > 0):
                                contrary_count += 1
                            else:
                                parallel_count += 1
                        else:
                            # Oblique: one moves, one holds
                            oblique_count += 1

                prev_bass = bass
                prev_soprano = soprano
            else:
                # Single note interrupts voice-leading chain
                # Reset to avoid comparing non-consecutive chords
                prev_bass = None
                prev_soprano = None

        # Calculate results
        if note_counts:
            avg = sum(note_counts) / len(note_counts)
            result["simultaneous_note_avg"] = safe_round(avg)

            # Standard deviation (texture variation)
            if len(note_counts) > 1:
                variance = sum((x - avg) ** 2 for x in note_counts) / len(note_counts)
                result["texture_variation"] = safe_round(variance ** 0.5)

        if chord_spans:
            result["avg_chord_span"] = safe_round(sum(chord_spans) / len(chord_spans))

        # Motion ratios - only if we have actual multi-voice transitions
        if total_transitions > 0:
            result["contrary_motion_ratio"] = safe_round(contrary_count / total_transitions, 3)
            result["parallel_motion_ratio"] = safe_round(parallel_count / total_transitions, 3)
            result["oblique_motion_ratio"] = safe_round(oblique_count / total_transitions, 3)

        # Unique chord count (harmonic variety)
        if unique_chords:
            result["unique_chord_count"] = len(unique_chords)

    except Exception as e:
        result["_warnings"].append(f"texture: {e}")


def extract_hand_span(score, result):
    """
    Find the largest simultaneous chord span in semitones.

    Extracted for 1-2 part scores. Ruby filters by normalized instrument
    (only solo keyboard/harp - see Score#chord_span_applicable?).
    """
    try:
        if len(score.parts) > 2:
            return

        max_span = 0
        for part in score.parts:
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


def extract_melodic_leaps(score, result):
    """
    Count melodic leaps (intervals >5 semitones, i.e. larger than a perfect 4th).

    Raw count - Ruby calculates ratios and interprets difficulty.
    """
    try:
        leap_count = 0

        for part in score.parts:
            notes_list = [n for n in part.flatten().notes if isinstance(n, note.Note)]

            for i in range(1, len(notes_list)):
                interval_size = abs(notes_list[i].pitch.ps - notes_list[i-1].pitch.ps)
                if interval_size > 5:  # Larger than perfect 4th
                    leap_count += 1

        result["leap_count"] = leap_count

    except Exception as e:
        result["_warnings"].append(f"melodic_leaps: {e}")


def extract_chromatic_notes(score, result):
    """
    Count notes that are chromatic (outside the key signature).

    Uses pitch class comparison (MIDI % 12) to avoid enharmonic issues
    where Db major notes were incorrectly marked chromatic against C# major scale.
    """
    try:
        analyzed_key = result.get("_analyzed_key") or score.analyze("key")
        if not analyzed_key:
            return

        # Get diatonic pitch classes (0-11) for the key's scale
        key_scale = analyzed_key.getScale()
        diatonic_pcs = {p.midi % 12 for p in key_scale.pitches[:-1]}  # exclude octave duplicate

        chromatic_count = 0
        cache = result.get("_cache")
        notes_list = cache.notes if cache else list(score.flatten().notes)

        for n in notes_list:
            pitches_to_check = []
            if isinstance(n, note.Note):
                pitches_to_check = [n.pitch]
            elif isinstance(n, chord.Chord):
                pitches_to_check = n.pitches

            for p in pitches_to_check:
                if p.midi % 12 not in diatonic_pcs:
                    chromatic_count += 1

        result["chromatic_note_count"] = chromatic_count

        # Compute chromatic_ratio (derived fact)
        pitch_count = result.get("pitch_count")
        if pitch_count and pitch_count > 0:
            result["chromatic_ratio"] = round(chromatic_count / pitch_count, 3)

    except Exception as e:
        result["_warnings"].append(f"chromatic_notes: {e}")


def extract_pitch_class_distribution(score, result):
    """
    Count occurrences of each pitch class (C, C#, D, etc.).

    Raw data for:
    - Ruby chromatic ratio calculation (alternative to chromatic_note_count)
    - Mode detection (check for raised/lowered scale degrees)
    - Tonal center analysis

    Uses note names (C#, Db) not integers, preserving enharmonic spelling.
    """
    try:
        cache = result.get("_cache")
        notes_list = cache.notes if cache else list(score.flatten().notes)

        pitch_classes = Counter()
        for n in notes_list:
            if isinstance(n, note.Note):
                # Use pitch name without octave: "C#4" -> "C#"
                pitch_classes[n.pitch.name] += 1
            elif isinstance(n, chord.Chord):
                for p in n.pitches:
                    pitch_classes[p.name] += 1

        if pitch_classes:
            result["pitch_class_distribution"] = dict(pitch_classes)

    except Exception as e:
        result["_warnings"].append(f"pitch_class_distribution: {e}")


def extract_meter_info(score, result):
    """
    Extract meter classification and beat count from time signature.

    meter_classification: 'simple', 'compound', or 'complex'
    beat_count: Number of conducted beats (e.g., 6/8 = 2 beats)
    """
    try:
        cache = result.get("_cache")
        flat = cache.flat if cache else score.flatten()
        time_sigs = list(flat.getElementsByClass(meter.TimeSignature))
        if not time_sigs:
            return

        ts = time_sigs[0]

        # Beat count (conducted beats)
        result["beat_count"] = ts.beatCount

        # Meter classification
        if hasattr(ts, "classification"):
            result["meter_classification"] = ts.classification
        else:
            # Fallback: determine from beatDivisionCount
            if ts.beatCount in (2, 3, 4) and ts.beatDivisionCount == 2:
                result["meter_classification"] = "simple"
            elif ts.beatCount in (2, 3, 4) and ts.beatDivisionCount == 3:
                result["meter_classification"] = "compound"
            else:
                result["meter_classification"] = "complex"

    except Exception as e:
        result["_warnings"].append(f"meter_info: {e}")


def extract_spanners(score, result):
    """
    Extract spanner-based notation: slurs, ottava marks.
    """
    try:
        cache = result.get("_cache")
        flat = cache.flat if cache else score.flatten()

        # Slurs
        slurs = list(flat.getElementsByClass(spanner.Slur))
        result["slur_count"] = len(slurs)

        # Ottava (8va, 8vb, 15ma, etc.)
        ottavas = list(flat.getElementsByClass(spanner.Ottava))
        result["has_ottava"] = len(ottavas) > 0

    except Exception as e:
        result["_warnings"].append(f"spanners: {e}")


def extract_ornament_counts(score, result):
    """
    Count specific ornament types for ornament density calculation.

    These are raw counts - Ruby will compute density ratios.
    """
    try:
        cache = result.get("_cache")
        flat = cache.flat if cache else score.flatten()

        # Trills
        trills = list(flat.getElementsByClass(expressions.Trill))
        result["trill_count"] = len(trills)

        # Mordents
        mordents = list(flat.getElementsByClass(expressions.Mordent))
        result["mordent_count"] = len(mordents)

        # Turns
        turns = list(flat.getElementsByClass(expressions.Turn))
        result["turn_count"] = len(turns)

        # Tremolos
        tremolos = list(flat.getElementsByClass(expressions.Tremolo))
        result["tremolo_count"] = len(tremolos)

        # Arpeggio marks
        arpeggios = list(flat.getElementsByClass(expressions.ArpeggioMark))
        result["arpeggio_mark_count"] = len(arpeggios)

    except Exception as e:
        result["_warnings"].append(f"ornament_counts: {e}")


def extract_grace_notes(score, result):
    """
    Count grace notes (appoggiaturas, acciaccaturas).
    """
    try:
        grace_count = 0

        cache = result.get("_cache")
        notes_list = cache.notes if cache else list(score.flatten().notes)
        for n in notes_list:
            if isinstance(n, note.Note):
                if n.duration.isGrace:
                    grace_count += 1
            elif isinstance(n, chord.Chord):
                if n.duration.isGrace:
                    grace_count += 1

        result["grace_note_count"] = grace_count

    except Exception as e:
        result["_warnings"].append(f"grace_notes: {e}")


def extract_pedal_marks(score, result):
    """
    Check for piano pedal markings.
    """
    try:
        cache = result.get("_cache")
        flat = cache.flat if cache else score.flatten()
        pedals = list(flat.getElementsByClass(expressions.PedalMark))
        result["has_pedal_marks"] = len(pedals) > 0

    except Exception as e:
        result["_warnings"].append(f"pedal_marks: {e}")


# Note: Mode detection removed - music21 only returns major/minor.
# See docs/refactor_todo.md Finding 3 for future mode_tendency implementation.


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

        # Create cache for expensive operations
        cache = ScoreCache(score)

        # Store cached key for extraction functions
        result["_analyzed_key"] = cache.analyzed_key
        result["_cache"] = cache

        # Run all extractions (pass cache where needed)
        extract_pitch_range(score, result)
        extract_tempo_duration(score, result)
        extract_complexity(score, result)
        extract_rhythm(score, result)
        extract_harmony(score, result, lambda: cache.chordified)
        extract_melody(score, result)
        extract_structure(score, result, lambda: cache.chordified)
        extract_notation(score, result)
        extract_lyrics(score, result)
        extract_instrumentation(score, result)
        extract_texture(score, result, lambda: cache.chordified)

        # Existing extractions
        extract_hand_span(score, result)
        extract_tessitura(score, result)
        extract_melodic_leaps(score, result)

        # Phase 0: New raw extractions
        extract_chromatic_notes(score, result)
        extract_pitch_class_distribution(score, result)
        extract_meter_info(score, result)
        extract_spanners(score, result)
        extract_ornament_counts(score, result)
        extract_grace_notes(score, result)
        extract_pedal_marks(score, result)

        result["extraction_status"] = "extracted"

    except Exception as e:
        result["extraction_status"] = "failed"
        result["extraction_error"] = str(e)[:1000]

    # Clean up internal fields
    result.pop("_analyzed_key", None)
    result.pop("_cache", None)
    warnings = result.pop("_warnings", [])
    if warnings:
        result["_extraction_warnings"] = warnings

    return result


# ─────────────────────────────────────────────────────────────────
# BATCH PROCESSING
# ─────────────────────────────────────────────────────────────────

def _extract_one(path: str) -> dict:
    """
    Extract single file. Top-level function required for multiprocessing.

    Returns dict with file_path and all extraction results.
    Never raises - errors captured in result dict.
    """
    result = {"file_path": path}
    if not Path(path).exists():
        result["extraction_status"] = "failed"
        result["extraction_error"] = f"File not found: {path}"
    else:
        try:
            result.update(extract(path))
        except Exception as e:
            result["extraction_status"] = "failed"
            result["extraction_error"] = str(e)[:500]
    return result


def extract_batch(
    paths: list[str],
    output_file=sys.stdout,
    workers: int = 1
) -> dict:
    """
    Extract features from multiple files in batch mode.

    Args:
        paths: List of MusicXML file paths
        output_file: File object for JSONL output (default: stdout)
        workers: Parallel workers. 1=sequential, 0=auto (cpu_count)

    Returns:
        Stats dict with total, extracted, failed counts
    """
    from multiprocessing import Pool, cpu_count

    total = len(paths)
    stats = {"total": total, "extracted": 0, "failed": 0}

    if workers == 0:
        workers = cpu_count()

    def process_result(i: int, result: dict):
        """Handle single result: update stats, write output, log progress."""
        ok = result.get("extraction_status") == "extracted"
        stats["extracted" if ok else "failed"] += 1

        output_file.write(json.dumps(result, ensure_ascii=False) + "\n")
        output_file.flush()

        status = "OK" if ok else "FAIL"
        print(f"[{i+1}/{total}] {status}: {Path(result['file_path']).name}", file=sys.stderr)
        sys.stderr.flush()

    if workers > 1:
        print(f"Parallel extraction with {workers} workers", file=sys.stderr)
        with Pool(workers) as pool:
            for i, result in enumerate(pool.imap(_extract_one, paths)):
                process_result(i, result)
    else:
        for i, path in enumerate(paths):
            process_result(i, _extract_one(path))

    return stats


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Extract musical features from MusicXML files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  Single file:
    python3 extract.py score.mxl

  Batch mode (sequential):
    python3 extract.py --batch paths.txt -o results.jsonl

  Batch mode (4 parallel workers):
    python3 extract.py --batch paths.txt -o results.jsonl --workers 4

  Batch mode (auto-detect CPU cores):
    find ~/data -name "*.mxl" | python3 extract.py --batch - -o results.jsonl -w 0
"""
    )
    parser.add_argument("path", nargs="?", help="Path to MusicXML file")
    parser.add_argument("--batch", "-b", metavar="FILE",
                        help="Batch mode: read paths from FILE (use '-' for stdin)")
    parser.add_argument("--output", "-o", metavar="FILE",
                        help="Output file for batch mode (default: stdout)")
    parser.add_argument("--workers", "-w", type=int, default=1, metavar="N",
                        help="Parallel workers: 1=sequential (default), 0=auto, N=specific count")

    args = parser.parse_args()

    # Batch mode
    if args.batch:
        # Read paths from file or stdin
        if args.batch == "-":
            paths = [line.strip() for line in sys.stdin if line.strip()]
        else:
            with open(args.batch) as f:
                paths = [line.strip() for line in f if line.strip()]

        if not paths:
            print("No paths provided", file=sys.stderr)
            sys.exit(1)

        # Open output file or use stdout
        if args.output:
            with open(args.output, "w") as out:
                stats = extract_batch(paths, out, workers=args.workers)
        else:
            stats = extract_batch(paths, workers=args.workers)

        print(f"\nDone: {stats['extracted']} extracted, {stats['failed']} failed",
              file=sys.stderr)
        sys.exit(0)

    # Single file mode
    if not args.path:
        parser.print_help()
        sys.exit(1)

    if not Path(args.path).exists():
        print(json.dumps({
            "extraction_status": "failed",
            "extraction_error": f"File not found: {args.path}"
        }))
        sys.exit(1)

    result = extract(args.path)
    print(json.dumps(result, ensure_ascii=False))
