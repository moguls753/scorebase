# ScoreBase

Open source sheet music search engine. Aggregates 100k+ scores from multiple archives, normalizes metadata across sources, and provides AI-powered semantic search.

**Live:** [scorebase.org](https://scorebase.org)

**Stack:** Rails + Python (FastAPI) · SQLite + Postgres + ChromaDB

## Data Sources

| Source | Content | Scores |
|--------|---------|--------|
| PDMX | General collection (MuseScore community exports) | ~93k |
| CPDL | Choral works with voicing metadata | ~43k |
| IMSLP | Instrumental and orchestral works | varies |
| OpenScore Lieder | 19th century art songs (voice + piano) | ~1.3k |
| OpenScore Quartets | String quartets | ~200 |

## Data Pipeline

### Import
Each source has a dedicated importer handling its specific format and metadata structure.

### Normalize
Raw imports have inconsistent metadata. LLM-powered normalizers standardize fields that can't be fixed with simple rules:

| Field | Example | Approach |
|-------|---------|----------|
| **Composers** | "Bach, J.S." → "Johann Sebastian Bach" | LLM with composer database context |
| **Voicing** | "For SATB choir" → `[S, A, T, B]` | LLM extracts from title/description |
| **Genres** | Inferred from title, composer, instrumentation | LLM classification |
| **Instruments** | Normalized names + family classification | Rule-based + LLM fallback |
| **Periods** | Composer birth year → Musical period | Rule-based lookup |

### Extract
For scores with MusicXML, Python extracts raw musical features:

**Per-score:** duration, tempo, key/time signatures, modulation count

**Per-part:** pitch range, tessitura (average pitch), note density, chromatic ratio, rhythmic complexity, interval patterns, max chord span (keyboard), position shifts (strings/guitar)

### Difficulty
Computed difficulty (1-5) uses instrument-specific weighted algorithms:

| Instrument | Key Factors |
|------------|-------------|
| **Keyboard** | Hand span, polyphony, tempo, chromatic content |
| **Guitar** | Position shifts, chord complexity, tempo |
| **Strings** | Position shifts, double stops, tempo |
| **Voice** | Range, tessitura, intervallic leaps |

Fallback: note density percentile when instrument-specific metrics unavailable.

### Index
Score metadata is embedded into vectors and stored in ChromaDB for semantic search.

### Search
Smart Search: query → embedding → vector similarity → LLM reranking → results with explanations.

## Roadmap: LLM-Enhanced Difficulty

Three planned improvements to difficulty scoring:

**1. Pedagogical Grade Normalizer** — For known repertoire, query LLM for standard grade levels (ABRSM/RCM). Algorithm difficulty becomes fallback for obscure pieces.

**2. Context-Aware Query Interpretation** — Infer user context at search time: student vs performer, pedagogical terms ("Grade 4") vs casual ("easy"), then rank accordingly.

**3. Conversational Clarification** — When "easy" is ambiguous, ask one clarifying question: true beginner, intermediate-accessible, or easy relative to concert repertoire.

## Self-Hosting

```bash
bin/dev                              # Rails server
cd rag && python -m src.api.main     # RAG service on :8001
```

See `rag/` for the Python RAG service.

## License

AGPL-3.0 — You can use, modify, and self-host freely. If you run a public service with modifications, you must share your changes.

## Attribution

Score data includes works from [PDMX](https://github.com/pnlong/PDMX) (CC BY 4.0), [OpenScore](https://openscore.cc) (CC0), [CPDL](https://www.cpdl.org), and [IMSLP](https://imslp.org).
