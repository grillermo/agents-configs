# Incremental Transcript Processing Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modify `amie_conversations/preprocess_production_transcript.rb` so repeated runs only process new conversations by detecting already-written files and stopping at the first known ID.

**Architecture:** Scan the output directory on startup to build a Set of already-processed IDs; emit epoch-prefixed filenames (`<epoch>_<id>.md`) so the folder sorts chronologically; break the CSV loop as soon as a known ID is encountered (safe because new rows are always prepended).

**Tech Stack:** Ruby stdlib only — `csv`, `fileutils`, `json`, `set`, `time`

**Spec:** `docs/superpowers/specs/2026-06-12-incremental-transcript-processing-design.md`

---

## Chunk 1: Epoch-prefixed filenames + requires

### Task 1: Add `require "set"` and `require "time"`

**Files:**
- Modify: `amie_conversations/preprocess_production_transcript.rb:1-7`

- [ ] **Step 1: Add the two requires**

At the top of the file, after the existing requires, add:

```ruby
require "set"
require "time"
```

The full require block becomes:

```ruby
require "csv"
require "fileutils"
require "json"
require "set"
require "time"
```

- [ ] **Step 2: Verify script still loads**

```bash
ruby -c amie_conversations/preprocess_production_transcript.rb
```

Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add amie_conversations/preprocess_production_transcript.rb
git commit -m "chore: add require set and time"
```

---

### Task 2: Add `early_exit_id` to `Result` struct

**Files:**
- Modify: `amie_conversations/preprocess_production_transcript.rb:9`

- [ ] **Step 1: Update `Result` struct**

Change:

```ruby
Result = Struct.new(:files_written, :rows_skipped, :errors, keyword_init: true)
```

To:

```ruby
Result = Struct.new(:files_written, :rows_skipped, :errors, :early_exit_id, keyword_init: true)
```

- [ ] **Step 2: Verify syntax**

```bash
ruby -c amie_conversations/preprocess_production_transcript.rb
```

Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add amie_conversations/preprocess_production_transcript.rb
git commit -m "feat: add early_exit_id to Result struct"
```

---

### Task 3: Epoch-prefixed filename in `write_markdown`

**Files:**
- Modify: `amie_conversations/preprocess_production_transcript.rb` — `write_markdown` method (lines ~62-68)

The goal: filename becomes `<epoch>_<id>.md` where epoch is `Time.parse(row["created_at"]).utc.to_i`.

- [ ] **Step 1: Update `write_markdown`**

Change:

```ruby
def write_markdown(row)
  id = fetch_required(row, id_column)
  response = JSON.parse(fetch_required(row, response_column))
  path = File.join(output_dir, "#{safe_filename(id)}.md")

  File.write(path, markdown_for(row, response), mode: "w", encoding: "UTF-8")
end
```

To:

```ruby
def write_markdown(row)
  id = fetch_required(row, id_column)
  response = JSON.parse(fetch_required(row, response_column))
  epoch = Time.parse(fetch_required(row, "created_at")).utc.to_i
  path = File.join(output_dir, "#{epoch}_#{safe_filename(id)}.md")

  File.write(path, markdown_for(row, response), mode: "w", encoding: "UTF-8")
end
```

Note: `fetch_required` already raises `KeyError` on missing/empty value, and `Time.parse` raises `ArgumentError` on bad input — both are caught by the existing per-row rescue in `run`.

- [ ] **Step 2: Verify syntax**

```bash
ruby -c amie_conversations/preprocess_production_transcript.rb
```

Expected: `Syntax OK`

- [ ] **Step 3: Smoke test on real CSV**

```bash
mkdir -p /tmp/transcript-test
ruby amie_conversations/preprocess_production_transcript.rb \
  production-transcript.csv /tmp/transcript-test 2>&1 | head -5
ls /tmp/transcript-test | head -5
```

Expected: filenames like `1746657516_9e51c126-3854-4533-be0e-e06679baf410.md`

- [ ] **Step 4: Clean up temp output**

```bash
rm -rf /tmp/transcript-test
```

- [ ] **Step 5: Commit**

```bash
git add amie_conversations/preprocess_production_transcript.rb
git commit -m "feat: epoch-prefixed output filenames"
```

---

## Chunk 2: Processed-ID set + early exit

> **Prerequisite:** Chunk 1 must be fully applied first. It adds `require "set"`, `require "time"`, and `:early_exit_id` to the `Result` struct — all required by this chunk.

### Task 4: Build processed-ID set on startup

**Files:**
- Modify: `amie_conversations/preprocess_production_transcript.rb` — add `processed_ids` private method, call it from `run`

- [ ] **Step 1: Add `processed_ids` method**

Add this private method after the `safe_filename` method (before the inner `SpeakerNames` class):

```ruby
def processed_ids
  pattern = File.join(output_dir, "*.md")
  Dir.glob(pattern).each_with_object(Set.new) do |path, set|
    name = File.basename(path, ".md")  # ".md" already stripped here
    # Strip leading epoch prefix if present (integer prefix, no underscores)
    id = name.match?(/\A\d+_/) ? name.split("_", 2)[1] : name
    set.add(id)
  end
end
```

