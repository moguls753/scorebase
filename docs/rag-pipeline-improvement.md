# RAG Pipeline Improvement Plan

## Overview

This document outlines the strategy for data normalization, correction, and RAG pipeline improvements for ScoreBase Pro. The goal: ensure only clean, validated data enters the vector store.

**Core Principle:** Garbage in, garbage out. The RAG system is only as good as the text we embed.

---

## Architecture: Rails Owns Data, Python Owns Vectors

```
┌─────────────────────────────────────────────────────────────────┐
│ RAILS (SQLite owner - ALL writes)                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Import → Normalize → Enrich → Validate → Generate search_text  │
│                                                │                │
│                                               LLM               │
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
│  Also: Vector search, optional LLM re-ranking                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                          ChromaDB
                       (vector index)
```

**Key principle:** Rails owns all database writes. Python is a read-only consumer.

---

## Current State

### What We Have

| Component | Status | Notes |
|-----------|--------|-------|
| Import (PDMX, IMSLP, CPDL) | Working | Raw data, no normalization |
| `extraction_status` | Working | music21 feature extraction |
| `normalization_status` | Working | Composer names only |
| RAG Indexer (Python) | Working | No quality gate, indexes everything |
| Vector Store (ChromaDB) | Working | Contains unvalidated data |

### Data Quality Issues

1. **Composer names** - Partially normalized (AI-powered)
2. **Period/Era** - Inconsistent, often missing or wrong
3. **Genres** - Hyphen-delimited, inconsistent vocabulary
4. **Encoding issues** - Mojibake in some records (filtered via `safe_for_ai` scope)
5. **Missing fields** - IMSLP/CPDL lack music21 extraction data

### The Problem

```
Current: Import → (maybe normalize composer) → Index (Python generates text + embeds)
                                                 ↑
                                          No quality gate!
                                          Python writes descriptions
```

Bad data pollutes the vector store. Rails doesn't control what gets indexed.

---

## Target Architecture

```
Import → Enrich → Validate → Generate → Index
  ↓        ↓         ↓          ↓         ↓
 raw    background  gate     search    vector
 data     jobs    (rag_status) text     store
         (Rails)   (Rails)   (Rails)   (Python)
```

### Pipeline Stages

```ruby
enum :rag_status, {
  pending: 0,      # Waiting for enrichment
  ready: 1,        # All fields validated, ready for text generation
  templated: 2,    # search_text generated (LLM)
  indexed: 3,      # In vector store, searchable
  failed: -1       # Needs investigation
}
```

### New Fields

```ruby
# RAG Pipeline
rag_status: :integer, default: 0
search_text: :text                    # LLM-generated description for embedding
search_text_generated_at: :datetime
indexed_at: :datetime
index_version: :integer               # For bulk re-indexing on template changes

# Data Corrections
period: :string                       # Normalized period (Baroque, Classical, etc.)
period_source: :string                # How we determined it (composer_map, llm, manual)
normalized_genre: :string
```

---

## Terminology

| Term | Meaning |
|------|---------|
| `search_text` | LLM-generated description stored in SQLite |
| `rag_status` | Pipeline stage tracking |
| `indexed` | In ChromaDB, searchable |
| **Templating** | Transforming metadata → LLM prompt |
| **Generation** | LLM creates search_text |
| **Embedding** | Python converts text → vector |
| **Indexing** | Python stores vector in ChromaDB |

---

## LLM Backend Flexibility

All LLM operations must support multiple backends for testing and cost optimization:

| Backend | Use Case | Cost |
|---------|----------|------|
| **Groq** | Fast, reliable, production | API costs |
| **Gemini** | Alternative, good quality | API costs |
| **LMStudio** | Local testing, bulk processing | Free (GPU) |

### Affected Operations

1. **Composer Normalization** (existing) - already supports Groq/Gemini
2. **Search Text Generation** (new) - must support all three
3. **Field Validation** (optional) - must support all three

### Implementation Pattern

