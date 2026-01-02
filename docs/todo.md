# Performance Optimization TODO

## Problem: Slow Database Queries (1.5-2 seconds)

### Root Cause

Bot traffic is triggering slow queries by passing specific voicing parameters that aren't handled correctly:

**Example bot requests:**
- `?page=878&voicing=SAATTB`
- `?page=835&voicing=SSATBB`
- `?page=586&voicing=AATTBB`

**The bug:** In `scores_controller.rb` lines 158-173, the `apply_forces_filter` method only handles generic forces (solo, duet, trio, quartet, ensemble). When bots pass specific voicing like "SAATTB", it falls through to the `else` clause which returns **all 300,000 scores**, then tries to sort and paginate them.

```ruby
def apply_forces_filter(scores, forces)
  case forces
  when "solo"    then scores.solo
  when "duet"    then scores.duet
  when "trio"    then scores.trio
  when "quartet" then scores.quartet
  when "ensemble" then scores.ensemble
  else
    scores  # ← Returns ALL 300k scores! (Bug)
  end
end
```

**Result:** 1.5-2 second ActiveRecord queries

---

## Solutions

### Fix 1: Handle Specific Voicing (IMMEDIATE - 5 minutes)

**Priority:** HIGH
**Impact:** Queries drop from 1.5s → ~50ms
**File:** `app/controllers/scores_controller.rb`

**Change the `apply_forces_filter` method to:**

```ruby
def apply_forces_filter(scores, forces)
  case forces
  when "solo"
    scores.solo
  when "duet"
    scores.duet
  when "trio"
    scores.trio
  when "quartet"
    scores.quartet
  when "ensemble"
    scores.ensemble
  else
    # If it looks like a specific voicing (SATB, SSAA, etc.), filter by it
    if forces.present? && forces.match?(/^[SATB]+$/i)
      scores.where(voicing: forces.upcase)
    else
      scores
    end
  end
end
```

**Testing:**
```bash
# Before: ~1500ms
curl "https://scorebase.org/scores?voicing=SAATTB&page=1"

# After: ~50ms
```

---

### Fix 2: Add Composite Indexes (BETTER - 10 minutes)

**Priority:** HIGH
**Impact:** Further speedup for multi-filter queries
**File:** Create new migration

The `voicing` column has a single-column index, but common filter combinations need composite indexes.

**Create migration:**

```bash
bin/rails generate migration AddCompositeIndexesForFilters
```

**Migration content:**

```ruby
# db/migrate/XXXXXX_add_composite_indexes_for_filters.rb
class AddCompositeIndexesForFilters < ActiveRecord::Migration[8.1]
  def change
    # Common filter combinations from bot traffic analysis
    add_index :scores, [:voicing, :genre], name: "index_scores_on_voicing_and_genre"
    add_index :scores, [:voicing, :period], name: "index_scores_on_voicing_and_period"
    add_index :scores, [:voicing, :num_parts], name: "index_scores_on_voicing_and_num_parts"
    add_index :scores, [:source, :voicing], name: "index_scores_on_source_and_voicing"
  end
end
```

**Run migration:**

```bash
bin/rails db:migrate
bin/kamal deploy  # Deploy to production
```

**Note:** SQLite index creation is fast (< 1 second for 300k rows). Safe to run in production.

---

### Fix 3: Optimize Voice Type Scopes (MEDIUM - 30 minutes)

**Priority:** MEDIUM
**Impact:** Speeds up voice type filters (mixed, treble, mens, unison)
**File:** `app/models/score.rb` + migration

**Current problem:** Lines 271-277 use slow LIKE queries:

```ruby
scope :mixed_voices, -> {
  where("voicing LIKE '%S%' AND (voicing LIKE '%T%' OR voicing LIKE '%B%')")
}
scope :treble_voices, -> {
  where("voicing LIKE '%S%' AND voicing LIKE '%A%' AND voicing NOT LIKE '%T%' AND voicing NOT LIKE '%B%'")
}
scope :mens_voices, -> {
  where("(voicing LIKE '%T%' OR voicing LIKE '%B%') AND voicing NOT LIKE '%S%' AND voicing NOT LIKE '%A%'")
}
```

These LIKE queries are slow on 300k rows because they can't use indexes effectively.

**Solution:** Add a computed `voice_type` column

**Step 1: Create migration**

```bash
bin/rails generate migration AddVoiceTypeToScores
```

```ruby
class AddVoiceTypeToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :voice_type, :string
    add_index :scores, :voice_type
  end
end
```

**Step 2: Add computation method to Score model**