- [ ] **Step 2: Verify syntax**

```bash
ruby -c amie_conversations/preprocess_production_transcript.rb
```

Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add amie_conversations/preprocess_production_transcript.rb
git commit -m "feat: build processed-ID set from output dir"
```

---

### Task 5: Early-exit loop in `run`

**Files:**
- Modify: `amie_conversations/preprocess_production_transcript.rb` — `run` method (lines ~35-55)

The loop must: check if `row[id_column]` is in the processed set → break with `early_exit_id` set; otherwise behave as before.

- [ ] **Step 1: Update `run` method**

Change:

```ruby
def run
  FileUtils.mkdir_p(output_dir)

  files_written = 0
  rows_skipped = 0
  errors = []

  CSV.foreach(input_path, headers: true) do |row|
    unless row[status_column] == completed_status
      rows_skipped += 1
      next
    end

    write_markdown(row)
    files_written += 1
  rescue JSON::ParserError, KeyError, ArgumentError => e
    errors << "#{row[id_column] || "unknown"}: #{e.class}: #{e.message}"
  end

  Result.new(files_written:, rows_skipped:, errors:)
end
```

To:

```ruby
def run
  FileUtils.mkdir_p(output_dir)

  files_written = 0
  rows_skipped = 0
  errors = []
  early_exit_id = nil
  seen = processed_ids

  CSV.foreach(input_path, headers: true) do |row|
    row_id = row[id_column]

    if seen.include?(row_id)
      early_exit_id = row_id
      break
    end

    unless row[status_column] == completed_status
      rows_skipped += 1
      next
    end

    write_markdown(row)
    files_written += 1
  rescue JSON::ParserError, KeyError, ArgumentError => e
    errors << "#{row_id || "unknown"}: #{e.class}: #{e.message}"
  end

  Result.new(files_written:, rows_skipped:, errors:, early_exit_id:)
end
```

- [ ] **Step 2: Verify syntax**

```bash
ruby -c amie_conversations/preprocess_production_transcript.rb
```

Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add amie_conversations/preprocess_production_transcript.rb
git commit -m "feat: stop processing at first already-processed ID"
```

---

## Chunk 3: CLI output + end-to-end verification

### Task 6: Print fourth summary line

**Files:**
- Modify: `amie_conversations/preprocess_production_transcript.rb` — CLI section at bottom (lines ~176-193)

- [ ] **Step 1: Add the fourth output line**

Change:

```ruby
puts "Wrote #{result.files_written} markdown files to #{output_dir}"
puts "Skipped #{result.rows_skipped} non-COMPLETED rows"

unless result.errors.empty?
  warn "Encountered #{result.errors.size} errors:"
  result.errors.each { |error| warn "  #{error}" }
  exit 1
end
```

To:

```ruby
puts "Wrote #{result.files_written} markdown files to #{output_dir}"
puts "Skipped #{result.rows_skipped} non-COMPLETED rows"

if result.early_exit_id
  puts "Stopped at already-processed id #{result.early_exit_id}"
else
  puts "Reached end of CSV"
end

unless result.errors.empty?
  warn "Encountered #{result.errors.size} errors:"
  result.errors.each { |error| warn "  #{error}" }
  exit 1
end
```

- [ ] **Step 2: Verify syntax**

```bash
ruby -c amie_conversations/preprocess_production_transcript.rb
```

Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add amie_conversations/preprocess_production_transcript.rb
git commit -m "feat: print early-exit or end-of-CSV summary line"
```

---

### Task 7: End-to-end verification

- [ ] **Step 1: Wipe existing output and do a full run**

```bash
cd amie_conversations
rm -rf production-transcript-conversations
ruby preprocess_production_transcript.rb
```

Expected output:
```
Wrote N markdown files to production-transcript-conversations
Skipped M non-COMPLETED rows
Reached end of CSV
```

Filenames should start with epoch digits:

```bash
ls production-transcript-conversations | head -5
```

Expected: `1746657516_9e51c126-...md` (10-digit prefix, underscore, UUID, `.md`)

- [ ] **Step 2: Run again immediately (no CSV change)**

```bash
ruby preprocess_production_transcript.rb
```

Expected:
```
Wrote 0 markdown files to production-transcript-conversations
Skipped 0 non-COMPLETED rows
Stopped at already-processed id <first-row-id>
```

Zero files written, stopped at the very first row.

- [ ] **Step 3: Confirm file count unchanged**

```bash
ls production-transcript-conversations | wc -l
```

Expected: same count as after step 1.

- [ ] **Step 4: Commit (if any last changes needed, else just tag as done)**

```bash
git status
```

If clean, no commit needed. If anything leftover:

```bash
git add amie_conversations/preprocess_production_transcript.rb
git commit -m "chore: verify incremental processing end-to-end"
```
