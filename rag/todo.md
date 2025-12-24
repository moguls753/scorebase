# Music21 Extraction - Implementation Plan

## Overview

**Goal:** Add 4 new musical features + improved difficulty scoring + performance optimizations

**Current State:**
- 66 fields extracted from MusicXML
- Difficulty based only on `melodic_complexity` (inaccurate)
- Memory issues (1GB too low, OOM kills observed)
- Slow extraction (~10 sec/score average)

**Target State:**
- 70+ fields extracted
- `computed_difficulty` (1-5) based on ALL metrics
- New RAG-queryable features: hand_span, tessitura, position_shifts
- 3x faster extraction (cache chordify)
- Stable memory usage (2GB, no OOM kills)

---

## PART 1: Add New Extraction Functions (Python)

**File:** `rag/extract.py`

All new metrics will be stored in Score model for:
- RAG filtering ("piano pieces for small hands")
- UI display
- Debugging difficulty calculations

### Step 1.1: Add `extract_hand_span()` function

**Location:** After `extract_texture()` (around line 618), before `extract()` main function

**Add this function:**

```python
def extract_hand_span(score, result):
    """
    Find the largest simultaneous chord span in semitones.
    Only relevant for keyboard instruments.

    Use cases:
        - "Piano pieces for small hands" (span < 9)
        - "No large stretches" (span < 12)

    Example:
        C-E-G = 7 semitones (comfortable)
        C-E-A = 9 semitones (medium stretch)
        C-G-E (next octave) = 16 semitones (large stretch)
    """
    try:
        max_span = 0

        for part in score.parts:
            # Only check keyboard parts
            part_name = get_part_name(part).lower()
            if not any(k in part_name for k in ["piano", "organ", "harpsichord", "keyboard", "clavier"]):
                continue

            chords_list = list(part.flatten().getElementsByClass(chord.Chord))
            for c in chords_list:
                if len(c.pitches) >= 2:
                    pitches_sorted = sorted(c.pitches, key=lambda p: p.ps)
                    span = int(pitches_sorted[-1].ps - pitches_sorted[0].ps)
                    max_span = max(max_span, span)

        if max_span > 0:
            result["max_chord_span"] = max_span

    except Exception as e:
        result["_warnings"].append(f"hand_span: {e}")
```

**Verify:** `grep -n "def extract_hand_span" rag/extract.py` should show the function

---

### Step 1.2: Add `extract_tessitura()` function

**Location:** After `extract_hand_span()`, before `extract()` main function

**Add this function:**

```python
def extract_tessitura(score, result):
    """
    Calculate average pitch (tessitura) for each part.
    More useful than just min/max range for vocal queries.

    Use cases:
        - "Comfortable for alto" (tessitura avg 60-72 MIDI)
        - "Doesn't sit too high for soprano"
        - "Bass part in comfortable register"

    Example:
        Soprano: range C4-A5, tessitura G4-D5 (mostly stays around middle)
        Bass: range E2-E4, tessitura A2-D3 (comfortable low range)
    """
    try:
        tessitura = {}

        for part in score.parts:
            part_name = get_part_name(part)
            # Only get Note objects, not Chords
            pitches = [n.pitch.ps for n in part.flatten().notes if isinstance(n, note.Note)]

            if pitches:
                avg_pitch = sum(pitches) / len(pitches)

                # Convert back to note name
                avg_note = pitch.Pitch()
                avg_note.ps = avg_pitch

                tessitura[part_name] = {
                    "average_pitch": avg_note.nameWithOctave,
                    "average_midi": round(avg_pitch, 1)
                }

        if tessitura:
            result["tessitura"] = tessitura

    except Exception as e:
        result["_warnings"].append(f"tessitura: {e}")
```

**Verify:** `grep -n "def extract_tessitura" rag/extract.py` should show the function

---

### Step 1.3: Add `extract_register_shifts()` function

**Location:** After `extract_tessitura()`, before `extract()` main function

**Add this function:**