```ruby
# app/models/score.rb

def compute_voice_type
  return nil if voicing.blank?

  has_soprano = voicing.include?("S")
  has_alto = voicing.include?("A")
  has_tenor = voicing.include?("T")
  has_bass = voicing.include?("B")

  if has_soprano && (has_tenor || has_bass)
    "mixed"
  elsif has_soprano && has_alto && !has_tenor && !has_bass
    "treble"
  elsif (has_tenor || has_bass) && !has_soprano && !has_alto
    "mens"
  elsif num_parts == 1
    "unison"
  else
    nil
  end
end

# Auto-compute on save
before_save :set_voice_type

def set_voice_type
  self.voice_type = compute_voice_type
end
```

**Step 3: Backfill existing records**

```bash
bin/rails runner 'Score.find_each { |s| s.update_column(:voice_type, s.compute_voice_type) }'
```

**Step 4: Update scopes to use indexed column**

```ruby
scope :mixed_voices, -> { where(voice_type: "mixed") }
scope :treble_voices, -> { where(voice_type: "treble") }
scope :mens_voices, -> { where(voice_type: "mens") }
scope :unison_voices, -> { where(voice_type: "unison") }
```

**Impact:** Voice type filters go from ~500ms → ~20ms

---

### Fix 4: Add HTTP Caching Headers (LATER - 2 hours)

**Priority:** LOW (do after Pro features are built)
**Impact:** Cloudflare edge caching → bot requests don't hit server
**File:** `app/controllers/scores_controller.rb`

**Add to `index` and `show` actions:**

```ruby
def index
  # Tell Cloudflare/browsers: cache this for 1 hour
  expires_in 1.hour, public: true

  # Existing code...
end

def show
  # Cache individual score pages for longer (scores rarely change)
  expires_in 6.hours, public: true

  # Existing code...
end
```

**Trade-offs:**
- Slightly stale data (acceptable for public domain catalog)
- Need cache invalidation when scores are added/updated
- Huge reduction in server load

---

## Bot Traffic Management

### Current Situation

**Bots crawling the site:**
- **GPTBot** (OpenAI) - Most active, systematic crawling
- **Amazonbot** - Individual score pages
- **Bytespider** (TikTok) - PDF downloads
- **SemrushBot** - SEO analysis

**Current robots.txt:** Blocks AI bots from downloading PDFs only, allows HTML crawling

### Should We Block Them?

**Decision: NO - Use rate limiting instead**

**Why allow AI bots:**
- Brand awareness in AI models (ChatGPT recommends ScoreBase when users ask)
- Future AI search engines (SearchGPT, Perplexity)
- Free user acquisition channel

**Why not block them:**
- GPTBot ≠ Googlebot (blocking GPTBot doesn't hurt SEO)
- AI recommendations valuable for discovery
- Can control load via rate limiting

### Rate Limiting Strategy

**Cloudflare Rate Limiting Rules** (see Cloudflare setup guide below):
- Allow AI bots to crawl
- But throttle them: 10 requests per minute per bot
- No server impact (handled at Cloudflare edge)
- Get brand awareness without server crush

---

## Implementation Priority

### Phase 1: Immediate (Do Now)
1. ✅ Fix voicing filter bug (Fix #1) - 5 minutes
2. ✅ Add composite indexes (Fix #2) - 10 minutes
3. ✅ Deploy fixes - 5 minutes

**Total time:** 20 minutes
**Expected impact:** 1500ms → 50ms on voicing queries

### Phase 2: Short Term (This Week)
1. Set up Cloudflare rate limiting for bots
2. Monitor query performance improvements

### Phase 3: Medium Term (When Building Pro Features)
1. Add `voice_type` column optimization (Fix #3)
2. Optimize other complex scopes if needed

### Phase 4: Later (Before Marketing Push)
1. Add HTTP caching headers (Fix #4)
2. Set up Cloudflare Page Rules for aggressive caching
3. Cache invalidation strategy

---

## Metrics to Track

**Before optimization:**
- Complex voicing queries: 1500-2000ms
- Simple queries: 20-50ms
- All requests: `cache: miss`

**After Phase 1 (target):**
- All queries: < 100ms
- Bot traffic: manageable load

**After Phase 4 (target):**
- Cache hit rate: > 80%
- Bot requests: served from edge (0ms server time)
- Real user requests: < 50ms

---

## Notes

- SQLite is handling 300k rows well for simple queries
- The issue is unoptimized scopes + bot crawl patterns
- Cloudflare CDN already in place, just needs configuration
- Don't over-optimize before validating Pro product-market fit