```ruby
# app/services/llm_client.rb
class LlmClient
  BACKENDS = %i[groq gemini lmstudio].freeze

  def initialize(backend: :groq)
    @backend = backend
    @client = build_client(backend)
  end

  def chat(prompt)
    case @backend
    when :groq    then @client.chat(prompt)
    when :gemini  then @client.generate(prompt)
    when :lmstudio then @client.complete(prompt)
    end
  end

  private

  def build_client(backend)
    case backend
    when :groq     then GroqClient.new
    when :gemini   then GeminiClient.new
    when :lmstudio then LmStudioClient.new
    end
  end
end

# Usage
generator = Rag::SearchTextGenerator.new(client: LlmClient.new(backend: :lmstudio))
```

### Configuration

```ruby
# config/environments/development.rb
config.llm_backend = :lmstudio  # Free local testing

# config/environments/production.rb
config.llm_backend = :groq  # Fast, reliable

# Override via ENV
ENV["LLM_BACKEND"] = "gemini"
```

### Rake Task Support

```bash
# Test with different backends
bin/rails rag:generate BACKEND=lmstudio LIMIT=100
bin/rails rag:generate BACKEND=groq LIMIT=100
bin/rails rag:generate BACKEND=gemini LIMIT=100
```

---

## Data Correction Strategies

> **Note:** All mappings below (composer periods, genres, voicings, etc.) are initial suggestions.
> They should be expanded and refined based on actual data analysis. Start small, iterate.

### 1. Period Inference from Composer (Deterministic)

Most reliable method. Composer → Period is a known mapping.

```ruby
# app/services/period_inferrer.rb
COMPOSER_PERIODS = {
  # Medieval (500-1400)
  "Hildegard von Bingen" => "Medieval",
  "Guillaume de Machaut" => "Medieval",

  # Renaissance (1400-1600)
  "Josquin des Prez" => "Renaissance",
  "Palestrina, Giovanni Pierluigi da" => "Renaissance",
  "Victoria, Tomás Luis de" => "Renaissance",
  "Byrd, William" => "Renaissance",
  "Lassus, Orlande de" => "Renaissance",

  # Baroque (1600-1750)
  "Bach, Johann Sebastian" => "Baroque",
  "Handel, George Frideric" => "Baroque",
  "Vivaldi, Antonio" => "Baroque",
  "Purcell, Henry" => "Baroque",
  "Monteverdi, Claudio" => "Baroque",
  "Schütz, Heinrich" => "Baroque",
  "Buxtehude, Dietrich" => "Baroque",

  # Classical (1750-1820)
  "Mozart, Wolfgang Amadeus" => "Classical",
  "Haydn, Joseph" => "Classical",
  "Beethoven, Ludwig van" => "Classical/Romantic",

  # Romantic (1820-1900)
  "Schubert, Franz" => "Romantic",
  "Brahms, Johannes" => "Romantic",
  "Mendelssohn, Felix" => "Romantic",
  "Schumann, Robert" => "Romantic",
  "Chopin, Frédéric" => "Romantic",
  "Liszt, Franz" => "Romantic",
  "Wagner, Richard" => "Romantic",
  "Verdi, Giuseppe" => "Romantic",
  "Dvořák, Antonín" => "Romantic",
  "Tchaikovsky, Pyotr Ilyich" => "Romantic",
  "Bruckner, Anton" => "Romantic",
  "Mahler, Gustav" => "Late Romantic",
  "Rachmaninoff, Sergei" => "Late Romantic",

  # 20th Century
  "Debussy, Claude" => "Impressionist",
  "Ravel, Maurice" => "Impressionist",
  "Stravinsky, Igor" => "20th Century",
  "Bartók, Béla" => "20th Century",
  "Shostakovich, Dmitri" => "20th Century",
  "Britten, Benjamin" => "20th Century",
  "Vaughan Williams, Ralph" => "20th Century",

  # Contemporary
  "Pärt, Arvo" => "Contemporary",
  "Lauridsen, Morten" => "Contemporary",
  "Whitacre, Eric" => "Contemporary",
  "Rutter, John" => "Contemporary",
}.freeze

def infer_period(composer)
  COMPOSER_PERIODS[composer]
end
```