```python
def extract_register_shifts(score, result):
    """
    Count large melodic jumps (>5 semitones) that indicate position changes.
    Relevant for strings, winds, brass - indicates technical difficulty.

    Use cases:
        - "No position changes" (beginner pieces)
        - "Stays in one position" (shift_count low)
        - Difficulty indicator (high shifts = harder)

    Threshold: >5 semitones (larger than fourth) = likely position shift
    """
    try:
        shift_count = 0

        for part in score.parts:
            notes_list = [n for n in part.flatten().notes if isinstance(n, note.Note)]

            for i in range(1, len(notes_list)):
                interval_size = abs(notes_list[i].pitch.ps - notes_list[i-1].pitch.ps)
                if interval_size > 5:  # Larger than fourth
                    shift_count += 1

        if shift_count > 0:
            result["position_shift_count"] = shift_count

            # Normalize by piece length for better comparison
            if result.get("measure_count") and result["measure_count"] > 0:
                result["position_shifts_per_measure"] = round(
                    shift_count / result["measure_count"], 2
                )

    except Exception as e:
        result["_warnings"].append(f"register_shifts: {e}")
```

**Verify:** `grep -n "def extract_register_shifts" rag/extract.py` should show the function

---

### Step 1.4: Add `compute_difficulty_score()` function

**Location:** After `extract_register_shifts()`, before `extract()` main function

**Add this function:**

```python
def compute_difficulty_score(result) -> int:
    """
    Compute difficulty score (1-5) based on ALL extracted metrics.
    Uses both existing metrics and newly added ones.

    Returns:
        1 = Beginner
        2 = Easy
        3 = Intermediate
        4 = Advanced
        5 = Expert

    Scoring (0-13 points total):
        - Note density: 0-2 points
        - Chromatic complexity: 0-2 points
        - Rhythm complexity: 0-2 points
        - Melodic intervals: 0-2 points
        - Tempo: 0-1 point
        - Modulations: 0-1 point
        - Polyphony: 0-1 point
        - Hand span (piano): 0-1 point
        - Position shifts: 0-1 point

    Mapping:
        0-2 points   → 1 (Beginner)
        3-5 points   → 2 (Easy)
        6-8 points   → 3 (Intermediate)
        9-11 points  → 4 (Advanced)
        12+ points   → 5 (Expert)
    """
    points = 0

    # Note Density (0-2 points)
    density = result.get("note_density", 0)
    if density > 20:
        points += 2
    elif density > 10:
        points += 1

    # Chromatic Complexity (0-2 points)
    chromatic = result.get("chromatic_complexity", 0)
    if chromatic > 0.3:
        points += 2
    elif chromatic > 0.15:
        points += 1

    # Rhythm Complexity (0-2 points)
    if result.get("syncopation_level", 0) > 0.3:
        points += 1
    if result.get("rhythmic_variety", 0) > 0.7:
        points += 1

    # Melodic Intervals (0-2 points)
    largest = result.get("largest_interval", 0)
    if largest > 12:  # Octave+
        points += 2
    elif largest > 7:  # Fifth+
        points += 1

    # Tempo (0-1 point)
    if result.get("tempo_bpm", 120) > 150:
        points += 1

    # Modulations (0-1 point)
    if result.get("modulation_count", 0) > 2:
        points += 1

    # Polyphony/Counterpoint (0-1 point)
    if result.get("voice_independence", 0) > 0.7:
        points += 1

    # Hand Span - Piano difficulty (0-1 point)
    if result.get("max_chord_span", 0) > 12:  # Tenth or larger
        points += 1

    # Position Shifts - Instrumental difficulty (0-1 point)
    shifts_per_measure = result.get("position_shifts_per_measure", 0)
    if shifts_per_measure > 0.5:  # More than 1 shift every 2 measures
        points += 1

    # Map to 1-5 scale
    if points <= 2:
        return 1  # Beginner
    elif points <= 5:
        return 2  # Easy
    elif points <= 8:
        return 3  # Intermediate
    elif points <= 11:
        return 4  # Advanced
    else:
        return 5  # Expert
```

**Verify:** `grep -n "def compute_difficulty_score" rag/extract.py` should show the function

