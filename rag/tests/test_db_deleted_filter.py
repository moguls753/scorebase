"""The indexer's SQLite reads must ignore soft-deleted scores."""

import sqlite3

from src import config, db


def _make_scores_db(tmp_path, rows):
    """Create a minimal `scores` table.

    rows: iterable of (id, rag_status, search_text, deleted_at).
    """
    db_path = tmp_path / "scores.sqlite3"
    conn = sqlite3.connect(db_path)
    conn.execute(
        "CREATE TABLE scores ("
        "id INTEGER PRIMARY KEY, title TEXT, search_text TEXT, "
        "rag_status TEXT, deleted_at TEXT)"
    )
    conn.executemany(
        "INSERT INTO scores (id, title, search_text, rag_status, deleted_at) "
        "VALUES (?, ?, ?, ?, ?)",
        [(sid, f"Title {sid}", text, status, deleted)
         for sid, status, text, deleted in rows],
    )
    conn.commit()
    conn.close()
    return db_path


def test_get_templated_scores_excludes_soft_deleted(tmp_path, monkeypatch):
    db_path = _make_scores_db(tmp_path, [
        (1, "templated", "text one", None),
        (2, "templated", "text two", "2026-05-22 10:00:00"),
    ])
    monkeypatch.setattr(config, "RAILS_DB_PATH", db_path)

    assert [s["id"] for s in db.get_templated_scores(limit=100)] == [1]


def test_get_templated_scores_unlimited_excludes_soft_deleted(tmp_path, monkeypatch):
    db_path = _make_scores_db(tmp_path, [
        (1, "templated", "text one", None),
        (2, "templated", "text two", "2026-05-22 10:00:00"),
        (3, "templated", "text three", None),
    ])
    monkeypatch.setattr(config, "RAILS_DB_PATH", db_path)

    assert [s["id"] for s in db.get_templated_scores(limit=-1)] == [1, 3]


def test_get_scores_by_ids_excludes_soft_deleted(tmp_path, monkeypatch):
    db_path = _make_scores_db(tmp_path, [
        (1, "templated", "text one", None),
        (2, "templated", "text two", "2026-05-22 10:00:00"),
    ])
    monkeypatch.setattr(config, "RAILS_DB_PATH", db_path)

    assert [s["id"] for s in db.get_scores_by_ids([1, 2])] == [1]


def test_get_active_score_ids_returns_only_live(tmp_path, monkeypatch):
    db_path = _make_scores_db(tmp_path, [
        (1, "indexed", "t", None),
        (2, "templated", "t", None),
        (3, "indexed", "t", "2026-05-22 10:00:00"),
    ])
    monkeypatch.setattr(config, "RAILS_DB_PATH", db_path)

    assert db.get_active_score_ids() == {1, 2}


def test_get_active_score_ids_empty_when_all_deleted(tmp_path, monkeypatch):
    db_path = _make_scores_db(tmp_path, [
        (1, "indexed", "t", "2026-05-22 10:00:00"),
    ])
    monkeypatch.setattr(config, "RAILS_DB_PATH", db_path)

    assert db.get_active_score_ids() == set()
