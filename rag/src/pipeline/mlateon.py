"""Exact mLateOn retrieval over a read-only snapshot of edition descriptions."""

import hashlib
import json
from itertools import islice
from contextlib import closing
from functools import lru_cache
from pathlib import Path
from threading import Lock

import numpy as np

from . import SearchBusy
from .. import db

MODEL = "lightonai/mLateOn"
REVISION = "bbd883ae1fadb563056ff73b1061ae8172a3fcda"
DIMENSION = 128
MAX_LENGTH = 512
FORMAT = {"version": 1, "model": MODEL, "revision": REVISION, "max_length": MAX_LENGTH}


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


class Encoder:
    def __init__(self):
        import torch
        from sentence_transformers import MultiVectorEncoder

        device = "cpu"
        if torch.cuda.is_available():
            device = "cuda"
        elif torch.backends.mps.is_available():
            device = "mps"
        self.model = MultiVectorEncoder(
            MODEL, revision=REVISION, local_files_only=True, device=device,
            model_kwargs={"dtype": torch.float32 if device == "cpu" else torch.float16,
                          "attn_implementation": "sdpa"},
        )
        # MultiVectorEncoder uses task-specific lengths, not max_seq_length.
        backbone = self.model[0]
        backbone.query_length = MAX_LENGTH
        backbone.document_length = MAX_LENGTH

    def encode(self, texts, *, query=False):
        # These methods apply the checkpoint's different [Q] and [D] prefixes.
        fn = self.model.encode_query if query else self.model.encode_document
        vectors = fn(texts, batch_size=12, convert_to_numpy=True, show_progress_bar=False)
        return [np.asarray(v, dtype=np.float16) for v in vectors]


def _valid_tokens(vectors):
    return (vectors.ndim == 2 and vectors.shape[1] == DIMENSION
            and 0 < len(vectors) <= MAX_LENGTH and np.isfinite(vectors).all())


def write_index(path, batches):
    """Consume batches of (score_id, description, document token vectors). Never replace a live index."""
    path = Path(path)
    path.mkdir(mode=0o700, parents=True, exist_ok=False)
    count = 0
    seen = set()
    with (path / "rows.jsonl").open("w", encoding="utf-8") as rows, (path / "tokens.f16").open("wb") as tokens:
        for batch in batches:
            for sid, text, vectors in batch:
                vectors = np.asarray(vectors, dtype="<f2")
                if sid in seen or not _valid_tokens(vectors):
                    raise ValueError("Invalid or duplicate mLateOn document")
                seen.add(sid)
                rows.write(json.dumps([sid, len(vectors), digest(text)]) + "\n")
                vectors.tofile(tokens)
                count += 1
    if not count:
        raise ValueError("No eligible descriptions to index")
    # Readers require the manifest: a failed build cannot be opened as a partial index.
    pending = path / "manifest.tmp"
    pending.write_text(json.dumps({**FORMAT, "count": count}), encoding="utf-8")
    pending.rename(path / "manifest.json")


def eligible(conn):
    rows = conn.execute("""SELECT id, search_text FROM scores
        WHERE deleted_at IS NULL AND rag_status IN ('templated', 'indexed')
          AND search_text IS NOT NULL ORDER BY id""")
    for sid, text in rows:
        if text.strip():
            yield sid, text


def build(path, reuse=None):
    prior = Index(reuse) if reuse is not None else None
    positions = {int(sid): i for i, sid in enumerate(prior.ids)} if prior else {}
    encoder = None
    reused = 0
    encoded = 0
    with closing(db.read_only_connection()) as conn:
        rows = eligible(conn)

        def batches():
            nonlocal encoder, reused, encoded
            while batch := list(islice(rows, 96)):
                cached, fresh = [], []
                for sid, text in batch:
                    i = positions.get(sid)
                    if i is not None and prior.hashes[i] == digest(text):
                        cached.append((sid, text, prior.tokens[prior.offsets[i]:prior.offsets[i + 1]]))
                    else:
                        fresh.append((sid, text))
                reused += len(cached)
                yield cached
                if fresh:
                    if encoder is None:
                        encoder = Encoder()
                    vectors = encoder.encode([text for _, text in fresh])
                    encoded += len(fresh)
                    yield ((sid, text, v) for (sid, text), v in zip(fresh, vectors, strict=True))

        write_index(path, batches())
    return {"reused": reused, "encoded": encoded, "total": reused + encoded}


