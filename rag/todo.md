# RAG Embedding Strategy

## Current Status

**Phase 1 implementation complete. Ready for testing.**

### Completed
- [x] Curated test dataset extracted (1,468 scores with music21 analysis)
  - Bach: 150, Mozart: 80, Beethoven: 58, Chopin: 40, Schubert: 40 + folk/traditional
- [x] Python RAG pipeline built (Haystack + ChromaDB + SentenceTransformers)
- [x] Natural prose embedding document generation
- [x] FastAPI search endpoint
- [x] CPU-only PyTorch for lightweight deployment
- [x] Fixed difficulty source: now uses `melodic_complexity` (music21) instead of unreliable `complexity` (PDMX)

### Next Steps
- [ ] Re-index with fixed difficulty logic and test search queries
- [ ] Evaluate results against success criteria
- [ ] Iterate on prose generation if needed
- [ ] Phase 2: Add synthetic queries if results need improvement

### Known Issues

#### PDMX `complexity` field is unreliable
- 60% of Bach scores have `complexity=0` (beginner) - clearly wrong
- Music21 `melodic_complexity` (0-1) is accurate:
  - Bach fugues: 0.71-0.87 (advanced/virtuoso) ✓

**RAG indexer**: Fixed - now prioritizes `melodic_complexity`

**Rails view helper**: Needs fix - `app/helpers/scores_helper.rb` line 101:
```ruby
# Current (broken): only shows if complexity > 0
if score.complexity.to_i.positive?

# Should use melodic_complexity instead:
if score.melodic_complexity.present?
  # Convert 0-1 to 1-3 scale for meter display
end
```

---

## Architecture

### Embedding Model
- `all-MiniLM-L6-v2` (384 dimensions, fast, CPU-friendly)

### Document Format (Natural Prose)
Each score is embedded as readable prose:
```
"Prelude in C major" by Johann Sebastian Bach. This is for Keyboard.
This is an easy, simple piece suitable for beginners. The piece is in C major,
in 4/4 time. Duration is about 4 minutes, a short piece. The texture is
polyphonic, duet. Pitch range spans from C3 to G5. Contains dynamic markings,
ornaments. Genre: Baroque music, Keyboard.
```

### Fields Used in Embedding
From Score model + music21 extraction:
- title, composer
- instruments, voicing, is_vocal, has_accompaniment
- **melodic_complexity (0-1)** → primary difficulty source:
  - < 0.3: "easy, simple piece suitable for beginners"
  - 0.3-0.5: "moderate complexity, suitable for intermediate"
  - 0.5-0.7: "challenging piece for advanced players"
  - > 0.7: "virtuoso piece, technically demanding"
- complexity (0-3) → fallback only if melodic_complexity is null
- key_signature, time_signature, tempo_marking
- duration_seconds → "short piece", "medium length", "extended work"
- texture_type, num_parts → "solo/duet/trio/quartet"
- lowest_pitch, highest_pitch → vocal/pitch range
- has_dynamics, has_ornaments, has_articulations
- genres (includes period: "Baroque music", etc.)
- lyrics_language
- description

---

## Commands

### Setup (on target machine)
```bash
cd rag
python3.11 -m venv venv
source venv/bin/activate

# CPU-only PyTorch first
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt
```

### Build Index
```bash
rm -rf data/chroma  # Clear existing index
python -m src.pipeline.indexer -1  # Index all extracted scores
```

### Search
```bash
python -m src.pipeline.search "easy Bach for piano"
python -m src.pipeline.search "SATB piece for Easter"
python -m src.pipeline.search "short romantic piano piece"
```

### Start API Server
```bash
python -m src.api.main
# GET http://localhost:8001/search?q=easy+Bach&top_k=10
```

---

## Target Queries to Test

### Piano Teacher
- "easy Bach for piano students"
- "grade 4 piano exam piece, baroque"
- "beginner Chopin for teenager"

### Choir Director
- "SATB piece for Easter, soprano below B5"
- "simple anthem for community choir"
- "funeral music, peaceful, not too sad"

### Student
- "violin audition piece, romantic period"
- "virtuoso piano that sounds harder than it is"

### Church Musician
- "communion meditation for organ, quiet"
- "wedding prelude for string quartet"

---

## Success Criteria

- Top 5 results should include at least 2-3 relevant scores
- Difficulty filtering should work (beginner vs advanced)
- Period filtering should work (baroque vs romantic)
- Voicing/instrument filtering should work
- Duration estimates should be in right ballpark

---

## Phase 2: Synthetic Queries (if needed)

If Phase 1 results are poor, add synthetic queries to bridge vocabulary gap:

```python
# Template-based query generation
synthetic_queries = [
    f"easy {composer} for piano students",
    f"short {period} keyboard piece",
    f"beginner-intermediate {composer}",
    f"{voicing} piece for {occasion}",
]
```

These get appended to the document before embedding, helping match user queries that use different vocabulary than the metadata.

---

## Phase 3: Refinement (future)

1. LLM-generated queries for complex scores
2. Occasion detection (Easter, Christmas, wedding, funeral)
3. Mood/character descriptors
4. Re-ranking with cross-encoder for better precision