**Coverage:** ~80% of scores (most are by well-known composers)

**Run after:** Composer normalization (needs canonical names)

### 2. Genre Vocabulary Normalization (Rule-Based)

Standardize genre strings to a controlled vocabulary.

```ruby
# app/services/genre_normalizer.rb
GENRE_MAPPINGS = {
  # Sacred/Religious
  /mass/i => "Mass",
  /motet/i => "Motet",
  /anthem/i => "Anthem",
  /hymn/i => "Hymn",
  /psalm/i => "Psalm",
  /requiem/i => "Requiem",
  /magnificat/i => "Magnificat",
  /sacred/i => "Sacred",
  /religious/i => "Sacred",
  /spiritual/i => "Spiritual",
  /gospel/i => "Gospel",
  /christmas|carol|noel/i => "Christmas",
  /easter/i => "Easter",

  # Secular
  /madrigal/i => "Madrigal",
  /chanson/i => "Chanson",
  /lied|lieder/i => "Lied",
  /art song/i => "Art Song",
  /folk/i => "Folk",
  /traditional/i => "Traditional",
  /popular|pop/i => "Popular",

  # Forms
  /fugue/i => "Fugue",
  /canon/i => "Canon",
  /chorale/i => "Chorale",
  /cantata/i => "Cantata",
  /oratorio/i => "Oratorio",
  /opera/i => "Opera",

  # Other
  /educational|teaching/i => "Educational",
  /contemporary/i => "Contemporary",
  /classical/i => "Classical",
}.freeze
```

### 3. Title-Is-Genre Detection (Heuristic)

Quick check: is the title actually a genre?

```ruby
# app/services/title_genre_detector.rb
GENRE_TITLES = %w[
  Motet Madrigal Mass Requiem Magnificat Anthem Hymn
  Psalm Chanson Lied Canon Fugue Chorale Cantata
  Gloria Credo Kyrie Sanctus Agnus Benedictus
].map(&:downcase).freeze

def title_is_likely_genre?(title)
  return false if title.blank?
  words = title.downcase.split(/\s+/)

  # Single word matching genre vocabulary
  return true if words.length == 1 && GENRE_TITLES.include?(words.first)

  # "Motet No. 3" pattern
  return true if words.first.in?(GENRE_TITLES) && words[1]&.match?(/no\.?|in|for/i)

  false
end
```

### 4. Voicing Standardization (Rule-Based)

```ruby
VOICING_MAPPINGS = {
  /soprano.*alto.*tenor.*bass/i => "SATB",
  /satb/i => "SATB",
  /ssaa/i => "SSAA",
  /ttbb/i => "TTBB",
  /unison/i => "Unison",
  /2.?part|two.?part/i => "2-Part",
  /3.?part|three.?part/i => "3-Part",
}.freeze
```

### 5. LLM-Based Field Validation (Edge Cases Only)

Use sparingly for:
- Scores with missing period after composer lookup fails
- Titles that look like genres
- Validation sampling (spot-check 1% of data)

---

## Validation Rules for `rag_status: :ready`

A score is ready for search_text generation when:

```ruby
# app/models/score.rb
def ready_for_rag?
  return false unless safe_for_ai?  # No mojibake
  return false if title.blank?
  return false if composer.blank?
  return false unless normalization_normalized?  # Composer normalized

  # At least some musical context
  has_musical_context = [
    voicing.present?,
    normalized_genre.present?,
    period.present?,
    key_signature.present?
  ].count(true) >= 2

  has_musical_context
end
```

---

## Search Text Generation (Rails + LLM)

Port from `rag/src/llm/description_generator.py` to Rails.

### MetadataTransformer (port from Python)

