"""Tests for metadata transformer."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src" / "llm"))
from metadata_transformer import transform_metadata, _bucket, _bucket_01, _get_difficulty


class TestBucket:
    """Test bucketing functions."""

    def test_bucket_returns_none_for_none(self):
        assert _bucket(None, [1, 2], ["a", "b", "c"]) is None

    def test_bucket_returns_none_for_empty_labels(self):
        assert _bucket(5, [1, 2], []) is None

    def test_bucket_maps_correctly(self):
        assert _bucket(0, [1, 2, 3], ["low", "med", "high", "max"]) == "low"
        assert _bucket(1, [1, 2, 3], ["low", "med", "high", "max"]) == "low"
        assert _bucket(2, [1, 2, 3], ["low", "med", "high", "max"]) == "med"
        assert _bucket(5, [1, 2, 3], ["low", "med", "high", "max"]) == "max"

    def test_bucket_01_returns_none_for_none(self):
        assert _bucket_01(None) is None

    def test_bucket_01_maps_correctly(self):
        assert _bucket_01(0.0) == "low"
        assert _bucket_01(0.32) == "low"
        assert _bucket_01(0.33) == "medium"
        assert _bucket_01(0.65) == "medium"
        assert _bucket_01(0.66) == "high"
        assert _bucket_01(1.0) == "high"


class TestDifficulty:
    """Test difficulty mapping."""

    def test_none_returns_intermediate(self):
        assert _get_difficulty(None) == ["intermediate", "moderate"]

    def test_low_complexity_is_beginner(self):
        assert _get_difficulty(0.1)[0] == "easy"
        assert _get_difficulty(0.29)[0] == "easy"

    def test_mid_complexity_is_intermediate(self):
        assert _get_difficulty(0.3)[0] == "intermediate"
        assert _get_difficulty(0.49)[0] == "intermediate"

    def test_high_complexity_is_advanced(self):
        assert _get_difficulty(0.5)[0] == "advanced"
        assert _get_difficulty(0.69)[0] == "advanced"

    def test_very_high_complexity_is_virtuoso(self):
        assert _get_difficulty(0.7)[0] == "virtuoso"
        assert _get_difficulty(1.0)[0] == "virtuoso"


class TestTransformMetadata:
    """Test the main transform function."""

    def test_empty_dict_returns_difficulty(self):
        result = transform_metadata({})
        assert "difficulty_level" in result
        assert result["difficulty_level"] == ["intermediate", "moderate"]

    def test_none_values_are_filtered(self):
        result = transform_metadata({"title": None, "composer": None})
        assert "title" not in result
        assert "composer" not in result

    def test_empty_strings_are_filtered(self):
        result = transform_metadata({"title": "", "composer": ""})
        assert "title" not in result
        assert "composer" not in result

    def test_na_values_are_filtered(self):
        result = transform_metadata({"tags": "NA", "genres": "NA"})
        assert "tags" not in result
        assert "genres" not in result

    def test_valid_values_pass_through(self):
        result = transform_metadata({
            "title": "Test Piece",
            "composer": "Bach",
            "genres": "classical",
        })
        assert result["title"] == "Test Piece"
        assert result["composer"] == "Bach"
        assert result["genres"] == "classical"

    def test_time_signature_mapped(self):
        result = transform_metadata({"time_signature": "4/4"})
        assert result["time_signature"] == "four-four (common time)"

    def test_unknown_time_signature_passes_through(self):
        result = transform_metadata({"time_signature": "7/8"})
        assert result["time_signature"] == "7/8"

    def test_clefs_mapped(self):
        result = transform_metadata({"clefs_used": "f, g"})
        assert result["clefs_used"] == "bass and treble"

    def test_cadence_mapped(self):
        result = transform_metadata({"final_cadence": "PAC"})
        assert result["final_cadence"] == "perfect authentic cadence"

    def test_num_parts_bucketed(self):
        assert transform_metadata({"num_parts": 1})["num_parts"] == "solo"
        assert transform_metadata({"num_parts": 2})["num_parts"] == "duo"
        assert transform_metadata({"num_parts": 4})["num_parts"] == "small_ensemble"

    def test_largest_leap_bucketed(self):
        assert transform_metadata({"largest_interval": 3})["largest_leap"] == "small"
        assert transform_metadata({"largest_interval": 7})["largest_leap"] == "medium"
        assert transform_metadata({"largest_interval": 12})["largest_leap"] == "large"
        assert transform_metadata({"largest_interval": 17})["largest_leap"] == "very_large"

    def test_booleans_preserved(self):
        result = transform_metadata({
            "has_dynamics": True,
            "has_vocal": False,
        })
        assert result["has_dynamics"] is True
        assert result["has_vocal"] is False

    def test_full_example(self):
        """Test with realistic data."""
        raw = {
            "title": "Prelude in C",
            "composer": "Bach",
            "melodic_complexity": 0.87,
            "time_signature": "4/4",
            "clefs_used": "f, g",
            "num_parts": 2,
            "is_instrumental": True,
        }
        result = transform_metadata(raw)

        assert result["title"] == "Prelude in C"
        assert result["difficulty_level"][0] == "virtuoso"
        assert result["time_signature"] == "four-four (common time)"
        assert result["clefs_used"] == "bass and treble"
        assert result["num_parts"] == "duo"
        assert result["is_instrumental"] is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
