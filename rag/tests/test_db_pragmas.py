"""Verify Python sqlite3 connections set the same busy_timeout as Rails."""

import sqlite3

from src import config, db


def test_get_connection_sets_busy_timeout(tmp_path, monkeypatch):
    """Match Rails' `busy_timeout: 5000` so concurrent writes wait 5s instead of failing."""
    db_path = tmp_path / "test.sqlite3"
    sqlite3.connect(db_path).close()  # create the file
    monkeypatch.setattr(config, "RAILS_DB_PATH", db_path)

    conn = db.get_connection()
    try:
        timeout = conn.execute("PRAGMA busy_timeout").fetchone()[0]
        assert timeout == 5000
    finally:
        conn.close()
