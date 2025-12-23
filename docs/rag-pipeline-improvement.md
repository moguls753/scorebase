# RAG Pipeline Improvement Plan

Rails owns all data writes. Python reads `search_text` from SQLite and indexes to ChromaDB.

---

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Schema | ✅ | `composer_status`, `genre_status`, `period_status`, `instruments_status` enums |
| Composer | ✅ | ~50k normalized, ~200k failed |
| Genre | ✅ | Service + rake task ready |
| Period | 🟡 | Service done, needs rake task |
| Instruments | ⬜ | Not started |
| Search Text | ⬜ | Port from Python |
| Python Indexer | ⬜ | Update to read `search_text` |

---

## Schema

All status fields use: `pending | normalized | not_applicable | failed`

```ruby
enum :composer_status, { pending, normalized, not_applicable, failed }
enum :genre_status, { pending, normalized, not_applicable, failed }
enum :period_status, { pending, normalized, not_applicable, failed }
enum :instruments_status, { pending, normalized, not_applicable, failed }

enum :rag_status, { pending, ready, templated, indexed, failed }
```

---

## Normalizers

### Composer (done)
```bash
bin/rails normalize:composers LIMIT=1000
bin/rails normalize:reset                    # Reset to pending
```

### Genre (done)
Vocabulary: `config/genre_vocabulary.yml` (~30 genres)

```ruby
result = GenreInferrer.new.infer(score)
result.found?     # => genre identified
result.success?   # => API call succeeded
result.genre      # => "Motet" or nil
```

```bash
bin/rails normalize:genres LIMIT=100 BACKEND=groq
bin/rails normalize:reset_genres SCOPE=failed
```

### Period (needs rake task)
Deterministic lookup from composer name.

```ruby
PeriodInferrer.infer("Bach, Johann Sebastian")  # => "Baroque"
```

### Instruments (TODO)
Normalize strings, infer from title when missing.

---

## Commands

```bash
bin/rails rag:stats                           # Pipeline status
bin/rails normalize:genres LIMIT=100          # Run genre inference
bin/rails normalize:reset_genres SCOPE=failed # Reset failures
bundle exec rspec spec/services/              # Run specs
```

---

## Next Steps

1. **Period rake task** - copy pattern from `normalize_genres.rake`
2. **Instruments normalizer** - service + vocabulary + rake task
3. **Search text generation** - port from Python
4. **Bulk processing** - run all normalizers, generate search_text, re-index

---

## Validation

Score is ready for RAG when:
- `safe_for_ai?` (no mojibake)
- `composer_normalized?`
- Has 2+ of: voicing, genre, period, key_signature

See `Score#ready_for_rag?` in `app/models/score.rb`
