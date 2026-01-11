"""
Tests for Music21 Feature Extractor
===================================
Focus on critical paths. If extraction works end-to-end, the details work.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest
from music21 import bar, chord, converter, expressions, key, meter, note, stream, tempo

sys.path.insert(0, str(Path(__file__).parent.parent))
from extract import extract, is_multi_movement


def make_simple_score():
    """C major scale with tempo marking."""
    s = stream.Score()
    p = stream.Part()
    p.partName = "Melody"

    m = stream.Measure(number=1)
    m.append(meter.TimeSignature("4/4"))
    m.append(key.KeySignature(0))
    m.append(tempo.MetronomeMark(number=120))

    for pitch in ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]:
        m.append(note.Note(pitch, quarterLength=0.5))

    p.append(m)
    s.append(p)
    return s


def make_satb_score():
    """4-part choir score."""
    s = stream.Score()
    for name, pitches in [
        ("Soprano", ["C5", "E5", "G5"]),
        ("Alto", ["G4", "C5", "E5"]),
        ("Tenor", ["E4", "G4", "C5"]),
        ("Bass", ["C3", "E3", "G3"]),
    ]:
        p = stream.Part()
        p.partName = name
        m = stream.Measure()
        m.append(meter.TimeSignature("4/4"))
        for pitch in pitches:
            m.append(note.Note(pitch, quarterLength=1.0))
        p.append(m)
        s.append(p)
    return s


def make_piano_score():
    """Piano score with chords to test hand span."""
    s = stream.Score()
    p = stream.Part()
    p.partName = "Piano"

    m = stream.Measure(number=1)
    m.append(meter.TimeSignature("4/4"))
    # C-E-G chord (7 semitones span)
    m.append(chord.Chord(["C4", "E4", "G4"], quarterLength=1.0))
    # C-G-C chord (12 semitones span - octave)
    m.append(chord.Chord(["C4", "G4", "C5"], quarterLength=1.0))
    # Single notes
    m.append(note.Note("D4", quarterLength=1.0))
    m.append(note.Note("E4", quarterLength=1.0))

    p.append(m)
    s.append(p)
    return s


def save_temp(score):
    """Save to temp file, return path."""
    _, path = tempfile.mkstemp(suffix=".musicxml")
    score.write("musicxml", fp=path)
    return path


class TestExtraction:
    """Core extraction tests."""

    def test_extraction_succeeds(self):
        path = save_temp(make_simple_score())
        try:
            result = extract(path)
            assert result["extraction_status"] == "extracted"
        finally:
            Path(path).unlink()

    def test_pitch_range_extracted(self):
        path = save_temp(make_simple_score())
        try:
            result = extract(path)
            assert result["lowest_pitch"] == "C4"
            assert result["highest_pitch"] == "C5"
            assert result["ambitus_semitones"] == 12
        finally:
            Path(path).unlink()

    def test_tempo_extracted(self):
        path = save_temp(make_simple_score())
        try:
            result = extract(path)
            assert result["tempo_bpm"] == 120
        finally:
            Path(path).unlink()

    def test_time_signature_extracted(self):
        path = save_temp(make_simple_score())
        try:
            result = extract(path)
            assert result["time_signature"] == "4/4"
        finally:
            Path(path).unlink()

    def test_key_detected(self):
        path = save_temp(make_simple_score())
        try:
            result = extract(path)
            # C major and A minor are relative keys (same notes) - either is valid
            assert result["key_signature"] in ["C major", "A minor"]
        finally:
            Path(path).unlink()

    def test_multipart_extraction(self):
        path = save_temp(make_satb_score())
        try:
            result = extract(path)
            assert result["num_parts"] == 4
            assert "Soprano" in result["part_names"]
            assert "Bass" in result["part_names"]
        finally:
            Path(path).unlink()

    def test_missing_file_fails_gracefully(self):
        result = extract("/no/such/file.mxl")
        assert result["extraction_status"] == "failed"
        assert result["extraction_error"] is not None


class TestAdvancedFeatures:
    """Tests for advanced extraction features."""

    def test_hand_span_extracted_for_piano(self):
        """Piano scores should have max_chord_span."""
        path = save_temp(make_piano_score())
        try:
            result = extract(path)
            assert "max_chord_span" in result
            assert result["max_chord_span"] == 12  # C4 to C5 = octave
        finally:
            Path(path).unlink()

    def test_tessitura_extracted(self):
        """Parts should have tessitura (average pitch)."""
        path = save_temp(make_satb_score())
        try:
            result = extract(path)
            assert "tessitura" in result
            assert "Soprano" in result["tessitura"]
            assert "average_midi" in result["tessitura"]["Soprano"]
        finally:
            Path(path).unlink()


class TestMultiMovement:
    """Multi-movement detection tests."""

    def test_tempo_change_not_multi_movement(self):
        """Tempo changes alone should NOT flag as multi-movement (Erlkönig case)."""
        s = stream.Score()
        p = stream.Part()
        m1 = stream.Measure(number=1)
        m1.append(tempo.MetronomeMark(text="Schnell", number=148))
        m1.append(note.Note("C4", quarterLength=4))
        p.append(m1)
        m2 = stream.Measure(number=2)
        m2.append(tempo.MetronomeMark(text="Andante", number=80))
        m2.append(note.Note("D4", quarterLength=4))
        p.append(m2)
        s.append(p)

        assert is_multi_movement(s, {}) is False

    def test_movement_names_is_multi_movement(self):
        """Movement names (Allemande, Courante) should flag as multi-movement."""
        s = stream.Score()
        p = stream.Part()
        p.append(expressions.TextExpression("Allemande"))
        p.append(note.Note("C4"))
        p.append(expressions.TextExpression("Courante"))
        p.append(note.Note("D4"))
        s.append(p)

        assert is_multi_movement(s, {}) is True

    def test_internal_final_barline_is_multi_movement(self):
        """Internal final barline should flag as multi-movement."""
        s = stream.Score()
        p = stream.Part()
        m1 = stream.Measure(number=1)
        m1.append(note.Note("C4", quarterLength=4))
        m1.rightBarline = bar.Barline('light-heavy')
        p.append(m1)
        m2 = stream.Measure(number=2)
        m2.append(note.Note("D4", quarterLength=4))
        p.append(m2)
        m3 = stream.Measure(number=3)
        m3.append(note.Note("E4", quarterLength=4))
        p.append(m3)
        s.append(p)

        assert is_multi_movement(s, {}) is True


class TestCLI:
    """CLI interface tests."""

    def test_cli_outputs_json(self):
        path = save_temp(make_simple_score())
        try:
            proc = subprocess.run(
                [sys.executable, str(Path(__file__).parent.parent / "extract.py"), path],
                capture_output=True, text=True
            )
            output = json.loads(proc.stdout)
            assert output["extraction_status"] == "extracted"
        finally:
            Path(path).unlink()

    def test_cli_missing_arg_shows_usage(self):
        """CLI without args shows usage help."""
        proc = subprocess.run(
            [sys.executable, str(Path(__file__).parent.parent / "extract.py")],
            capture_output=True, text=True
        )
        assert "usage:" in proc.stdout.lower() or "usage:" in proc.stderr.lower()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
