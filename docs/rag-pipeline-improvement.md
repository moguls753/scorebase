# RAG Pipeline Improvement Plan

## Overview

This document outlines the strategy for data normalization, correction, and RAG pipeline improvements for ScoreBase Pro. The goal: ensure only clean, validated data enters the vector store.

**Core Principle:** Garbage in, garbage out. The RAG system is only as good as the text we embed.

---

## Current State

### What We Have

| Component | Status | Notes |
|-----------|--------|-------|
| Import (PDMX, IMSLP, CPDL) | Working | Raw data, no normalization |
| `extraction_status` | Working | music21 feature extraction |
| `normalization_status` | Working | Composer names only |
| RAG Indexer | Working | No quality gate, indexes everything |
| Vector Store (ChromaDB) | Working | Contains unvalidated data |

### Data Quality Issues

1. **Composer names** - Partially normalized (AI-powered)
2. **Period/Era** - Inconsistent, often missing or wrong
3. **Genres** - Hyphen-delimited, inconsistent vocabulary
4. **Encoding issues** - Mojibake in some records (filtered via `safe_for_ai` scope)
5. **Missing fields** - IMSLP/CPDL lack music21 extraction data

### The Problem

```
Current: Import → (maybe normalize composer) → Index
                                                 ↑
                                          No quality gate!
```

Bad data pollutes the vector store. Search results suffer.

---

## Target Architecture

```
Import → Enrich → Validate → Template → Index
  ↓        ↓         ↓          ↓         ↓
 raw    background  gate     search    vector
 data     jobs    (rag_status) text     store
```

### Pipeline Stages

```ruby
enum :rag_status, {
  pending: 0,      # Waiting for enrichment
  ready: 1,        # All fields validated, ready for templating
  templated: 2,    # search_text generated
  indexed: 3,      # In vector store, searchable
  failed: -1       # Needs investigation
}
```

### New Fields

```ruby
# RAG Pipeline
rag_status: :integer, default: 0
search_text: :text                    # The templated text for embedding
search_text_generated_at: :datetime
indexed_at: :datetime
index_version: :integer               # For bulk re-indexing on template changes

# Data Corrections
period: :string                       # Normalized period (Baroque, Classical, etc.)
period_source: :string                # How we determined it (composer_map, llm, manual)
```

---

## Terminology Decisions

| Old Term | New Term | Reason |
|----------|----------|--------|
| `embedding_text` | `search_text` | Text is *for* embedding, not the embedding itself |
| `embedding_status` | `rag_status` | More descriptive of the full pipeline |
| embedded/indexed | `indexed` | Describes outcome (searchable), not process |

**The Process:**
- **Templating** = Converting structured data to text string
- **Embedding** = Converting text to vector (happens in indexer)
- **Indexing** = Storing vector in ChromaDB (happens with embedding)

---

## Data Correction Strategies

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

def normalize_genre(raw_genre)
  return nil if raw_genre.blank?

  GENRE_MAPPINGS.each do |pattern, normalized|
    return normalized if raw_genre.match?(pattern)
  end

  raw_genre.titleize # Fallback: titleize unknown genres
end
```

### 3. LLM-Based Field Validation (For Edge Cases)

Use LLM to check/correct fields that can't be handled by rules.

```ruby
# app/services/llm_field_validator.rb
class LlmFieldValidator
  PROMPT = <<~PROMPT
    You are a music librarian. Analyze this score metadata and correct any errors.

    Current data:
    - Title: %{title}
    - Composer: %{composer}
    - Period: %{period}
    - Genre: %{genre}

    Tasks:
    1. Is the title actually a genre? (e.g., "Motet" as title)
    2. Does the period match the composer's era?
    3. Is the genre classification correct?

    Return JSON:
    {
      "title_is_genre": true/false,
      "suggested_genre_from_title": "...",
      "period_correct": true/false,
      "suggested_period": "...",
      "genre_correct": true/false,
      "suggested_genre": "...",
      "confidence": 0.0-1.0
    }
  PROMPT

  def validate(score)
    # Call Groq/Gemini API
    # Parse response
    # Return corrections
  end
end
```

**Use sparingly:** API costs add up. Use for:
- Scores with missing period after composer lookup fails
- Titles that look like genres (single word, matches genre vocabulary)
- Validation sampling (spot-check 1% of data)

### 4. Title-Is-Genre Detection (Heuristic)

Quick check before LLM: is the title actually a genre?

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

### 5. Voicing Standardization (Rule-Based)

Normalize voicing strings to standard abbreviations.

```ruby
VOICING_MAPPINGS = {
  /soprano.*alto.*tenor.*bass/i => "SATB",
  /satb/i => "SATB",
  /soprano.*alto/i => "SA",
  /tenor.*bass/i => "TB",
  /ssaa/i => "SSAA",
  /ttbb/i => "TTBB",
  /unison/i => "Unison",
  /2.?part|two.?part/i => "2-Part",
  /3.?part|three.?part/i => "3-Part",
  /4.?part|four.?part/i => "4-Part",
}.freeze
```

### 6. Key Signature Normalization

Standardize key notation.

```ruby
KEY_MAPPINGS = {
  /c\s*major|c\s*dur/i => "C major",
  /c\s*minor|c\s*moll/i => "C minor",
  /g\s*major|g\s*dur/i => "G major",
  # ... etc
  /b\s*flat\s*major|bb\s*major/i => "Bb major",
  /f\s*sharp\s*minor|f#\s*minor/i => "F# minor",
}.freeze
```

---

## Validation Rules for `rag_status: :ready`

A score is ready for templating when:

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
    genre.present?,
    period.present?,
    key_signature.present?
  ].count(true) >= 2

  has_musical_context
end
```

