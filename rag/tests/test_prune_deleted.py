"""ChromaDB reconcile: orphaned vectors are pruned, live ones are kept."""

from unittest.mock import MagicMock

import pytest

from src import db
from src.pipeline.prune_deleted import _indexed_doc_ids, _orphans, prune_deleted


def _fake_store(*, doc_count, ids, metadatas):
    store = MagicMock()
    store.count_documents.return_value = doc_count
    store._collection.get.return_value = {"ids": ids, "metadatas": metadatas}
    return store


def test_orphans_returns_doc_ids_without_a_live_score():
    indexed = {1: "score_1", 2: "score_2", 3: "score_3"}
    assert _orphans(indexed, {1, 3}) == ["score_2"]


def test_orphans_flags_everything_when_keep_set_empty():
    # The pure function has no guard; prune_deleted() is what refuses this.
    assert _orphans({1: "score_1"}, set()) == ["score_1"]


def test_indexed_doc_ids_maps_score_id_to_doc_id():
    collection = MagicMock()
    collection.get.return_value = {
        "ids": ["score_1", "score_2"],
        "metadatas": [{"score_id": 1}, {"score_id": 2}],
    }
    assert _indexed_doc_ids(collection) == {1: "score_1", 2: "score_2"}


def test_indexed_doc_ids_skips_vectors_without_score_id():
    collection = MagicMock()
    collection.get.return_value = {
        "ids": ["score_1", "no_meta"],
        "metadatas": [{"score_id": 1}, None],
    }
    assert _indexed_doc_ids(collection) == {1: "score_1"}


def test_prune_deleted_removes_orphans(monkeypatch):
    store = _fake_store(
        doc_count=3,
        ids=["score_1", "score_2", "score_3"],
        metadatas=[{"score_id": 1}, {"score_id": 2}, {"score_id": 3}],
    )
    monkeypatch.setattr(db, "get_active_score_ids", lambda: {1, 3})

    removed = prune_deleted(document_store=store)

    assert removed == 1
    store._collection.delete.assert_called_once_with(ids=["score_2"])


def test_prune_deleted_check_only_deletes_nothing(monkeypatch):
    store = _fake_store(
        doc_count=2,
        ids=["score_1", "score_2"],
        metadatas=[{"score_id": 1}, {"score_id": 2}],
    )
    monkeypatch.setattr(db, "get_active_score_ids", lambda: {1})

    removed = prune_deleted(check_only=True, document_store=store)

    assert removed == 1
    store._collection.delete.assert_not_called()


def test_prune_deleted_keeps_all_when_nothing_orphaned(monkeypatch):
    store = _fake_store(
        doc_count=2,
        ids=["score_1", "score_2"],
        metadatas=[{"score_id": 1}, {"score_id": 2}],
    )
    monkeypatch.setattr(db, "get_active_score_ids", lambda: {1, 2})

    assert prune_deleted(document_store=store) == 0
    store._collection.delete.assert_not_called()


def test_prune_deleted_noop_when_index_empty(monkeypatch):
    store = _fake_store(doc_count=0, ids=[], metadatas=[])
    queried = []
    monkeypatch.setattr(
        db, "get_active_score_ids", lambda: queried.append(True) or set()
    )

    assert prune_deleted(document_store=store) == 0
    assert queried == []  # early return before touching the DB
    store._collection.delete.assert_not_called()


def test_prune_deleted_refuses_to_wipe_on_empty_keep_set(monkeypatch):
    store = _fake_store(
        doc_count=2,
        ids=["score_1", "score_2"],
        metadatas=[{"score_id": 1}, {"score_id": 2}],
    )
    monkeypatch.setattr(db, "get_active_score_ids", set)

    with pytest.raises(RuntimeError, match="Refusing to prune"):
        prune_deleted(document_store=store)

    store._collection.delete.assert_not_called()
