# Incremental Transcript Processing Design

**Date:** 2026-06-12
**File:** `amie_conversations/preprocess_production_transcript.rb`

## Problem

New conversations are continually prepended to `production-transcript.csv`. Each full re-run reprocesses the entire file unnecessarily. We need incremental processing: only write conversations not yet on disk, and stop as soon as a known ID is encountered.

## Design

### 1. Epoch-Prefixed Filenames

New output filenames: `<epoch>_<id>.md`

- Epoch = `created_at` column parsed via `Time.parse(created_at).utc.to_i` (requires `require "time"`). **Do not use `Time.iso8601`** — the CSV format (`2026-05-07 22:38:36.694+00`) uses a space separator and `+00` offset that `iso8601` rejects, causing an `ArgumentError` on every row.
- Example: `1746657516_9e51c126-3854-4533-be0e-e06679baf410.md`
- Files sort chronologically by name in any file browser or `ls`

### 2. Build Processed-ID Set on Startup

Before touching the CSV, scan `output_dir` for `*.md` files. Extract the UUID from each filename by stripping a leading `<digits>_` prefix (if present) and the `.md` suffix. Store IDs in a `Set`.

Supports both naming styles during migration:
- Old: `<id>.md` → ID = basename without `.md`
- New: `<epoch>_<id>.md` → ID = `filename.split('_', 2)[1]` stripped of `.md` (epoch is a plain integer — no underscores — so split on first `_` is unambiguous)

**Constraint:** IDs in the CSV are UUIDs (hex digits and hyphens only, no underscores). The `<digits>_` epoch prefix is therefore an unambiguous separator.

Empty folder → empty set → process everything.

### 3. Stop-on-Known-ID (Early Exit)

Walk CSV rows top-to-bottom (newest first, matching prepend order):

```
for each row:
  if row.id ∈ processed_set  → break (all remaining rows already done)
  if row.status != COMPLETED  → rows_skipped += 1; next
  write markdown              → files_written += 1
```

The `break` is safe because conversations are always prepended; any row below a known ID was processed in a prior run.

### 4. Error Handling

Existing per-row `rescue JSON::ParserError, KeyError, ArgumentError` is preserved. Added case: unparseable `created_at` → raises `ArgumentError` → caught, recorded as error, row skipped, processing continues to next row.

### 5. Output Summary

Add `early_exit_id` (nilable) to the `Result` struct. Set it to the matched row's id when breaking. The CLI section checks `result.early_exit_id` and prints the appropriate fourth line:

```
Stopped at already-processed id <id>   # if result.early_exit_id is set
Reached end of CSV                     # if result.early_exit_id is nil
```

## Migration

Delete the existing output directory and re-run:

```bash
rm -rf amie_conversations/production-transcript-conversations
ruby amie_conversations/preprocess_production_transcript.rb
```

No code change needed for migration; the script handles an empty folder on first run.

## Constraints & Trade-offs

- **Stop-on-known-ID skips back-fills.** If a previously-pending row is later completed and sits above a known ID in the CSV, it will never be processed. Acceptable per the prepend-only contract.
- **`created_at` parse error** is non-fatal: the row is skipped with an error entry, not a crash.
- **Set lookup is O(1)** — no performance concern even with thousands of files.
- **Requires `require "set"` and `require "time"`** — neither is in the current script.