---

## Search Text Template

```ruby
# app/services/search_text_generator.rb
class SearchTextGenerator
  def generate(score)
    parts = []

    # Core identification
    parts << "#{score.title} by #{score.composer}."

    # Period and style
    if score.period.present?
      parts << "#{score.period} period composition."
    end

    # Genre and form
    if score.genre.present?
      parts << "Genre: #{score.genre}."
    end

    # Voicing and instrumentation
    if score.voicing.present?
      parts << "Written for #{score.voicing}."
    end

    # Musical characteristics
    musical_chars = []
    musical_chars << "key of #{score.key_signature}" if score.key_signature.present?
    musical_chars << "#{score.time_signature} time" if score.time_signature.present?
    musical_chars << "#{score.texture_type} texture" if score.texture_type.present?

    parts << musical_chars.join(", ") + "." if musical_chars.any?

    # Lyrics/language
    if score.language.present?
      parts << "Text in #{score.language}."
    end

    # Difficulty/complexity
    if score.complexity.present?
      parts << complexity_description(score.complexity)
    end

    parts.join(" ").squish
  end

  private

  def complexity_description(level)
    case level
    when 1..2 then "Suitable for beginners."
    when 3..4 then "Intermediate difficulty."
    when 5..6 then "Advanced level."
    when 7.. then "Highly complex, for professionals."
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

### Phase 2: Core Services

1. `PeriodInferrer` - Composer → Period mapping
2. `GenreNormalizer` - Standardize genre vocabulary
3. `TitleGenreDetector` - Check if title is actually a genre
4. `VoicingNormalizer` - Standardize voicing strings
5. `SearchTextGenerator` - Create templated search text
6. `RagReadinessValidator` - Check if score is ready for RAG

### Phase 3: Background Jobs

```ruby
# Job orchestration (run in sequence per score)
class RagEnrichmentJob < ApplicationJob
  def perform(score_id)
    score = Score.find(score_id)

    # Skip if already indexed
    return if score.rag_status_indexed?

    # Step 1: Infer period from composer
    if score.period.blank? && score.normalization_normalized?
      period = PeriodInferrer.new.infer(score.composer)
      score.update(period: period, period_source: "composer_map") if period
    end

    # Step 2: Normalize genre
    if score.genres.present? && score.normalized_genre.blank?
      normalized = GenreNormalizer.new.normalize(score.genres)
      score.update(normalized_genre: normalized)
    end

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

    text = SearchTextGenerator.new.generate(score)
    score.update(
      search_text: text,
      search_text_generated_at: Time.current,
      rag_status: :templated
    )
  end
end
```

### Phase 4: Update Indexer

Modify `rag/src/pipeline/indexer.py` to:

1. Only fetch scores with `rag_status = 'templated'`
2. Use `search_text` directly (no LLM generation needed!)
3. Update `indexed_at` and `rag_status` after indexing

```python
# New flow in indexer.py
def index_scores(batch_size: int = 100):
    # Only get templated scores
    scores = fetch_templated_scores(batch_size)

    for score in scores:
        # Use pre-generated search_text (no LLM call!)
        embedding = embed(score.search_text)
        store_in_chroma(score.id, embedding, score.search_text)
        mark_as_indexed(score.id)
```

**Big win:** No LLM call per score during indexing! Templates are pre-generated.

### Where to Run: Local vs Production

| Task | Where | Why |
|------|-------|-----|
| Initial bulk processing | Local | Iterate fast, test templates, no prod risk |
| Template/model experiments | Local | Mistakes don't pollute prod index |
| Ongoing new scores | Production | Background jobs, stays in sync |
| Re-indexing after changes | Local first | Verify quality, then deploy |

**Workflow:**
1. Build & test pipeline locally
2. Bulk process against prod DB dump locally
3. Deploy and let background jobs handle new scores
4. For template changes: test locally, then re-index in prod

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
  task template: :environment do
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

## Next Coding Session Checklist

### Must Do
- [ ] Create migration for RAG pipeline fields
- [ ] Add `rag_status` enum to Score model
- [ ] Implement `PeriodInferrer` with composer map (~100 composers)
- [ ] Implement `SearchTextGenerator`
- [ ] Implement `RagReadinessValidator`
- [ ] Add scopes: `needs_enrichment`, `needs_templating`, `needs_indexing`
- [ ] Update indexer to use `search_text` directly

### Should Do
- [ ] Implement `GenreNormalizer`
- [ ] Implement `VoicingNormalizer`
- [ ] Add `TitleGenreDetector`
- [ ] Create rake tasks for pipeline management
- [ ] Add dashboard/stats for pipeline monitoring

### Could Do
- [ ] LLM-based field validation for edge cases
- [ ] Key signature normalization
- [ ] Batch re-indexing support (index_version tracking)
- [ ] Admin UI for manual corrections

---

## Open Questions

1. **ChromaDB vs pgvector:** Should we store embeddings in Postgres too? Would simplify architecture (one DB) but ChromaDB has better similarity search.

2. **Re-indexing strategy:** When template changes, do we re-index all? Use `index_version` to track?

3. **Failed scores:** How to handle? Manual review queue? Auto-retry with LLM fallback?

4. **IMSLP/CPDL extraction:** These don't have music21 data. Index anyway with basic metadata, or skip?

---

## Success Metrics

- **Coverage:** % of scores with `rag_status: :indexed`
- **Quality:** Search result relevance (manual testing)
- **Pipeline health:** % failed, avg time to index
- **Data completeness:** % of scores with period, genre, voicing filled

Target: 80% of scores indexed with valid data within 2 weeks of implementation.