---

### Step 1.5: Update `extract()` main function to call new functions

**Location:** Find the `extract()` function (around line 625)

**Find this section:**
```python
        # Run all extractions
        extract_pitch_range(score, result)
        extract_tempo_duration(score, result)
        extract_complexity(score, result)
        extract_rhythm(score, result)
        extract_harmony(score, result)
        extract_melody(score, result)
        extract_structure(score, result)
        extract_notation(score, result)
        extract_lyrics(score, result)
        extract_instrumentation(score, result)
        extract_texture(score, result)

        result["extraction_status"] = "extracted"
```

**Replace with:**
```python
        # Run all extractions
        extract_pitch_range(score, result)
        extract_tempo_duration(score, result)
        extract_complexity(score, result)
        extract_rhythm(score, result)
        extract_harmony(score, result)
        extract_melody(score, result)
        extract_structure(score, result)
        extract_notation(score, result)
        extract_lyrics(score, result)
        extract_instrumentation(score, result)
        extract_texture(score, result)

        # New extractions (added 2025-12-24)
        extract_hand_span(score, result)
        extract_tessitura(score, result)
        extract_register_shifts(score, result)

        # Compute final difficulty score from all metrics
        result["computed_difficulty"] = compute_difficulty_score(result)

        result["extraction_status"] = "extracted"
```

**Verify:**
```bash
python3 rag/extract.py rag/tests/fixtures/simple.mxl 2>/dev/null | jq '.computed_difficulty'
# Should output a number 1-5 (or null if no test file)
```

---

## PART 2: Database Migration

### Step 2.1: Generate migration file

**Command:**
```bash
bin/rails generate migration AddNewExtractionFields
```

**File:** `db/migrate/YYYYMMDDHHMMSS_add_new_extraction_fields.rb`

**Replace contents with:**
```ruby
class AddNewExtractionFields < ActiveRecord::Migration[8.0]
  def change
    # Computed difficulty (1-5) based on ALL complexity metrics
    # Replaces melodic_complexity as primary difficulty indicator
    add_column :scores, :computed_difficulty, :integer
    add_index :scores, :computed_difficulty

    # Hand span for piano/keyboard works (semitones)
    # Enables "small hands friendly" queries
    add_column :scores, :max_chord_span, :integer

    # Average pitch per part (tessitura)
    # JSON: { "Soprano": { "average_pitch": "G4", "average_midi": 67.2 }, ... }
    # Enables "comfortable for alto" queries
    add_column :scores, :tessitura, :json

    # Position shifts for instrumental difficulty
    # Count of large interval jumps (>5 semitones)
    add_column :scores, :position_shift_count, :integer
    # Normalized by measure count for better comparison
    add_column :scores, :position_shifts_per_measure, :float
  end
end
```

**Verify migration file exists:**
```bash
ls -la db/migrate/*add_new_extraction_fields.rb
```

---

### Step 2.2: Run migration

**Commands:**
```bash
# Run migration
bin/rails db:migrate

# Verify new columns exist
bin/rails runner 'puts Score.column_names.grep(/computed_difficulty|chord_span|tessitura|shift/).join(", ")'
# Should output: computed_difficulty, max_chord_span, tessitura, position_shift_count, position_shifts_per_measure
```

---

## PART 3: Performance Optimizations

**Goal:** Reduce memory usage and speed up extraction

### Step 3.1: Cache `chordify()` operation

**Problem:** `chordify()` is called 3 times (lines 286, 399, 582) - very RAM-intensive

**Location:** `rag/extract.py`, find `def extract_harmony()` (around line 232)

**Current signature:**
```python
def extract_harmony(score, result):
```

**Change signature to accept optional chordified getter:**
```python
def extract_harmony(score, result, get_chordified=None):
```

**Inside the function, find this line (around line 286):**
```python
        # Chord analysis
        try:
            chordified = score.chordify()
```

**Replace with:**
```python
        # Chord analysis
        try:
            # Use cached chordified if available, otherwise compute
            if get_chordified is not None:
                chordified = get_chordified()
            else:
                chordified = score.chordify()
```

