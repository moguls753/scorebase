"""Tests for the LLM provider factory."""

import pytest

from src.llm import factory
from src.llm.groq_client import GroqConfig


def test_default_provider_is_deepseek(monkeypatch):
    monkeypatch.delenv("LLM_BACKEND", raising=False)
    assert factory.active_provider() == "deepseek"
    assert factory.required_api_key_env_var() == "DEEPSEEK_API_KEY"


def test_groq_provider(monkeypatch):
    monkeypatch.setenv("LLM_BACKEND", "groq")
    assert factory.active_provider() == "groq"
    assert factory.required_api_key_env_var() == "GROQ_API_KEY"


def test_lmstudio_provider_needs_no_api_key(monkeypatch):
    monkeypatch.setenv("LLM_BACKEND", "lmstudio")
    assert factory.active_provider() == "lmstudio"
    assert factory.required_api_key_env_var() is None


def test_unknown_provider_raises(monkeypatch):
    monkeypatch.setenv("LLM_BACKEND", "nonsense")
    with pytest.raises(ValueError, match="Unknown LLM_BACKEND"):
        factory.default_client()


def test_groq_config_defaults_to_quality_model(monkeypatch):
    """GroqConfig defaults to 70B (quality-first for rerank); 8B is the fallback."""
    monkeypatch.setenv("GROQ_API_KEY", "test")
    monkeypatch.delenv("GROQ_MODEL", raising=False)
    monkeypatch.delenv("GROQ_FALLBACK_MODEL", raising=False)

    config = GroqConfig.from_env()
    assert config.primary_model == "llama-3.3-70b-versatile"
    assert config.fallback_model == "llama-3.1-8b-instant"


def test_groq_config_honors_env_overrides(monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "test")
    monkeypatch.setenv("GROQ_MODEL", "some-other-model")
    monkeypatch.setenv("GROQ_FALLBACK_MODEL", "some-other-fallback")

    config = GroqConfig.from_env()
    assert config.primary_model == "some-other-model"
    assert config.fallback_model == "some-other-fallback"