```ruby
# app/services/rag/metadata_transformer.rb
class Rag::MetadataTransformer
  def transform(score)
    {
      title: score.title,
      composer: score.composer,
      period: score.period,
      genre: score.normalized_genre,
      voicing: score.voicing,
      key: score.key_signature,
      time_signature: score.time_signature,
      texture: score.texture_type,
      difficulty_level: difficulty_words(score.complexity),
      language: score.language,
      # ... other relevant fields
    }.compact
  end

  private

  def difficulty_words(complexity)
    case complexity
    when 1..2 then "easy"
    when 3..4 then "intermediate"
    when 5..6 then "advanced"
    when 7.. then "virtuoso"
    else "intermediate"
    end
  end
end
```

### SearchTextGenerator (LLM-powered)

```ruby
# app/services/rag/search_text_generator.rb
class Rag::SearchTextGenerator
  PROMPT = <<~PROMPT
    You write rich, searchable descriptions for a sheet music catalog.
    Write 5-7 sentences (150-250 words) covering:
    - Difficulty (easy/intermediate/advanced/virtuoso)
    - Character (mood/style words)
    - Best for (specific uses: sight-reading, recitals, church, exams)
    - Musical features (texture, harmony, patterns)
    - Key details (duration, voicing, key, period)

    Use words musicians search: "sight-reading", "recital piece", "church anthem", etc.
    Only use facts from the data. Write natural prose, not bullet points.

    Data:
    %{metadata_json}

    Return JSON: {"description": "..."}
  PROMPT

  def initialize(client: nil)
    @client = client || GroqClient.new
  end

  def generate(score)
    metadata = Rag::MetadataTransformer.new.transform(score)
    prompt = PROMPT % { metadata_json: metadata.to_json }

    response = @client.chat(prompt)
    parsed = JSON.parse(response)

    Result.new(
      description: parsed["description"],
      success: valid?(parsed["description"])
    )
  rescue => e
    Result.new(description: nil, success: false, error: e.message)
  end

  private

  def valid?(text)
    return false if text.blank? || text.length < 200
    return false if text.length > 1500
    # Must mention difficulty
    text.downcase.match?(/easy|beginner|intermediate|advanced|virtuoso/)
  end

  Result = Data.define(:description, :success, :error) do
    def initialize(description:, success:, error: nil)
      super
    end
  end
end
```

---

## Implementation Plan

### Phase 1: Database Migration

```ruby
# db/migrate/XXXXXX_add_rag_pipeline_fields.rb
class AddRagPipelineFields < ActiveRecord::Migration[8.0]
  def change
    add_column :scores, :rag_status, :integer, default: 0, null: false
    add_column :scores, :search_text, :text
    add_column :scores, :search_text_generated_at, :datetime
    add_column :scores, :indexed_at, :datetime
    add_column :scores, :index_version, :integer

    add_column :scores, :period, :string
    add_column :scores, :period_source, :string
    add_column :scores, :normalized_genre, :string

    add_index :scores, :rag_status
    add_index :scores, :indexed_at
  end
end
```

### Phase 2: Core Services (Rails)

1. `PeriodInferrer` - Composer → Period mapping (config/composer_periods.yml) ✅
2. `LlmClient` - Unified client for Groq/Gemini/LMStudio ✅
3. `Score#ready_for_rag?` - Check if score is ready ✅
4. `Rag::MetadataTransformer` - Prepare data for LLM (port from Python)
5. `Rag::SearchTextGenerator` - LLM generates description + genre/instrument inference

### Phase 3: Background Jobs

