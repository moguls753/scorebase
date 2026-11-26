# ScoreBase

Open source sheet music search engine. Aggregates scores from multiple archives, normalizes metadata with LLMs, and extracts musical features from MusicXML.

**Live at [scorebase.org](https://scorebase.org)** | **License: AGPL-3.0**

## What Is This?

**For musicians:** One search across free public domain scores and commercial arrangements. Filter by composer, instrument, genre, period, or difficulty. Download free PDFs, MusicXML, and MIDI — or purchase commercial arrangements via Sheet Music Direct.

**For developers:** A reference implementation of LLM-powered metadata normalization and MusicXML feature extraction for music information retrieval.

## Features

### Data Sources

| Source | Content | Type |
|--------|---------|------|
| PDMX | General collection (MuseScore community exports) | Free |
| CPDL | Choral works with voicing metadata | Free |
| IMSLP | Instrumental and orchestral works | Free |
| OpenScore Lieder | 19th century art songs | Free |
| OpenScore Quartets | String quartets | Free |
| Sheet Music Direct | Commercial arrangements (pop, jazz, film) | Commercial |

### LLM Metadata Normalization

Raw imports have inconsistent metadata. LLM normalizers standardize fields:

| Field | Example | Approach |
|-------|---------|----------|
| **Composers** | "Bach, J.S." → "Johann Sebastian Bach" | LLM with composer database |
| **Voicing** | "For SATB choir" → `[S, A, T, B]` | LLM extraction |
| **Genres** | Inferred from title, composer, instrumentation | LLM classification |
| **Instruments** | Normalized names + family classification | Rule-based + LLM |
| **Periods** | Composer birth year → Musical period | Rule-based lookup |
| **Pedagogical Grade** | Known repertoire → ABRSM/German grades | LLM lookup |

### MusicXML Feature Extraction

For scores with MusicXML, Python (music21) extracts:

- **Per-score:** duration, tempo, key/time signatures, modulation count
- **Per-part:** pitch range, tessitura, note density, chromatic ratio, rhythmic complexity, interval patterns

### Difficulty Scoring

Instrument-specific algorithms compute difficulty (1-5):

| Instrument | Key Factors |
|------------|-------------|
| **Keyboard** | Hand span, polyphony, tempo, chromatic content |
| **Guitar** | Position shifts, chord complexity, tempo |
| **Strings** | Position shifts, double stops, tempo |
| **Voice** | Range, tessitura, intervallic leaps |

For known repertoire, LLM-inferred pedagogical grades override algorithmic difficulty.

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Web** | Rails 8, Hotwire |
| **Data** | SQLite |
| **Search** | SQLite FTS5 for the catalogue; mLateOn token vectors and exact MaxSim for semantic search |
| **AI** | LLM-powered normalization and reranking |
| **Extraction** | Python, music21, FastAPI |

## Smart Search

Natural language search with LLM reranking — live in public BETA at `/smart-search`. Free during beta with a 5-searches/day per-IP cap. A planned Pro tier (€2/month, 100 searches/day) launches after BETA stabilizes; pricing covers the AI infrastructure costs while the catalog stays free.

### Building the Smart Search index

The mLateOn backend embeds existing edition descriptions as-is. Smart Search ranks the full index by exact MaxSim, then passes up to 30 candidates to the existing selector for up to three recommendations. The RAG API’s raw candidate endpoint reads the same index; the Rails catalogue search is separate. In a Python 3.11+ environment, from `rag/`:

```sh
python -m pip install -r requirements-mlateon.txt
hf download lightonai/mLateOn --revision bbd883ae1fadb563056ff73b1061ae8172a3fcda
export RAG_DB_PATH=/absolute/path/to/local/catalog.sqlite3
export MLATEON_INDEX_PATH=/absolute/path/to/a/new/index-directory
python -m src.pipeline.mlateon "$MLATEON_INDEX_PATH"
python -m src.pipeline.mlateon --check "$MLATEON_INDEX_PATH"
LLM_BACKEND=lmstudio LMSTUDIO_URL=http://127.0.0.1:1234/v1 LMSTUDIO_MODEL=your-local-model \
  python -m uvicorn src.api.main:app --host 127.0.0.1 --port 8001
```

Build from a consistent SQLite snapshot. All active `indexed` and `templated` rows with a nonblank `search_text` are eligible; `ready` means the text still needs to be written. The builder does not modify the catalogue. `--check` compares IDs and text hashes and exits nonzero on drift. For later builds, add `--reuse /path/to/trusted/previous-index` to reuse matching vectors while encoding additions and edits. Always write to a new directory outside the checkout or under the ignored `rag/data/` directory. Fresh retrievals exclude deleted or changed descriptions. Rails may reuse a previous answer for up to six hours within a release. After each index activation or rollback, `bin/rails rag:cutover_cache` prevents reuse of older answers without deleting search history.

The CPU serving image bundles the pinned query model and expects the completed index mounted read-only at `MLATEON_INDEX_PATH`. It will not start without a readable index, model and compatible catalogue. The service opens the catalogue in SQLite read-only mode. Its directory must allow SQLite to create WAL sidecar files after the last writer closes; never use `immutable=1` for a live catalogue. Changing an image, environment or mount requires recreating the accessory. For an index-only change, atomically switch the release symlink and restart the process. Use a **local** selector for private tests: the selector receives candidate descriptions.

## Contributing

Contributions welcome. Areas where help is appreciated:

- Bug reports and UX feedback
- Suggestions for new data sources
- Improvements to metadata normalization or difficulty scoring

## License

**AGPL-3.0** — Use and modify freely. If you run a public service with modifications, share your changes.

## Attribution

Score data from [PDMX](https://github.com/pnlong/PDMX) (CC BY 4.0), [OpenScore](https://openscore.cc) (CC0), [CPDL](https://www.cpdl.org), and [IMSLP](https://imslp.org).
