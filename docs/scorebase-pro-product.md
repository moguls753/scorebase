design ideas:

2. Dark Mode + Neon Accents
    High contrast dark backgrounds with vibrant neon colors. Futuristic, immersive, and easy on the eyes.

# ScoreBase Pro — Product Overview

## What Is ScoreBase?

ScoreBase is the largest free catalog of public domain sheet music. 300,000+ scores from IMSLP, CPDL, and other sources — searchable, downloadable, organized.

**Free version:** Browse, basic search, download PDFs.

**Pro version:** AI-powered smart search that understands musical context.

## Infrastructure

```
scorebase.org        → Main app (Rails + RAG)
cdn.scorebase.org    → Static assets / PDFs
```

Cloudflare handles DNS, CDN, rate limiting, security. One domain, one app, tiered features.

---

## The Problem

Finding the right sheet music is hard. Current search requires knowing exact titles, composers, or catalog numbers.

But musicians think differently:

- "I need something for my student who's been playing piano for 2 years"
- "We need a short sacred piece for Easter, SATB, not too difficult"
- "I'm looking for a violin sonata, romantic period, around 15 minutes"

Basic keyword search can't answer these questions.

## The Solution: RAG Smart Search

Natural language search that understands:

- **Difficulty levels** — "beginner", "intermediate", "2 years of experience"
- **Vocal ranges** — "soprano not above A4", "comfortable for bass"
- **Instrumentation** — "string quartet", "piano four hands", "SATB choir"
- **Duration** — "short piece", "around 10 minutes", "full recital program"
- **Style/Period** — "romantic", "baroque", "contemporary"
- **Occasion** — "Christmas", "wedding", "funeral", "graduation"
- **Mood** — "joyful", "meditative", "dramatic"

---

## Target Users

### 1. Piano/Instrument Teachers
Finding appropriate repertoire for students at different levels is time-consuming. Teachers need pieces that:
- Match student's current ability
- Challenge without overwhelming
- Fit exam requirements
- Keep students engaged

### 2. Choir Directors / Conductors
Programming concerts requires balancing:
- Vocal ranges suitable for their ensemble
- Difficulty level their group can handle
- Thematic coherence
- Variety in style and period

### 3. Music Students
Students searching for:
- Repertoire for auditions
- Pieces for recitals
- Exam-appropriate works
- Sight-reading practice material

### 4. Church Musicians
Weekly need for:
- Music matching liturgical season
- Appropriate difficulty for volunteer choirs
- Specific voicing (SATB, SAB, unison)
- Public domain (no licensing fees)

### 5. Amateur Musicians
Hobbyists looking for:
- Pieces they can actually play
- Music for home enjoyment
- Chamber music for playing with friends

---

## Example Queries by User Type

### Piano Teacher

> "I need 3 pieces for a grade 4 piano student exam, one baroque, one romantic, one 20th century"

> "My 8-year-old student loves fast pieces but struggles with hand crossings, what do you suggest?"

> "Easy Chopin for a teenager who just finished their first year of lessons"

> "Sight-reading pieces for intermediate students, 2 pages max"

> "Piano duets for teacher and beginner student"

### Choir Director

> "SATB piece for Easter, 3-4 minutes, soprano stays below B5, accessible for community choir"

> "Renaissance motet for advanced chamber choir, 12-16 voices"

> "Simple anthem for Advent, SAB or SATB, congregation could join on refrain"

> "Funeral music for mixed choir, peaceful, not too sad, English text preferred"

> "Concert opener, dramatic, under 5 minutes, shows off the choir"

### Orchestral Conductor

> "String orchestra piece for youth orchestra, no shifting required for violins"

> "Short orchestral work to open a concert, festive, around 8 minutes"

> "Chamber orchestra piece, classical period, with solo flute"

### Music Student

> "Violin audition pieces for conservatory, romantic period, shows technical ability and musicality"

> "Art songs in German for mezzo-soprano, not too high, good for competition"

> "Cello suites or sonatas for junior recital, around 20 minutes total"

> "Virtuoso piano pieces that sound harder than they are"

### Church Musician

> "Communion meditation for organ, quiet, 3-4 minutes"

> "Hymn arrangements for brass quartet, Easter Sunday"

> "Simple choral introit for Lent, minor key, SATB"

> "Wedding prelude pieces for string quartet, elegant, not overplayed"

### Amateur / Hobbyist

> "Piano pieces I can learn in a weekend, sounds impressive but not too hard"

> "String quartet music for intermediate players, fun to play"

> "Easy classical guitar pieces, no barre chords"

> "Flute and piano duets for playing with my daughter"

---

## What Are We Selling?

### Free Tier
- Full catalog access (300k+ scores)
- Basic search (title, composer, instrument)
- Download PDFs
- No account required

### Pro Tier — $2.99/month

- **Smart Search** — Natural language queries that understand musical context
- **Saved Searches** — Store and revisit complex queries
- **Favorites & Collections** — Organize your personal library
- **Difficulty Filtering** — Search by student level
- **Range Checking** — Filter by vocal/instrumental ranges
- **Recommendations** — "More like this" suggestions

## Why $2.99?

- Low enough for students and hobbyists
- Recurring revenue adds up (1000 users = $3k/month)
- Undercuts expensive alternatives
- Easy impulse decision for working musicians
- Cheaper than one private lesson

## Competitive Landscape

| Service | Price | Public Domain Focus | Smart Search |
|---------|-------|:-------------------:|:------------:|
| IMSLP | Free (ads) | Yes | No |
| Sheet Music Plus | Per score | No | No |
| Musicnotes | Per score | No | No |
| JW Pepper | Per score | No | No |
| **ScoreBase Pro** | $2.99/mo | Yes | Yes |

ScoreBase Pro is the only service combining free public domain scores with intelligent, context-aware search.

---

## Technical: How RAG Search Works

### 1. Embedding Generation
- Each score's metadata (title, composer, instruments, tags, description) → vector embedding
- Store 300k vectors in pgvector (Postgres extension)
- Update embeddings when new scores are added

### 2. Query Processing
- User query → embedding
- Extract structured data (difficulty, range, duration if mentioned)
- Combine semantic similarity with hard filters

### 3. Retrieval
- Find top N semantically similar scores
- Apply filters (instrument, voicing, difficulty)
- Re-rank by relevance score

### 4. Response
- Return ranked results with match explanations
- "This piece matches because: intermediate difficulty, SATB voicing, Easter text"

### Tech Stack
- **Rails** — App, auth, billing
- **Python/FastAPI** — RAG service
- **pgvector** — Vector storage in Postgres
- **Stripe** — Subscriptions
- **Kamal** — Deployment
- **Cloudflare** — CDN, rate limiting, security

---

## MVP Scope

### In MVP
1. User accounts (Devise)
2. Stripe subscription ($2.99/month)
3. RAG smart search (core feature)
4. Favorites (save scores)
5. Search history

### Not in MVP
- Collections/folders
- Sharing lists with others
- Recommendations engine
- Mobile app
- API access

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Free → Pro conversion | 2-5% |
| Monthly churn | < 5% |
| Search → Download rate | > 30% |
| Queries per pro user/month | > 10 |

---

## Roadmap

**Phase 1: MVP**
- User auth + Stripe billing
- RAG search service
- Basic favorites

**Phase 2: Retention**
- Collections/folders
- Search history
- Better recommendations

**Phase 3: Growth**
- API for developers
- Institutional accounts
- Mobile app