**Repeat for `extract_structure()` and `extract_texture()`:**

1. Find `def extract_structure(score, result):` (around line 379)
   - Change to: `def extract_structure(score, result, get_chordified=None):`
   - Find: `chordified = score.chordify()` (around line 399)
   - Replace with same pattern

2. Find `def extract_texture(score, result):` (around line 568)
   - Change to: `def extract_texture(score, result, get_chordified=None):`
   - Find: `chordified = score.chordify()` (around line 582)
   - Replace with same pattern

**Now update `extract()` main function:**

Find this section:
```python
        # Run all extractions
        extract_pitch_range(score, result)
        # ... other calls ...
        extract_harmony(score, result)
        # ...
        extract_structure(score, result)
        # ...
        extract_texture(score, result)
```

**Replace with:**
```python
        # Cache chordify operation (expensive, used by 3 functions)
        _chordified_cache = None

        def get_chordified():
            nonlocal _chordified_cache
            if _chordified_cache is None:
                _chordified_cache = score.chordify()
            return _chordified_cache

        # Run all extractions
        extract_pitch_range(score, result)
        extract_tempo_duration(score, result)
        extract_complexity(score, result)
        extract_rhythm(score, result)
        extract_harmony(score, result, get_chordified)  # Pass cache
        extract_melody(score, result)
        extract_structure(score, result, get_chordified)  # Pass cache
        extract_notation(score, result)
        extract_lyrics(score, result)
        extract_instrumentation(score, result)
        extract_texture(score, result, get_chordified)  # Pass cache

        # New extractions
        extract_hand_span(score, result)
        extract_tessitura(score, result)
        extract_register_shifts(score, result)

        # Compute final difficulty
        result["computed_difficulty"] = compute_difficulty_score(result)

        result["extraction_status"] = "extracted"

        # Cleanup - free memory immediately
        del score
        if _chordified_cache is not None:
            del _chordified_cache
```

**Impact:** 3x faster, uses 1/3 the RAM

---

### Step 3.2: Make modulation detection optional (OPTIONAL - can skip)

**Problem:** Modulation detection creates Score objects for every 8-bar chunk (memory intensive)

**Location:** Top of `rag/extract.py`, after imports (around line 62)

**Add this constant:**
```python
# Feature flags
EXTRACT_MODULATIONS = False  # Disabled by default - memory intensive, rarely useful
```

**Location:** Inside `extract_harmony()`, find the modulation detection section (around line 254-282)

**Wrap the modulation section:**
```python
        # Modulation detection (analyze key every 8 measures)
        if EXTRACT_MODULATIONS:  # Add this line
            modulations = []
            # ... rest of modulation code ...
```

**Note:** This step is optional. Modulation detection is interesting but rarely used and memory-intensive.

---

## PART 4: Infrastructure Changes

### Step 4.1: Increase job container memory

**File:** `config/deploy.yml`

**Find (around line 17-22):**
```yaml
  job:
    hosts:
      - 46.224.124.123
    cmd: bin/jobs
    options:
      memory: 1g
```

**Change to:**
```yaml
  job:
    hosts:
      - 46.224.124.123
    cmd: bin/jobs
    options:
      memory: 2g  # Increased from 1g - music21 needs more for complex scores
```

**Verify:**
```bash
grep -A 5 "job:" config/deploy.yml | grep memory
# Should show: memory: 2g
```

---

### Step 4.2: Create dedicated extractions queue

**File:** `config/queue.yml`

**Find the production workers section (around line 24):**
```yaml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    # CPU-heavy: PDF-to-image conversion
```

**Add NEW worker BEFORE the existing workers:**
```yaml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    # Memory & CPU-intensive: music21 extraction (Python)
    # Single thread to prevent OOM kills
    - queues:
        - extractions
      threads: 1  # One at a time - music21 is memory-hungry
      processes: 1
      polling_interval: 0.5

    # CPU-heavy: PDF-to-image conversion (ImageMagick/Ghostscript)
    # ... existing workers below ...
```

