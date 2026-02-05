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
| **Search** | FTS5 trigram index, ChromaDB vectors, sentence-transformers |
| **AI** | LLM-powered normalization and reranking |
| **Extraction** | Python, music21, FastAPI |

## Pro

Smart search with LLM reranking (coming soon). Pro subscription covers API costs.

## Contributing

Contributions welcome. Areas where help is appreciated:

- Bug reports and UX feedback
- Suggestions for new data sources
- Improvements to metadata normalization or difficulty scoring

## License

**AGPL-3.0** — Use and modify freely. If you run a public service with modifications, share your changes.

## Attribution

Score data from [PDMX](https://github.com/pnlong/PDMX) (CC BY 4.0), [OpenScore](https://openscore.cc) (CC0), [CPDL](https://www.cpdl.org), and [IMSLP](https://imslp.org).
