# RAG Pipeline

Rails owns all writes. Python reads `search_text` from SQLite and indexes to ChromaDB.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ RAILS (SQLite)                                                  │
│  Import → Normalize → Enrich → Validate → Generate search_text  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ PYTHON (ChromaDB)                                               │
│  Read search_text → Embed (sentence-transformers) → Index       │
└─────────────────────────────────────────────────────────────────┘
```

## Pipeline

```
Composer → Period → Instruments → Genre → mark_ready → generate → index
                                              │            │          │
                                        rag:pending   rag:ready   rag:templated → rag:indexed
```

## Commands

```bash
# Normalization (run in order)
bin/rails normalize:composers LIMIT=1000
bin/rails normalize:periods LIMIT=1000
bin/rails normalize:instruments LIMIT=100 BACKEND=groq
bin/rails normalize:genres LIMIT=100 BACKEND=groq

# RAG Pipeline
bin/rails rag:mark_ready                     # Move eligible → ready
bin/rails rag:generate LIMIT=100             # Generate search_text
bin/rails rag:generate LIMIT=100 FORCE=true  # Regenerate existing
bin/rails rag:reset SCOPE=failed             # Reset failed scores
bin/rails rag:stats                          # Show pipeline stats

# Python Indexer
cd rag && python -m rag.src.pipeline.indexer 100   # batch
cd rag && python -m rag.src.pipeline.indexer -1    # all
```

## LLM Backends

```bash
BACKEND=groq bin/rails rag:generate LIMIT=100      # Fast, API costs
BACKEND=lmstudio bin/rails rag:generate LIMIT=1000 # Local, free
```

## RAG Status

```ruby
enum :rag_status, {
  pending: "pending",      # Waiting for normalization
  ready: "ready",          # Validated, ready for LLM
  templated: "templated",  # search_text generated
  indexed: "indexed",      # In ChromaDB
  failed: "failed"
}
```

## Validation

```ruby
def ready_for_rag?
  return false if title.blank? || composer.blank?
  return false unless composer_normalized?
  # Need at least 2 of: voicing, genre, period, key_signature
  [voicing.present?, genre_normalized?, period_normalized?, key_signature.present?].count(true) >= 2
end
```

## Current State (2025-01)

```
Total scores: ~93k
├── composer_normalized: ~50k (real composers)
└── composer_failed:     ~43k (Traditional, Unknown, etc.)
```

## Data Notes

- Deleted 156k PDMX garbage, 45 corrupted scores
- Fixed 72 mojibake composers
- Traditional/Unknown marked `failed` (won't re-process)
- IMSLP/CPDL: no music21 data, indexed with basic metadata

## Next Steps

- [ ] Bulk processing locally (test full pipeline)
- [ ] Production deploy

## Open Questions

1. Re-indexing strategy when prompt changes?
2. Failed scores: manual review or auto-retry?
