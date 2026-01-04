# ScoreBase

Open source sheet music search engine. Aggregates 100k+ public domain scores, normalizes metadata across sources, and provides AI-powered semantic search.

**Live:** [scorebase.org](https://scorebase.org)

## Free vs Pro

**Free:** Browse, search, download 100k+ public domain scores. Filter by key, time signature, voicing, difficulty, genre, period.

**Pro (€2.99/mo):** AI-powered Smart Search that understands musical context—"easy piano pieces in C major for beginners" or "romantic art songs for soprano with wide range."

### Why a subscription?

Smart Search runs on AI. AI costs money. Your subscription keeps it running while the catalog stays free for everyone.

## Data Sources

| Source | Content | Scores |
|--------|---------|--------|
| PDMX | General collection (MuseScore community exports) | ~93k |
| CPDL | Choral works with voicing metadata | ~43k |
| IMSLP | Instrumental and orchestral works | varies |
| OpenScore Lieder | 19th century art songs (voice + piano) | ~1.3k |
| OpenScore Quartets | String quartets | ~200 |

## Data Pipeline

### 1. Import
Each source has a dedicated importer handling its specific format and metadata structure.

### 2. Normalize
Raw imports have inconsistent metadata. Normalization standardizes:
- **Composers** — "Bach, J.S." → "Johann Sebastian Bach"
- **Genres** — Inferred from title, composer, instrumentation
- **Instruments** — Normalized names and family classification
- **Periods** — Medieval, Renaissance, Baroque, Classical, Romantic, Modern

### 3. Extract
For scores with MusicXML, music21 extracts musical features: pitch range, key/time signature analysis, tempo, duration, rhythmic patterns, harmonic content, and a computed difficulty score (1-5).

### 4. Index
Score metadata is embedded into vectors (sentence-transformers) and stored in ChromaDB for semantic search.

### 5. Search
Smart Search: query → embedding → vector similarity → LLM reranking (Groq/Llama 3.3) → results with explanations.

## Self-Hosting

```bash
bin/dev                              # Rails server
cd rag && python -m src.api.main     # RAG service on :8001
```

See `rag/` for the Python RAG service (FastAPI + ChromaDB + sentence-transformers).

## License

AGPL-3.0 — You can use, modify, and self-host freely. If you run a public service with modifications, you must share your changes.

## Attribution

Score data includes works from [PDMX](https://github.com/pnlong/PDMX) (CC BY 4.0), [OpenScore](https://openscore.cc) (CC0), [CPDL](https://www.cpdl.org), and [IMSLP](https://imslp.org).
