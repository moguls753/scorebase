# RAG Search System

## Architecture

```
INDEXING (one-time per score):
┌─────────────────────────────────────────────────────────────┐
│  Score Metadata (all non-nil fields)                        │
│              ↓                                              │
│  Groq Llama 3.3 70B                                         │
│  "Write 2-3 sentences describing this score for music       │
│   teachers searching for sheet music. Include explicit      │
│   difficulty words."                                        │
│              ↓                                              │
│  2-3 sentence description                                   │
│              ↓                                              │
│  Embedding (all-MiniLM-L6-v2)                               │
│              ↓                                              │
│  ChromaDB                                                   │
└─────────────────────────────────────────────────────────────┘

QUERYING (per search):
┌─────────────────────────────────────────────────────────────┐
│  User Query: "easy Bach for piano, something gentle"        │
│              ↓                                              │
│  Vector Similarity Search                                   │
│              ↓                                              │
│  Top 15 results                                             │
│              ↓                                              │
│  Groq Llama 3.3 70B                                         │
│  "Pick the 3 best matches and explain why they fit"         │
│              ↓                                              │
│  3 results + explanations                                   │
└─────────────────────────────────────────────────────────────┘
```

## LLM Provider

**Groq** (free tier)
- Model: `llama-3.3-70b-versatile`
- Rate limits: 30 req/min, 14,400 req/day
- Cost: $0 (free tier)
- Fallback: `llama-3.1-8b-instant` if rate limited

Check limits: https://console.groq.com/settings/limits

## Why This Approach

1. **LLM-generated descriptions** - Can infer teaching value, technical features (Alberti bass, arpeggios), and mood from metadata
2. **Explicit difficulty words** - "easy beginner piece" vs "virtuoso demanding" helps embeddings distinguish
3. **No query parsing/filters** - More robust, no risk of filter mismatches or empty results
4. **LLM at the end** - Handles negation ("not a fugue"), complex reasoning, explains matches

## Implementation Plan

### Phase 1: LLM-Generated Descriptions

- [ ] Create `src/pipeline/description_generator.py`
  - Takes score metadata dict (all non-nil fields)
  - Agent loop (max 3 attempts):
    1. Generate 2-3 sentence description
    2. Validate: all key metadata included? explicit difficulty words? natural prose?
    3. If invalid, critique and retry
  - Explicit difficulty words required: "easy beginner" / "intermediate" / "advanced challenging" / "virtuoso demanding"
  - Rate limiting: max 30 req/min

- [ ] Update `src/pipeline/indexer.py`
  - Replace `make_searchable_text()` with LLM generation
  - Store description in ChromaDB
  - Time estimate: ~50 min for 1,500 scores (may increase with retries)

### Phase 2: LLM Result Selection

- [ ] Create `src/pipeline/result_selector.py`
  - Takes user query + top 15 results
  - Calls Groq Llama 3.3 70B to pick best 3
  - Returns selections with explanations

- [ ] Update `src/pipeline/search.py`
  - Vector search returns top 15
  - Pass to result selector
  - Return 3 results with explanations

### Phase 3: API Integration

- [ ] Update `src/api/main.py`
  - New endpoint returns results + explanations
  - Response format for Rails integration

### Phase 4: Testing

- [ ] Test queries (from product doc):
  - "easy Bach for piano students"
  - "SATB piece for Easter"
  - "funeral music, peaceful, not too sad"
  - "Bach without fugue"
  - "pieces for teaching Alberti bass"

---

## Completed (Previous Work)

- [x] Curated test dataset (1,468 scores with music21 analysis)
- [x] Python RAG pipeline (Haystack + ChromaDB + SentenceTransformers)
- [x] FastAPI search endpoint
- [x] CPU-only PyTorch
- [x] Fixed difficulty: uses `melodic_complexity` (music21) as primary source

---

## Known Issues

### PDMX `complexity` field is unreliable
- 60% of Bach scores have `complexity=0` - wrong
- Music21 `melodic_complexity` (0-1) is accurate
- LLM should use melodic_complexity for difficulty words

---

## Available Metadata Fields

From Score model + music21 extraction (use all non-nil):

| Field | Example | Use in Description |
|-------|---------|-------------------|
| title | "Prelude in C major" | Title |
| composer | "Bach, Johann Sebastian" | Attribution |
| melodic_complexity | 0.72 | → "virtuoso demanding" |
| instruments | "Keyboard" | Instrumentation |
| voicing | "SATB" | Vocal parts |
| key_signature | "C major" | Key |
| time_signature | "4/4" | Meter |
| tempo_marking | "Allegro" | Character |
| duration_seconds | 240 | → "4 minute piece" |
| texture_type | "polyphonic" | Texture |
| num_parts | 4 | → "quartet" |
| lowest_pitch / highest_pitch | "C3" / "G5" | Range |
| has_dynamics | true | Expression |
| has_ornaments | true | Style |
| genres | "Baroque" | Period |
| lyrics_language | "Latin" | Text |
| is_vocal | true | Type |
| has_fugue | true | Form (for negation) |

### Difficulty Mapping (melodic_complexity)

| Range | Level | Words to Use |
|-------|-------|--------------|
| < 0.3 | Easy | "easy", "beginner", "simple", "accessible" |
| 0.3-0.5 | Intermediate | "intermediate", "moderate", "developing" |
| 0.5-0.7 | Advanced | "advanced", "challenging", "demanding" |
| > 0.7 | Virtuoso | "virtuoso", "technically demanding", "difficult", "expert" |

---

## Commands

```bash
# Setup
cd rag
source venv/bin/activate

# Set API key (you likely already have this from normalizer)
export GROQ_API_KEY=...

# Build index (with LLM descriptions)
python -m src.pipeline.indexer --limit 10   # test with 10 first
python -m src.pipeline.indexer --limit 100  # test with 100
python -m src.pipeline.indexer              # all scores (~50 min)

# Search
python -m src.pipeline.search "easy Bach for piano"

# API server
python -m src.api.main
```

---

## Cost & Time Estimates

| Operation | Model | Cost | Time |
|-----------|-------|------|------|
| Index 1,500 scores | Groq 70B (free) | $0 | ~50 min |
| Index 300k scores | Groq 70B (free) | $0 | ~7 days |
| 1 search query | Groq 70B (free) | $0 | ~1 sec |
| 1000 queries | Groq 70B (free) | $0 | - |

**Free tier limits:** 30 req/min, 14,400 req/day

At $2.99/month subscription with $0 LLM cost = **100% margin** (only infrastructure costs).
