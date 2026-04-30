"""Verify config picks up env-driven paths."""

import importlib

import pytest


@pytest.fixture
def reload_config(monkeypatch):
    """Helper: set env vars then reimport src.config so module-level reads pick them up."""
    def _reload(env: dict):
        for key, value in env.items():
            if value is None:
                monkeypatch.delenv(key, raising=False)
            else:
                monkeypatch.setenv(key, value)
        from src import config
        return importlib.reload(config)
    return _reload


def test_rails_db_path_uses_env_var(reload_config):
    config = reload_config({"RAG_DB_PATH": "/rails/storage/production.sqlite3"})
    assert str(config.RAILS_DB_PATH) == "/rails/storage/production.sqlite3"


def test_rails_db_path_defaults_to_development(reload_config):
    config = reload_config({"RAG_DB_PATH": None, "CHROMA_PATH": None})
    assert str(config.RAILS_DB_PATH).endswith("storage/development.sqlite3")


def test_chroma_path_uses_env_var(reload_config):
    config = reload_config({"CHROMA_PATH": "/data/chroma"})
    assert str(config.CHROMA_PATH) == "/data/chroma"


def test_chroma_path_defaults_to_local(reload_config):
    config = reload_config({"RAG_DB_PATH": None, "CHROMA_PATH": None})
    assert str(config.CHROMA_PATH).endswith("data/chroma")
