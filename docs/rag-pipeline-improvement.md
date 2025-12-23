# RAG Pipeline

Rails owns all data writes. Python reads `search_text` from SQLite and indexes to ChromaDB.

## Pipeline Flow

```
Import → Music21 → Composer → Period → Instruments → Genre → Search Text → Indexer
```

Each job only processes scores where prerequisites are met (via enum scopes).

## Status

| Step | Status | Requires | Job |
|------|--------|----------|-----|
| Composer | ✅ | - | `NormalizeComposersJob` |
| Period | ✅ | `composer_normalized` | `NormalizePeriodsJob` |
| Instruments | ⬜ | `composer_normalized` | TODO |
| Genre | ✅ | `composer_normalized` | `NormalizeGenresJob` |
| Search Text | ⬜ | all normalizers | TODO |

## Commands

```bash
bin/rails rag:stats

bin/rails normalize:composers LIMIT=1000
bin/rails normalize:periods LIMIT=1000
bin/rails normalize:genres LIMIT=100 BACKEND=groq
```

## Scope Guards

Jobs self-filter via enum scopes:

```ruby
Score.period_pending.composer_normalized
Score.genre_pending.composer_normalized.safe_for_ai
```

## Next

1. Instruments normalizer
2. Search text generation
3. Enable recurring jobs
