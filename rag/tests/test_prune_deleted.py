"""ChromaDB reconcile: orphaned vectors are pruned, live ones are kept."""

from unittest.mock import MagicMock

import pytest

from src import db
from src.pipeline.prune_deleted import _orphans, indexed_doc_ids, prune_deleted


def _fake_store(*, doc_count, ids, metadatas):
    store = MagicMock()
    store.count_documents.return_value = doc_count
    # indexed_doc_ids() pages until an empty result — hand back one page, then empty.
    store._collection.get.side_effect = [
        {"ids": ids, "metadatas": metadatas},
        {"ids": [], "metadatas": []},
    ]
    return store


def test_orphans_returns_doc_ids_without_a_live_score():
    indexed = {1: "score_1", 2: "score_2", 3: "score_3"}
    assert _orphans(indexed, {1, 3}) == ["score_2"]


def test_orphans_flags_everything_when_keep_set_empty():
    # The pure function has no guard; prune_deleted() is what refuses this.
    assert _orphans({1: "score_1"}, set()) == ["score_1"]


def test_indexed_doc_ids_pages_until_empty_and_maps():
    collection = MagicMock()
    collection.get.side_effect = [
        {"ids": ["score_1", "score_2"], "metadatas": [{"score_id": 1}, {"score_id": 2}]},
        {"ids": ["score_3"], "metadatas": [{"score_id": 3}]},
        {"ids": [], "metadatas": []},
    ]

    assert indexed_doc_ids(collection) == {1: "score_1", 2: "score_2", 3: "score_3"}
    assert collection.get.call_count == 3  # two data pages + the empty terminator
    assert [c.kwargs["offset"] for c in collection.get.call_args_list] == [0, 2, 3]


def test_indexed_doc_ids_skips_vectors_without_score_id():
    collection = MagicMock()
    collection.get.side_effect = [
        {"ids": ["score_1", "no_meta"], "metadatas": [{"score_id": 1}, None]},
        {"ids": [], "metadatas": []},
    ]
    assert indexed_doc_ids(collection) == {1: "score_1"}


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


# --- real ChromaDB integration (skipped if chromadb is not installed) -------
# Mocks can't catch a ChromaDB API mismatch -- these exercise the real client,
# with more than BATCH_SIZE vectors so pagination genuinely pages.

def _real_collection(tmp_path, n):
    """A real on-disk ChromaDB collection holding n score vectors."""
    chromadb = pytest.importorskip("chromadb")
    client = chromadb.PersistentClient(path=str(tmp_path / "chroma"))
    collection = client.create_collection("scores")
    for start in range(0, n, 200):
        batch = range(start + 1, min(start + 200, n) + 1)
        collection.add(
            ids=[f"score_{i}" for i in batch],
            embeddings=[[0.1, 0.2, 0.3] for _ in batch],
            metadatas=[{"score_id": i} for i in batch],
        )
    return collection


def test_real_chromadb_indexed_doc_ids_paginates_whole_collection(tmp_path):
    n = 1100  # > BATCH_SIZE (500): forces real multi-page pagination
    collection = _real_collection(tmp_path, n)

    assert indexed_doc_ids(collection) == {i: f"score_{i}" for i in range(1, n + 1)}


def test_real_chromadb_prune_deleted_end_to_end(tmp_path, monkeypatch):
    n = 1100
    collection = _real_collection(tmp_path, n)

    class _Store:
        _collection = collection

        def count_documents(self):
            return collection.count()

    orphan_ids = {500, 999, 1100}
    keep = set(range(1, n + 1)) - orphan_ids
    monkeypatch.setattr(db, "get_active_score_ids", lambda: keep)

    removed = prune_deleted(document_store=_Store())

    assert removed == len(orphan_ids)
    assert collection.count() == n - len(orphan_ids)
    assert set(indexed_doc_ids(collection)) == keep
