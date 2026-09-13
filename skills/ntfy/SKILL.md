---
name: ntfy
description: Send the user a push notification to their phone through their self-hosted ntfy server (ntfy.chiq.me, topic claude-alerts). Use when the user invokes /ntfy, or asks to be notified, pinged, alerted or messaged on their phone — e.g. "ntfy me when the tests finish", "send me a notification", "ping my phone when the deploy is done" — including at the end of a long task they asked to be told about, and whenever they want a link (PR, deploy, dashboard, doc, search result) sent to their phone.
---

# ntfy

Sends a notification to the user's iPhone via their private ntfy server. Delivery
reaches them as a web push from the home-screen ntfy app, so keep messages short
enough to read on a lock screen.

## Workflow

1. Work out the message:
   - `/ntfy <text>` → send that text as the message.
   - `/ntfy` with no text → send a one- or two-sentence status of what was just
     done in this conversation (what finished, whether it succeeded).
   - "notify me when X is done" → finish X first, then send the outcome,
     including failure. A notification that says "done" when it failed is worse
     than none.
2. Pick optional headers only when they add something:
   - `-t` title: a short label, e.g. the project or task name.
   - `-p` priority `1`–`5` (or `min`/`low`/`default`/`high`/`urgent`): use
     `high` for failures or things needing action, default otherwise.
   - `-T` tags: comma-separated emoji shortcodes, e.g. `white_check_mark`,
     `x`, `warning`, `rocket`.
   - `-c` topic: only if the user names a different topic; default is
     `claude-alerts`.
   - `-l` URL, optionally followed by `-L` label: sends a link as a tappable
     "view" button (up to 3). Use it whenever the message is about something
     with a URL — a PR, a deploy, a CI run, a file you uploaded — so the user
     can open it straight from the notification. The first link also becomes
     the notification's tap target, because iPhone web push may not show the
     buttons. Without `-L` the button reads "Open <host>".
   - `-u` click URL: only to make tapping the notification open something
     other than the first link.
3. Run the script (absolute path, so it works from any directory):

   ```sh
   sh ~/.claude/skills/ntfy/scripts/ntfy-send.sh -t "Tests" -p high -T x "3 failures in spec/models"
   sh ~/.claude/skills/ntfy/scripts/ntfy-send.sh -t "PR ready" -T rocket \
     -l https://github.com/org/repo/pull/42 -L "Open PR" "Review requested on #42"
   ```

   Add `--dry-run` to preview what would be sent without sending.
4. Report the result briefly: on success the script prints the server's JSON
   (`"id"` confirms delivery to the server). On failure, show the error output
   and exit status instead of claiming it was sent.

## Notes

- Credentials come from `/Users/grillermo/c/ntfyllermo/.env`
  (`DEFAULT_USER` / `DEFAULT_PASSWORD`); the script never prints the password.
  Never put secrets, tokens or passwords in the message itself — it is stored
  on the server and shown on the lock screen.
- If `https://ntfy.chiq.me` is unreachable (DNS, tunnel), the script retries
  the local server on `127.0.0.1:5333` and says so on stderr.
- Links must be `http(s)` URLs; the script rejects anything else and more
  than 3 links.
- Exit codes: `64` usage or invalid input, `66` credentials file or values
  missing, `69` curl or python3 missing; otherwise curl's exit status.
