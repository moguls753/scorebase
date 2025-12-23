# RAG Pipeline

Rails owns all data writes. Python reads `search_text` from SQLite and indexes to ChromaDB.

**Core Principle:** Garbage in, garbage out. The RAG system is only as good as the text we embed.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ RAILS (SQLite owner - ALL writes)                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Import → Normalize → Enrich → Validate → Generate search_text  │
│                                                                 │
│  Background jobs handle everything. Single source of truth.     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                         SQLite DB
                    (scores + search_text)
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ PYTHON (ChromaDB owner - read-only from SQLite)                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Read search_text → Embed (sentence-transformers) → Index       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Pipeline Flow

```
Composer ──→ Period (strict: requires composer_normalized)
         │
         └─→ Instruments ──→ Genre ──→ Search Text ──→ Indexer
             (relaxed: any composer status except pending)
```

## Status

| Step | Status | Requires | Job |
|------|--------|----------|-----|
| Composer | ✅ | - | `NormalizeComposersJob` |
| Period | ✅ | `composer_normalized` | `NormalizePeriodsJob` |
| Instruments | ✅ | composer processed | `NormalizeInstrumentsJob` |
| Genre | ✅ | composer + instruments processed | `NormalizeGenresJob` |
| Search Text | ⬜ | all normalizers | TODO |
| Python Indexer | ⬜ | search_text generated | TODO (simplify) |

## Commands

```bash
bin/rails rag:stats

bin/rails normalize:composers LIMIT=1000
bin/rails normalize:periods LIMIT=1000
bin/rails normalize:instruments LIMIT=100 BACKEND=groq
bin/rails normalize:genres LIMIT=100 BACKEND=groq

# Reset tasks
bin/rails normalize:reset_instruments SCOPE=failed
bin/rails normalize:reset_genres SCOPE=failed
```

## Scope Guards

Jobs self-filter via enum scopes:

```ruby
Score.period_pending.composer_normalized
Score.instruments_pending.where.not(composer_status: "pending").safe_for_ai
Score.genre_pending.where.not(composer_status: "pending").where.not(instruments_status: "pending").safe_for_ai
```

## LLM Backends

All LLM operations support multiple backends:

| Backend | Use Case | Cost |
|---------|----------|------|
| **Groq** | Fast, production | API costs |
| **Gemini** | Alternative | API costs |
| **LMStudio** | Local testing, bulk | Free (GPU) |

```bash
BACKEND=groq bin/rails normalize:instruments LIMIT=100
BACKEND=lmstudio bin/rails normalize:genres LIMIT=1000
```

## RAG Status Enum

```ruby
enum :rag_status, {
  pending: "pending",      # Waiting for enrichment
  ready: "ready",          # All fields validated, ready for text generation
  templated: "templated",  # search_text generated
  indexed: "indexed",      # In vector store, searchable
  failed: "failed"         # Needs investigation
}
```

## Validation: Ready for RAG?

```ruby
def ready_for_rag?
  return false unless safe_for_ai?
  return false if title.blank? || composer.blank?
  return false unless composer_normalized?

  # At least 2 of these must be present
  [voicing.present?, genre_normalized?, period_normalized?, key_signature.present?].count(true) >= 2
end
```

## Search Text Generation (TODO)

Port from Python. Rails generates `search_text`, Python just embeds.

```ruby
# app/services/rag/search_text_generator.rb
PROMPT = <<~PROMPT
  Write a searchable description (150-250 words) covering:
  - Difficulty (easy/intermediate/advanced)
  - Character (mood/style)
  - Best for (sight-reading, recitals, church, exams)
  - Musical features (texture, harmony)
  - Key details (voicing, key, period)

  Use words musicians search: "sight-reading", "recital piece", "church anthem"

  Data: %{metadata_json}
  Return JSON: {"description": "..."}
PROMPT
```

## Implementation Checklist

### Done ✅
- [x] Database migration (rag_status, search_text, period, etc.)
- [x] LlmClient with Groq/Gemini/LMStudio support
- [x] PeriodInferrer (composer → period lookup)
- [x] InstrumentInferrer (LLM-based)
- [x] GenreInferrer (LLM-based)
- [x] NormalizeComposersJob
- [x] NormalizePeriodsJob
- [x] NormalizeInstrumentsJob
- [x] NormalizeGenresJob
- [x] `ready_for_rag?` validation

### Next ⬜
- [ ] SearchTextGenerator (port from Python)
- [ ] GenerateSearchTextJob
- [ ] `rag:generate` rake task
- [ ] Simplify Python indexer (remove LLM, just embed)
- [ ] Bulk processing locally
- [ ] Production deploy

## Data Quality Notes

- **Cleanup (2024-12):** Deleted 156k PDMX scores with `composer_status: failed` and `genre: NA` (garbage metadata). Now ~93k scores.
- **Mojibake:** Filtered via `safe_for_ai` scope.
- **IMSLP/CPDL:** No music21 data. Index with basic metadata.

## Open Questions

1. **Re-indexing:** When prompt changes, re-index all? Use `index_version`?
2. **Failed scores:** Manual review? Auto-retry?
3. **Bulk processing:** Local first (iterate on prompts), then production.

## Success Metrics

- **Coverage:** % scores with `rag_status: indexed`
- **Quality:** Search result relevance (manual testing)
- **Completeness:** % scores with period, genre, instruments filled

Target: 80% of scores indexed with valid data.