```ruby
# Job orchestration (run in sequence per score)
class RagEnrichmentJob < ApplicationJob
  def perform(score_id)
    score = Score.find(score_id)
    return if score.rag_status_indexed?

    # Step 1: Infer period from composer (uses config/composer_periods.yml)
    if score.period.blank? && score.normalization_normalized?
      period = PeriodInferrer.infer(score.composer)
      score.update(period: period, period_source: "composer_map") if period
    end

    # Step 2: Genre/instrument inference handled by LLM in search_text generation

    # Step 3: Check readiness
    if score.ready_for_rag?
      score.update(rag_status: :ready)
      GenerateSearchTextJob.perform_later(score_id)
    end
  end
end

class GenerateSearchTextJob < ApplicationJob
  def perform(score_id)
    score = Score.find(score_id)
    return unless score.rag_status_ready?

    result = Rag::SearchTextGenerator.new.generate(score)

    if result.success
      score.update(
        search_text: result.description,
        search_text_generated_at: Time.current,
        rag_status: :templated
      )
    else
      score.update(rag_status: :failed)
    end
  end
end
```

### Phase 4: Simplify Python Indexer

Python becomes much simpler - just embed and store:

```python
# rag/src/pipeline/indexer.py (simplified)
def index_scores(batch_size: int = 100):
    """Index scores that have search_text ready."""
    # Only get templated scores (Rails already generated search_text)
    scores = db.query("""
        SELECT id, search_text FROM scores
        WHERE rag_status = 'templated'
        AND search_text IS NOT NULL
        LIMIT ?
    """, batch_size)

    for score in scores:
        # No LLM call! Just embed the pre-generated text
        embedding = embedder.embed(score.search_text)
        chroma.store(score.id, embedding, score.search_text)

        # Mark as indexed
        db.execute("""
            UPDATE scores
            SET rag_status = 'indexed', indexed_at = ?
            WHERE id = ?
        """, datetime.now(), score.id)
```

**Big win:** No LLM calls in Python. Rails handles all generation.

### Where to Run: Local vs Production

| Task | Where | Why |
|------|-------|-----|
| Initial bulk processing | Local | Iterate fast, test prompts, no prod risk |
| Prompt experiments | Local | Mistakes don't pollute prod index |
| Ongoing new scores | Production | Background jobs, stays in sync |
| Re-indexing after changes | Local first | Verify quality, then deploy |

**Workflow:**
1. Build & test pipeline locally
2. Bulk process against prod DB dump locally
3. Deploy and let background jobs handle new scores
4. For prompt changes: test locally, then re-index in prod

### Phase 5: Rake Tasks

```ruby
# lib/tasks/rag.rake
namespace :rag do
  desc "Enrich scores for RAG pipeline"
  task enrich: :environment do
    Score.normalization_normalized
         .where(rag_status: :pending)
         .find_each do |score|
      RagEnrichmentJob.perform_later(score.id)
    end
  end

  desc "Generate search text for ready scores"
  task generate: :environment do
    Score.rag_status_ready.find_each do |score|
      GenerateSearchTextJob.perform_later(score.id)
    end
  end

  desc "Show RAG pipeline stats"
  task stats: :environment do
    puts "RAG Pipeline Status:"
    puts "  Pending:   #{Score.rag_status_pending.count}"
    puts "  Ready:     #{Score.rag_status_ready.count}"
    puts "  Templated: #{Score.rag_status_templated.count}"
    puts "  Indexed:   #{Score.rag_status_indexed.count}"
    puts "  Failed:    #{Score.rag_status_failed.count}"
  end
end
```

---

## Step-by-Step Implementation Plan

> **Living document:** Update checkboxes as you progress. Add notes, dates, blockers.

### Step 1: Database Foundation ✅
- [x] Create migration for RAG pipeline fields (2024-12-23)
  - `rag_status`, `search_text`, `search_text_generated_at`
  - `indexed_at`, `index_version`
  - `period`, `period_source`, `normalized_genre`
- [x] Add `rag_status` enum to Score model
- [x] Add scopes: `rag_pending`, `rag_ready`, `rag_templated`, `rag_indexed`, `rag_failed`
- [x] Run migration, verify in console

### Step 2: Unified LLM Client ✅
- [x] Create `LlmClient` with Groq/Gemini/LMStudio support (2024-12-23)
- [ ] Test each backend manually (blocked: API keys not in dev credentials)
- [x] Add ENV-based backend selection (`LLM_BACKEND` env var)