**Verify:**
```bash
grep -A 3 "extractions" config/queue.yml
# Should show the new extractions queue config
```

---

### Step 4.3: Update job to use new queue

**File:** `app/jobs/extract_pending_scores_job.rb`

**Find (around line 10):**
```ruby
class ExtractPendingScoresJob < ApplicationJob
  queue_as :default
```

**Change to:**
```ruby
class ExtractPendingScoresJob < ApplicationJob
  queue_as :extractions  # Dedicated queue with optimized memory settings
```

**Verify:**
```bash
grep "queue_as" app/jobs/extract_pending_scores_job.rb
# Should show: queue_as :extractions
```

---

## PART 5: Reset, Deploy & Monitor

### Step 5.1: Reset extraction status

**Purpose:** Force re-extraction of all scores to populate new fields

**Command:**
```bash
# Reset only scores that have MusicXML files
bin/rails runner '
  count = Score.extraction_extracted
               .where.not(mxl_path: [nil, "", "N/A"])
               .update_all(extraction_status: :pending, extracted_at: nil)
  puts "Reset #{count} scores to pending for re-extraction"
'
```

**Expected output:** `Reset XXXX scores to pending for re-extraction`

**Verify:**
```bash
bin/rails runner 'puts "Pending: #{Score.extraction_pending.count}, Extracted: #{Score.extraction_extracted.count}"'
# Should show high pending count
```

---

### Step 5.2: Update frontend helper to use `computed_difficulty`

**File:** `app/helpers/scores_helper.rb`

**Find the `score_difficulty_level` function (around line 284):**
```ruby
  def score_difficulty_level(score)
    if score.melodic_complexity.present?
      mc = score.melodic_complexity.to_f
      if    mc < 0.3 then 1  # easy
      elsif mc < 0.5 then 2  # medium
      elsif mc < 0.7 then 3  # hard
      else                4  # virtuoso
      end
    elsif score.complexity.to_i.positive?
      score.complexity.to_i.clamp(1, 4)
    end
  end
```

**Replace with:**
```ruby
  def score_difficulty_level(score)
    # Prefer new computed_difficulty (uses ALL metrics)
    if score.computed_difficulty.present?
      score.computed_difficulty.to_i.clamp(1, 5)
    # Fallback to old melodic_complexity
    elsif score.melodic_complexity.present?
      mc = score.melodic_complexity.to_f
      if    mc < 0.3 then 1  # easy
      elsif mc < 0.5 then 2  # medium
      elsif mc < 0.7 then 3  # hard
      else                4  # virtuoso
      end
    # Final fallback to PDMX legacy complexity
    elsif score.complexity.to_i.positive?
      score.complexity.to_i.clamp(1, 4)
    end
  end
```

**Verify:**
```bash
grep -A 10 "def score_difficulty_level" app/helpers/scores_helper.rb | grep computed_difficulty
# Should show the new logic
```

---

### Step 5.3: Set up recurring extraction job

**File:** `config/recurring.yml`

**Find the production section (around line 12):**
```yaml
production:
  # clear_solid_queue_finished_jobs:
  #   command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
  #   schedule: every hour at minute 12
```

**Uncomment and update the extract_pending_scores section (around line 27-31):**
```yaml
  extract_pending_scores:
    class: ExtractPendingScoresJob
    queue: extractions  # Use dedicated queue
    args: [ { limit: 1000 } ]  # Process 1000 scores per run
    schedule: every 4 hours  # Changed from "every day at 3am"
```

**Verify:**
```bash
grep -A 5 "extract_pending_scores" config/recurring.yml
# Should show uncommented with schedule: every 4 hours
```

**Note:** With ~61,000 pending scores, 1000 per run every 4 hours = ~10 days to complete initial run

---

### Step 5.4: Deploy changes

