#!/bin/sh
# Save a video to PatataTube from a URL (Twitter/X, YouTube, a YouTube
# playlist) or a local file, optionally into a named group.
#
# A URL goes to POST /upload as JSON, a file to POST /upload/file as multipart.
# A group is named by its `name` or `label` (case-insensitive) and resolved to
# an id through GET /api/groups. The token comes from the patatatube .env
# (UPLOAD_TOKEN) and reaches curl through a config on stdin, so it never shows
# up in `ps` or in output.
#
# Without PATATATUBE_URL the server is picked automatically: the first of
# LOCAL_URLS that answers within a second, else REMOTE_URL. A private/loopback
# host talks to the server directly; any other host (videos.chiq.me) goes
# through Cloudflare, which caps the request body, so files over
# REMOTE_MAX_BYTES are refused before uploading.
set -eu

PATATATUBE_URL=${PATATATUBE_URL:-}
LOCAL_URLS=${PATATATUBE_LOCAL_URLS:-"http://127.0.0.1:3050 http://192.168.1.1:3050"}
REMOTE_URL=${PATATATUBE_REMOTE_URL:-https://videos.chiq.me}
PATATATUBE_ENV_FILE=${PATATATUBE_ENV_FILE:-/Users/grillermo/c/patatatube/.env}
REMOTE_MAX_BYTES=$((25 * 1000 * 1000))
GROUP=
DRY_RUN=0

usage() {
  printf 'usage: %s [--dry-run] [-g group] <url-or-file>\n' "$(basename "$0")" >&2
}

die() {
  status=$1
  shift
  printf 'save_video: %s\n' "$*" >&2
  exit "$status"
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --dry-run) DRY_RUN=1; shift ;;
    -g|--group)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      GROUP=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) usage; exit 64 ;;
    *) break ;;
  esac
done

[ "$#" -eq 1 ] || { usage; exit 64; }
TARGET=$1

command -v curl >/dev/null 2>&1 || die 69 "curl is not installed"
command -v python3 >/dev/null 2>&1 || die 69 "python3 is not installed"

case $TARGET in
  http://*|https://*) KIND=url ;;
  *)
    # A file:// URL or ~ that the shell didn't expand still means a local file.
    TARGET=${TARGET#file://}
    case $TARGET in "~/"*) TARGET="$HOME/${TARGET#\~/}" ;; esac
    [ -f "$TARGET" ] || die 66 "not a URL and not a file: $TARGET"
    KIND=file
    ;;
esac

if [ -z "$PATATATUBE_URL" ]; then
  for url in $LOCAL_URLS; do
    # Any HTTP answer counts; curl prints 000 when nothing is listening.
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 -m 2 "$url/" || true)
    if [ "$code" != 000 ]; then
      PATATATUBE_URL=$url
      break
    fi
  done
  PATATATUBE_URL=${PATATATUBE_URL:-$REMOTE_URL}
  printf 'save_video: using %s\n' "$PATATATUBE_URL" >&2
fi

# Host of PATATATUBE_URL: drop scheme, path, userinfo and port.
host=${PATATATUBE_URL#*://}
host=${host%%/*}
host=${host##*@}
host=${host%:*}
case $host in
  localhost|127.*|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|*.local|*.lan) REMOTE=0 ;;
  *) REMOTE=1 ;;
esac

if [ "$KIND" = file ] && [ "$REMOTE" -eq 1 ]; then
  size=$(wc -c < "$TARGET" | tr -d ' ')
  [ "$size" -le "$REMOTE_MAX_BYTES" ] \
    || die 73 "$TARGET is $((size / 1000 / 1000)) MB; $PATATATUBE_URL is remote (Cloudflare) and accepts at most $((REMOTE_MAX_BYTES / 1000 / 1000)) MB, and no local server ($LOCAL_URLS) answered. Upload it from the home network."
fi

[ -f "$PATATATUBE_ENV_FILE" ] || die 66 "env file not found: $PATATATUBE_ENV_FILE"
TOKEN=$(sed -n 's/^[[:space:]]*UPLOAD_TOKEN=//p' "$PATATATUBE_ENV_FILE" | tail -1 | tr -d '"'"'"'\r')
[ -n "$TOKEN" ] || die 66 "UPLOAD_TOKEN is not set in $PATATATUBE_ENV_FILE"

# curl with the Bearer header supplied on stdin rather than argv.
authed_curl() {
  printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -K - "$@"
}

GROUP_ID=
if [ -n "$GROUP" ]; then
  groups_json=$(authed_curl -sS --fail-with-body "$PATATATUBE_URL/api/groups") \
    || die 69 "could not list groups from $PATATATUBE_URL: $groups_json"
  GROUP_ID=$(printf '%s' "$groups_json" | python3 -c '
import json, sys
want = sys.argv[1].strip().casefold()
groups = json.load(sys.stdin)["groups"]
hits = [g for g in groups if want in (g["name"].casefold(), g["label"].casefold())]
if len(hits) == 1:
    print(hits[0]["id"])
    sys.exit(0)
listing = ", ".join("%s (%s)" % (g["name"], g["label"]) for g in groups)
reason = "ambiguous" if hits else "no such"
print("save_video: %s group %r; groups: %s" % (reason, sys.argv[1], listing), file=sys.stderr)
sys.exit(65)
' "$GROUP") || exit 65
fi

if [ "$KIND" = file ] && [ -z "$GROUP_ID" ]; then
  # /upload/file requires a group; /upload falls back to the inbox itself.
  groups_json=$(authed_curl -sS --fail-with-body "$PATATATUBE_URL/api/groups") \
    || die 69 "could not list groups from $PATATATUBE_URL: $groups_json"
  GROUP_ID=$(printf '%s' "$groups_json" | python3 -c '
import json, sys
groups = json.load(sys.stdin)["groups"]
inbox = [g for g in groups if g["name"] == "inbox"] or groups
if not inbox:
    sys.exit("save_video: the server has no groups")
print(inbox[0]["id"])
') || exit 65
fi

if [ "$KIND" = url ]; then
  body=$(python3 -c '
import json, sys
body = {"url": sys.argv[1]}
if sys.argv[2]:
    body["group_id"] = int(sys.argv[2])
print(json.dumps(body))
' "$TARGET" "$GROUP_ID")
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'POST %s/upload %s\n' "$PATATATUBE_URL" "$body"
    exit 0
  fi
  authed_curl -sS --fail-with-body -X POST "$PATATATUBE_URL/upload" \
    -H 'Content-Type: application/json' --data-binary "$body"
else
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'POST %s/upload/file file=%s group_id=%s\n' "$PATATATUBE_URL" "$TARGET" "$GROUP_ID"
    exit 0
  fi
  authed_curl -sS --fail-with-body -X POST "$PATATATUBE_URL/upload/file" \
    -F "file=@$TARGET" -F "group_id=$GROUP_ID"
fi
printf '\n'