def coverage(path):
    """Compare every eligible ID and text with one consistent catalogue read."""
    index = Index(path)
    hashes = dict(zip(index.ids.tolist(), index.hashes, strict=True))
    matched = missing = changed = 0
    with closing(db.read_only_connection()) as conn:
        for sid, text in eligible(conn):
            stored = hashes.pop(sid, None)
            if stored is None:
                missing += 1
            elif stored != digest(text):
                changed += 1
            else:
                matched += 1
    return {"matched": matched, "missing": missing, "changed": changed, "ineligible": len(hashes)}


class Index:
    def __init__(self, path):
        # Pin one release even if the operator switches the 'current' symlink while opening it.
        path = Path(path).resolve(strict=True)
        manifest = json.loads((path / "manifest.json").read_text())
        if any(manifest.get(k) != v for k, v in FORMAT.items()):
            raise ValueError("Incompatible mLateOn index")
        with (path / "rows.jsonl").open() as f:
            ids, lengths, self.hashes = zip(*(json.loads(line) for line in f), strict=True)
        if len(set(ids)) != len(ids) or len(ids) != manifest["count"] or min(lengths) < 1 or max(lengths) > MAX_LENGTH:
            raise ValueError("Invalid mLateOn row map")
        self.ids = np.asarray(ids, dtype=np.int64)
        self.offsets = np.cumsum([0, *lengths], dtype=np.int64)
        tokens = np.memmap(path / "tokens.f16", dtype="<f2", mode="r")
        self.tokens = tokens.reshape(int(self.offsets[-1]), DIMENSION)

    def candidates(self, query_tokens, limit):
        query = np.asarray(query_tokens, dtype=np.float32)
        if not _valid_tokens(query):
            raise ValueError("Invalid mLateOn query")
        scores = np.empty(len(self.ids), dtype=np.float64)
        for start in range(0, len(scores), 16):
            offsets = self.offsets[start:start + 17]
            dots = self.tokens[offsets[0]:offsets[-1]].astype(np.float32) @ query.T
            maxima = np.maximum.reduceat(dots, offsets[:-1] - offsets[0], axis=0)
            scores[start:start + len(maxima)] = maxima.sum(axis=1, dtype=np.float64)
        order = np.lexsort((self.ids, -scores))
        results = []
        # Refill past deleted, ineligible, or re-templated editions; never rank old tokens
        # and hand the selector a different description for the same id.
        for start in range(0, len(order), 64):
            group = order[start:start + 64]
            rows = db.get_smart_candidate_rows(self.ids[group].tolist())
            for i in group:
                row = rows.get(int(self.ids[i]))
                if row and digest(row["content"]) == self.hashes[i]:
                    results.append({**row, "similarity": float(scores[i])})
                    if len(results) == limit:
                        return results
        return results


@lru_cache(maxsize=1)
def _backend(path):
    return Index(path), Encoder()


_search_lock = Lock()


def warm_up(path):
    with _search_lock:
        index, encoder = _backend(path)
        if not _valid_tokens(encoder.encode(["sheet music"], query=True)[0]):
            raise ValueError("Invalid mLateOn encoder output")
        db.get_smart_candidate_rows([int(index.ids[0])])


def search(path, query, limit):
    if limit < 1:
        raise ValueError("Candidate limit must be positive")
    if not _search_lock.acquire(timeout=2):
        raise SearchBusy("mLateOn candidate search is busy")
    try:
        index, encoder = _backend(path)
        return index.candidates(encoder.encode([query], query=True)[0], limit)
    finally:
        _search_lock.release()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Build or check an immutable Smart Search index")
    parser.add_argument("path", type=Path, help="Index directory (must be new when building)")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--reuse", type=Path, help="Reuse matching IDs and texts from a trusted prior mLateOn build")
    mode.add_argument("--check", action="store_true", help="Check all eligible IDs and text hashes without writing")
    args = parser.parse_args()
    if args.check:
        result = coverage(args.path)
        print(json.dumps(result))
        raise SystemExit(int(any(result[k] for k in ('missing', 'changed', 'ineligible'))))
    print(json.dumps(build(args.path, reuse=args.reuse)))
