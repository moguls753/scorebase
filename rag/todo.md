# RAG Embedding Strategy - TODO

## Current Status

First 1200 parsed PDMX scores (IDs 1121-2320) are NOT suitable for testing:
- 72% have no composer ("NA")
- Mostly folk/traditional music
- Only 1 Bach, 2 Mozart, 1 Beethoven

## Step 1: Curate Test Dataset (~420 scores)

Parse MusicXML for these scores:

```ruby
# Run in Rails console
ids = []
ids += Score.where(composer: 'Bach, Johann Sebastian').where.not(mxl_path: [nil, '']).limit(150).pluck(:id)
ids += Score.where(composer: 'Mozart, Wolfgang Amadeus').where.not(mxl_path: [nil, '']).limit(80).pluck(:id)
ids += Score.where(composer: 'Beethoven, Ludwig van').where.not(mxl_path: [nil, '']).limit(60).pluck(:id)
ids += Score.where(composer: 'Chopin, Frédéric').where.not(mxl_path: [nil, '']).limit(40).pluck(:id)
ids += Score.where(composer: 'Schubert, Franz').where.not(mxl_path: [nil, '']).limit(40).pluck(:id)
ids += Score.where("voicing LIKE '%SATB%'").where.not(mxl_path: [nil, '']).limit(50).pluck(:id)
ids.uniq!
puts "#{ids.count} scores to parse"
```

This gives diversity across:
- Composers (Bach, Mozart, Beethoven, Chopin, Schubert)
- Periods (Baroque, Classical, Romantic)
- Instruments (keyboard, orchestral, choral)
- Difficulty levels

---

## Step 2: Embedding Strategy - Hybrid Approach

### The Problem

**Vocabulary gap** between user queries and document metadata:

| User says | Database has |
|-----------|--------------|
| "easy Bach for beginners" | `composer: Bach, complexity: 1` |
| "something my choir can handle" | `voicing: SATB, complexity: 2` |
| "romantic, around 15 minutes" | `genre: classical, duration: 900` |

Direct metadata embedding may not match natural language queries well.

### The Solution: Hybrid Embedding Document

Combine THREE elements for each score:

#### A. Natural Prose Metadata
Convert raw fields to readable text:
```
"Prelude in C major" by Johann Sebastian Bach.
A Baroque period composition for keyboard.
Intermediate difficulty, suitable for students with 2-3 years experience.
Duration approximately 4 minutes. Key of C major, common time.
```

#### B. Contextual Descriptions
Add semantic context:
```
Good for: keyboard students, counterpoint study, Bach introduction.
Style: polyphonic, contrapuntal, pedagogical.
```

#### C. Synthetic Queries
Natural language queries that WOULD match this score:
```
- "easy Bach for piano students"
- "short baroque keyboard piece"
- "beginner-intermediate Bach"
- "grade 4-5 exam repertoire"
- "2-minute classical piano, not too hard"
```

### Why This Works

1. **Synthetic queries** bridge vocabulary gap - user query lands close to matching synthetic queries
2. **Natural prose** catches exact matches ("Bach", "BWV 846")
3. **Context** adds semantic richness for similar-but-different queries

---

## Step 3: Implementation Order

### Phase 1 - Minimal Viable Test (do this first)
1. Parse the 420 curated scores with music21
2. Build simple text documents (metadata as prose only, no synthetic queries)
3. Index into ChromaDB
4. Test 10-20 queries from product doc
5. Evaluate: are results relevant?

### Phase 2 - Add Synthetic Queries
1. Create template-based query generator using patterns from product doc:
   - `"easy {composer} for {instrument}"`
   - `"{voicing} piece for {occasion}"`
   - `"{period} music, {difficulty}"`
2. Generate 5-10 synthetic queries per score
3. Re-index with hybrid documents
4. Compare results to Phase 1

### Phase 3 - Refinement
1. Add more query templates based on what's missing
2. Consider LLM-generated queries for complex scores
3. Add occasion detection (Easter, Christmas, wedding, funeral)
4. Add mood/character descriptors

---

## Fields to Use

### From Score Model
- title, composer
- key_signature, time_signature
- instruments, voicing, num_parts
- genres, tags
- language (for vocal works)
- complexity (0-3)
- description

### From Music21 Enrichment
- duration_seconds
- tempo_bpm
- range_low/high (pitch names)
- range_low_midi/high_midi (for filtering)
- computed_difficulty (1-5)

---

## Target Queries to Test

From product doc - these should return good results:

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
