# ScoreBase RAG System

## Structure

```
rag/
├── pyproject.toml                 # Dependencies
├── .gitignore                     # Ignore venv, data, cache
│
├── src/
│   ├── config.py                  # Paths and settings
│   ├── db.py                      # Read from Rails SQLite
│   │
│   ├── enrichment/                # MusicXML processing
│   │   ├── parser.py              # music21 feature extraction
│   │   └── enrich.py              # Helper to resolve paths
│   │
│   ├── pipeline/                  # Haystack RAG
│   │   ├── indexer.py             # Build vector index
│   │   └── search.py              # Query vector index
│   │
│   └── api/
│       └── main.py                # FastAPI server
│
├── scripts/
│   └── explore_mxl.py             # Test music21 on one file
│
└── data/
    └── chroma/                    # Vector DB (created on first index)
```

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  1. EXPLORE (understand your data)                          │
│     python scripts/explore_mxl.py                           │
│     → Tests music21 on one MXL file                         │
│     → Shows what features can be extracted                  │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  2. INDEX (build vector database)                           │
│     python -m src.pipeline.indexer 1000                     │
│     → Reads scores from Rails SQLite                        │
│     → Converts metadata to text                             │
│     → Embeds text into vectors                              │
│     → Stores in ChromaDB                                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  3. SEARCH (test queries)                                   │
│     python -m src.pipeline.search "easy Bach for piano"     │
│     → Embeds query                                          │
│     → Finds similar vectors                                 │
│     → Returns matching score IDs                            │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  4. SERVE (run API for Rails)                               │
│     python -m src.api.main                                  │
│     → FastAPI on http://localhost:8001                      │
│     → GET /search?q=easy+Bach+for+piano                     │
│     → Returns JSON with score IDs                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

```bash
cd rag

# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -e .

# Verify config (edit src/config.py if needed)
python scripts/explore_mxl.py

# Build index (start small)
python -m src.pipeline.indexer 100

# Test search
python -m src.pipeline.search "romantic piano sonata"

# Run API server
python -m src.api.main
# → http://localhost:8001/search?q=easy+Bach
```

---

## File Responsibilities

| File | What It Does |
|------|--------------|
| `config.py` | Paths to database, PDMX data, ChromaDB |
| `db.py` | Read scores from Rails SQLite |
| `parser.py` | Extract tempo, key, duration, ranges from MXL |
| `enrich.py` | Helper to resolve MXL file paths |
| `indexer.py` | Score → text → embedding → ChromaDB |
| `search.py` | Query → embedding → find similar → return IDs |
| `main.py` | REST API that Rails calls |

---

## Data Flow

```
Rails SQLite                    ChromaDB
┌─────────────┐                ┌─────────────┐
│ scores      │                │ vectors     │
│ - id        │    indexer     │ - embedding │
│ - title     │ ─────────────→ │ - score_id  │
│ - composer  │                │ - title     │
│ - genres    │                │ - composer  │
└─────────────┘                └─────────────┘
                                     ↑
                                     │ search
                                     │
                               "easy Bach"
```

---

## Rails Integration

```ruby
# app/services/rag_search.rb
class RagSearch
  def self.search(query, top_k: 10)
    response = HTTP.get(
      "http://localhost:8001/search",
      params: { q: query, top_k: top_k }
    )
    JSON.parse(response.body)["results"]
  end
end

# Usage in controller
ids = RagSearch.search("easy Bach for piano").pluck("score_id")
@scores = Score.where(id: ids)
```
