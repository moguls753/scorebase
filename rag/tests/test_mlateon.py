import sqlite3
from contextlib import closing
from unittest.mock import Mock

import numpy as np
import pytest

from src import config, db
from src.pipeline import mlateon, search


def tokens(*xy):
    vectors = np.zeros((len(xy), mlateon.DIMENSION), dtype=np.float16)
    vectors[:, :2] = xy
    return vectors


@pytest.fixture
def catalogue(tmp_path, monkeypatch):
    path = tmp_path / 'catalogue.sqlite3'
    monkeypatch.setattr(config, 'RAILS_DB_PATH', path)
    with closing(sqlite3.connect(path)) as conn, conn:
        conn.execute('''CREATE TABLE scores(id INTEGER PRIMARY KEY, title, search_text,
                     rag_status, deleted_at, source, price_usd, price_eur)''')
        conn.executemany('INSERT INTO scores(id,search_text,rag_status,deleted_at) VALUES (?,?,?,?)', [
            (1, 'two parts', 'indexed', None), (2, 'one part', 'templated', None),
            (3, 'gone', 'indexed', 'today'), (4, 'new text', 'indexed', None),
            (5, 'draft', 'pending', None), (6, '\t\n', 'templated', None),
        ])
    return path


def test_ranking_refills_past_stale_editions(tmp_path, catalogue):
    q = tokens((1, 0), (0, 1))
    # Higher-scoring deleted/changed/pending rows span more than one hydration batch.
    stale = [(i, 'missing', 2 * q) for i in range(100, 170)]
    stale += [(3, 'gone', 2 * q), (4, 'old text', 2 * q), (5, 'draft', 2 * q)]
    path = tmp_path / 'release'
    mlateon.write_index(path, [stale, [(2, 'one part', tokens((1, 0))), (1, 'two parts', q)]])
    results = mlateon.Index(path).candidates(q, 2)
    assert [(r['score_id'], r['similarity']) for r in results] == [(1, 2.0), (2, 1.0)]


def test_rebuild_reports_drift_and_only_encodes_new_or_changed_text(tmp_path, catalogue, monkeypatch):
    encode = Mock(side_effect=lambda texts: [tokens((1, 0)) for _ in texts])
    monkeypatch.setattr(mlateon, 'Encoder', lambda: Mock(encode=encode))
    old, new = tmp_path / 'old', tmp_path / 'new'
    mlateon.build(old)
    assert mlateon.Index(old).ids.tolist() == [1, 2, 4]
    with closing(sqlite3.connect(catalogue)) as conn, conn:
        conn.execute("update scores set search_text='corrected' where id=1")
        conn.execute("update scores set deleted_at='today' where id=2")
        conn.execute("update scores set rag_status='templated' where id=5")
    assert mlateon.coverage(old) == dict(matched=1, missing=1, changed=1, ineligible=1)
    encode.reset_mock()
    mlateon.build(new, reuse=old)
    encode.assert_called_once_with(['corrected', 'draft'])
    assert mlateon.coverage(new) == dict(matched=3, missing=0, changed=0, ineligible=0)


def test_wal_reader_after_last_writer_closes_and_reopens(catalogue, monkeypatch):
    monkeypatch.setenv('MLATEON_INDEX_PATH', '/release')
    with closing(sqlite3.connect(catalogue)) as writer:
        assert writer.execute('pragma journal_mode=wal').fetchone() == ('wal',)
    assert not catalogue.with_name(catalogue.name + '-wal').exists()
    with closing(db.get_connection()) as reader:
        assert reader.execute('select search_text from scores where id=1').fetchone() == ('two parts',)
        with closing(sqlite3.connect(catalogue)) as writer, writer:
            writer.execute("update scores set search_text='updated' where id=1")
        assert reader.execute('select search_text from scores where id=1').fetchone() == ('updated',)
        with pytest.raises(sqlite3.OperationalError, match='readonly'):
            reader.execute('update scores set search_text=null')


def test_initial_and_refined_search_use_30_candidates(monkeypatch):
    monkeypatch.setenv('MLATEON_INDEX_PATH', '/release')
    retrieve = Mock(return_value=[])
    monkeypatch.setattr(mlateon, 'search', retrieve)
    monkeypatch.setattr('src.llm.factory.default_client', Mock)
    search.smart_search('violin')
    retrieve.assert_called_with('/release', 'violin', 30)
    search.smart_refine(original_query='violin', refinement='two players',
                        previous_summary='', previous_recommendations=[])
    retrieve.assert_called_with('/release', 'violin two players', 30)
