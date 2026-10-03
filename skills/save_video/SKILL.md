---
name: save_video
description: Save a video to the user's PatataTube server (their self-hosted "watch later") from a URL — Twitter/X, YouTube, or a YouTube playlist — or from a local video file, optionally into a named group. Use when the user invokes /save_video, or asks to save, upload, add or send a video or link to PatataTube / watch later.
---

# save_video

Uploads a video to PatataTube (`~/c/patatatube`, served by Caddy on `:3050`).
The script picks the server itself: the first local address that answers
(`http://127.0.0.1:3050`, then `http://192.168.1.1:3050`), otherwise the
remote `https://videos.chiq.me`. It prints `save_video: using <url>` to stderr. The server downloads URLs itself, in the background,
and re-encodes everything for iOS, so a successful call means *queued*, not
*ready*.

## Workflow

1. Work out the target and the group:
   - `/save_video <url-or-path> [group]` → the first argument is the target,
     anything after it is the group name.
   - A URL must be `http(s)`. A path must point at an existing local file;
     resolve relative paths against the current directory. If the reference is
     missing or ambiguous, ask instead of guessing.
   - The group is matched case-insensitively against a group's `name` or its
     `label`. With no group, a URL lands in the inbox and a YouTube video is
     auto-classified into a group by the server; a file goes to the inbox.
2. Run the script (absolute path, so it works from any directory):

   ```sh
   sh ~/.claude/skills/save_video/scripts/save-video.sh "https://youtu.be/dQw4w9WgXcQ"
   sh ~/.claude/skills/save_video/scripts/save-video.sh -g children "https://x.com/user/status/123"
   sh ~/.claude/skills/save_video/scripts/save-video.sh -g "Music" ~/Downloads/clip.mov
   ```

   Add `--dry-run` to print the request without sending it (the group is still
   resolved against the server).
3. Report the result briefly:
   - `{"id": N, "status": "queued"}` — queued as video `N`.
   - `{"status": "queued", "playlist": "<list_id>"}` — a YouTube playlist. The
     server creates a **new** group named after the playlist and ignores any
     group you passed; say so if the user named one.
   - On failure, show the error output and exit status instead of claiming it
     was saved.

## Notes

- The token is `UPLOAD_TOKEN` from `/Users/grillermo/c/patatatube/.env`; the
  script never prints it. Override with `PATATATUBE_ENV_FILE`. Force a server
  with `PATATATUBE_URL` (skips detection), or change the candidates with
  `PATATATUBE_LOCAL_URLS` (space-separated) and `PATATATUBE_REMOTE_URL`.
- A YouTube video already downloaded is not fetched again — the server moves
  the existing one into the requested group.
- A failed download deletes its row instead of marking it failed, so the only
  trace is in `~/c/patatatube/log/backend.log`.
- An unknown or ambiguous group exits `65` and lists every group as
  `name (label)` — show that list to the user rather than picking one.
- `PATATATUBE_URL` on a loopback/private host (`127.0.0.1`, `192.168.x.x`,
  `10.x`, `172.16–31.x`, `localhost`, `*.local`, `*.lan`) is treated as local;
  anything else (e.g. `https://videos.chiq.me`) is remote, behind Cloudflare,
  and local files over 25 MB are refused with exit `73`. Tell the user to use
  a local URL for those. URL uploads are unaffected — the server downloads them.
- Exit codes: `64` usage, `65` group not found/ambiguous, `66` file or
  credentials missing, `69` curl/python3 missing or server unreachable,
  `73` file too large for a remote server;
  otherwise curl's exit status (`22` for an HTTP error, body on stderr).