### Step 3: Data Enrichment Services 🟡
- [x] Implement `PeriodInferrer` (composer → period lookup, ~47% coverage)
- [x] Implement `ready_for_rag?` validation on Score model
- [ ] ~~Implement `GenreNormalizer` (regex-based)~~ → **Changed: Use LLM**
- [ ] ~~Implement `InstrumentNormalizer` (regex-based)~~ → **Changed: Use LLM**

> **Decision (2024-12-23):** Rule-based genre/instrument normalization abandoned. Analysis showed:
> - PDMX: 164k scores have NO genres at all
> - CPDL/IMSLP: Genres/instruments embedded in complex strings
> - LLM is better suited for inferring genre/instruments from title/composer
>
> Genre and instrument inference will be handled during search_text generation (single LLM call).

### Step 4: Search Text Generation (Rails)
- [ ] Port `MetadataTransformer` from Python
- [ ] Port `SearchTextGenerator` from Python
- [ ] Add validation (length, difficulty term check)
- [ ] Test with all three LLM backends

### Step 5: Background Jobs
- [ ] Create `RagEnrichmentJob`
- [ ] Create `GenerateSearchTextJob`
- [ ] Test job chain with single score
- [ ] Test with batch of 10 scores

### Step 6: Rake Tasks
- [ ] `rag:enrich` - Queue enrichment jobs
- [ ] `rag:generate` - Queue text generation jobs
- [ ] `rag:stats` - Show pipeline statistics
- [ ] `rag:reset` - Reset rag_status for testing

### Step 7: Simplify Python Indexer
- [ ] Update indexer to read `search_text` from DB
- [ ] Remove LLM calls from Python
- [ ] Update `rag_status` to `indexed` after embedding
- [ ] Test full pipeline: Rails generate → Python embed

### Step 8: Bulk Processing (Local)
- [ ] Run enrichment on all scores locally
- [ ] Run text generation on ready scores
- [ ] Analyze failures, improve prompts/mappings
- [ ] Re-run until 80%+ success rate

### Step 9: Cleanup
- [ ] Remove `rag/src/llm/description_generator.py`
- [ ] Remove `rag/src/llm/metadata_transformer.py`
- [ ] Update Python imports/dependencies
- [ ] Document final architecture

### Step 10: Production Deploy
- [ ] Deploy Rails changes
- [ ] Run enrichment in production (background)
- [ ] Run text generation in production
- [ ] Re-index ChromaDB
- [ ] Verify search quality

---

## Quick Reference Checklist

| Phase | Status | Notes |
|-------|--------|-------|
| Migration | ✅ | `rag_status`, `search_text`, `period`, `normalized_genre` added |
| LLM Client | ✅ | Groq/Gemini/LMStudio support, needs API key testing |
| Enrichment | 🟡 | PeriodInferrer done (47%), genre/instrument → LLM |
| Text Gen | ⬜ | |
| Jobs | ⬜ | |
| Rake Tasks | ⬜ | |
| Python Update | ⬜ | |
| Bulk Process | ⬜ | |
| Cleanup | ⬜ | |
| Deploy | ⬜ | |

Legend: ⬜ Todo · 🟡 In Progress · ✅ Done · ❌ Blocked

---

## Open Questions

1. **Re-indexing strategy:** When prompt changes, do we re-index all? Use `index_version` to track?

2. **Failed scores:** How to handle? Manual review queue? Auto-retry?

3. **IMSLP/CPDL extraction:** These don't have music21 data. Index anyway with basic metadata, or skip?

4. **Groq vs local LLM:** For bulk generation, local LLM (LMStudio) might be cheaper. Worth supporting both in Rails?

---

## Success Metrics

- **Coverage:** % of scores with `rag_status: :indexed`
- **Quality:** Search result relevance (manual testing)
- **Pipeline health:** % failed, avg time to index
- **Data completeness:** % of scores with period, genre, voicing filled

Target: 80% of scores indexed with valid data.
