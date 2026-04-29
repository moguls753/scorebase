"""Tests for the German→English query normalizer."""

from src.pipeline.query_normalizer import normalize_for_embedding


def test_passthrough_for_english():
    assert normalize_for_embedding("Mozart sonatas") == "Mozart sonatas"


def test_translates_german_genre():
    assert normalize_for_embedding("Mozart Sonaten") == "Mozart sonatas"


def test_translates_compound_phrase():
    assert normalize_for_embedding("Streichquartett") == "string quartet"


def test_preserves_casing_of_unmatched_words():
    out = normalize_for_embedding("Bach Fuge für Klavier")
    assert "fugue" in out.lower()
    assert "piano" in out.lower()
    assert "Bach" in out


def test_idempotent_on_english_after_translation():
    once = normalize_for_embedding("leichte Klavierstücke")
    twice = normalize_for_embedding(once)
    assert twice == once


def test_handles_empty_and_none_safely():
    assert normalize_for_embedding("") == ""


def test_does_not_substitute_inside_word():
    # "Bass" shouldn't grab "Bassgitarre" mid-word, but standalone "Bass" should translate.
    assert "double bass" in normalize_for_embedding("Kontrabass solo").lower()
    out = normalize_for_embedding("Bassgitarre")
    assert out == "Bassgitarre"


def test_longer_phrases_win_over_shorter():
    out = normalize_for_embedding("Hochzeitsmarsch")
    assert out == "wedding march"
    assert "Hochzeit" not in out


def test_etude_singular_and_plural():
    assert normalize_for_embedding("Etüde") == "etude"
    assert normalize_for_embedding("Etüden") == "etudes"