**Commands:**
```bash
# Commit changes
git add .
git commit -m "Add computed difficulty + new extraction features + performance optimizations

- Add 4 new extraction features: computed_difficulty, max_chord_span, tessitura, position_shifts
- Cache chordify() operation (3x faster, 1/3 RAM)
- Increase job memory: 1GB → 2GB
- Create dedicated extractions queue (1 thread)
- Update frontend to use computed_difficulty
- Set up recurring extraction every 4 hours"

# Deploy
bin/kamal deploy

# Or if already deployed, just redeploy app:
bin/kamal app boot
```

**Verify deployment:**
```bash
# Check job container memory
kamal app exec -r job "cat /sys/fs/cgroup/memory/memory.limit_in_bytes"
# Should show: 2147483648 (2GB)

# Check queue config
kamal app exec -r job "bin/rails runner 'puts SolidQueue::Worker.all.map(&:queues).flatten.uniq'"
# Should include "extractions"

# Check migration ran
kamal app exec -r job "bin/rails runner 'puts Score.column_names.include?(\"computed_difficulty\")'"
# Should output: true
```

---

### Step 5.5: Monitor extraction progress

**Watch logs:**
```bash
kamal logs -r job -f
# Should see extraction jobs running in extractions queue
```

**Check progress periodically:**
```bash
kamal app exec -r job "bin/rails runner '
  puts \"Pending: #{Score.extraction_pending.where.not(mxl_path: [nil, \"\", \"N/A\"]).count}\"
  puts \"Extracted: #{Score.extraction_extracted.where.not(computed_difficulty: nil).count}\"
  puts \"Failed: #{Score.extraction_failed.count}\"
'"
```

**Check memory usage:**
```bash
# While job is running
kamal app exec -r job "ps aux --sort=-%mem | head -5"
# Should not exceed 2GB
```

---

## Testing Checklist

Before marking as complete, verify:

- [ ] `rag/extract.py` has 4 new functions
- [ ] `extract()` calls all new functions
- [ ] Migration adds 5 new columns
- [ ] `config/deploy.yml` shows 2g memory for job
- [ ] `config/queue.yml` has `extractions` queue
- [ ] `extract_pending_scores_job.rb` uses `:extractions` queue
- [ ] Frontend helper checks `computed_difficulty` first
- [ ] Recurring job runs every 4 hours
- [ ] Test extraction works: `python3 rag/extract.py <test-file.mxl> | jq .computed_difficulty`
- [ ] Production extraction jobs are running without OOM kills

---

## Quick Test (Local)

```bash
# Test extraction on a simple piece
python3 rag/extract.py /path/to/simple/piece.mxl > /tmp/test.json

# Verify new fields present
jq '{
  computed_difficulty,
  max_chord_span,
  tessitura,
  position_shift_count,
  position_shifts_per_measure
}' /tmp/test.json

# Should show values (or null if not applicable)
```

---

## Expected Results

**After full implementation:**

- **70+ fields** extracted (was 66)
- **Better difficulty scoring** - uses 9 metrics instead of 1
- **3x faster extraction** - chordify cached
- **No OOM kills** - 2GB memory + 1 thread
- **RAG queries enabled:**
  - "piano pieces for small hands" → filter by `max_chord_span < 9`
  - "comfortable for alto" → filter by `tessitura` MIDI 60-72
  - "no position shifts" → filter by `position_shift_count < 10`
- **Automatic extraction** - every 4 hours, 1000 scores per run

---

## Rollback Plan

If issues occur:

```bash
# 1. Stop extraction jobs
kamal app exec -r job "bin/rails runner 'SolidQueue::Job.where(class_name: \"ExtractPendingScoresJob\").destroy_all'"

# 2. Revert deployment
git revert HEAD
bin/kamal deploy

# 3. Rollback migration (if needed)
bin/kamal app exec -r job "bin/rails db:rollback"
```

---

## Notes

- All new fields are **optional** (won't break if extraction fails)
- `computed_difficulty` uses existing + new metrics (backward compatible)
- Tessitura is JSON - can query specific parts: `tessitura->>'Soprano'`
- Hand span only populated for keyboard instruments
- Position shifts useful for all instruments but especially strings/winds
- Frontend gracefully falls back to old difficulty calculation if new field missing
