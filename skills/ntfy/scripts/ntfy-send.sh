#!/bin/sh
# Send a push notification through the self-hosted ntfy server.
# Publishes JSON to the server root (topic, title, priority, tags, click, view
# actions for links). Credentials are read from the ntfyllermo .env
# (DEFAULT_USER / DEFAULT_PASSWORD) and handed to curl through a private config
# file, so the password never shows up in `ps` or in output.
set -eu

NTFY_URL=${NTFY_URL:-https://ntfy.chiq.me}
NTFY_LOCAL_URL=${NTFY_LOCAL_URL:-http://127.0.0.1:5333}
NTFY_ENV_FILE=${NTFY_ENV_FILE:-/Users/grillermo/c/ntfyllermo/.env}
TOPIC=claude-alerts
TITLE=
PRIORITY=
TAGS=
CLICK=
DRY_RUN=0
# One link per line as "label<TAB>url"; an empty label is filled in later.
LINKS=
TAB=$(printf '\t')
NL='
'

usage() {
  printf 'usage: %s [--dry-run] [-c topic] [-t title] [-p priority] [-T tags] [-u click-url] [-l url [-L label]]... <message...>\n' "$(basename "$0")" >&2
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --dry-run) DRY_RUN=1; shift ;;
    -c|--topic) TOPIC=${2:?}; shift 2 ;;
    -t|--title) TITLE=${2:?}; shift 2 ;;
    -p|--priority) PRIORITY=${2:?}; shift 2 ;;
    -T|--tags) TAGS=${2:?}; shift 2 ;;
    -u|--click) CLICK=${2:?}; shift 2 ;;
    -l|--link) LINKS="$LINKS$TAB${2:?}$NL"; shift 2 ;;
    -L|--label)
      # Labels the most recent -l, so it must come after one.
      if [ -z "$LINKS" ]; then
        printf 'ntfy: -L/--label must follow a -l/--link\n' >&2
        exit 64
      fi
      last=$(printf '%s' "$LINKS" | tail -n 1)
      LINKS="$(printf '%s' "$LINKS" | sed '$d')"
      [ -n "$LINKS" ] && LINKS="$LINKS$NL"
      LINKS="$LINKS${2:?}$TAB${last#*"$TAB"}$NL"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) usage; exit 64 ;;
    *) break ;;
  esac
done

if [ "$#" -eq 0 ]; then
  usage
  exit 64
fi
MESSAGE=$*

if [ ! -f "$NTFY_ENV_FILE" ]; then
  printf 'ntfy: credentials file not found: %s\n' "$NTFY_ENV_FILE" >&2
  exit 66
fi
env_value() {
  sed -n "s/^$1=//p" "$NTFY_ENV_FILE" | tail -n 1
}
NTFY_USER=$(env_value DEFAULT_USER)
NTFY_PASSWORD=$(env_value DEFAULT_PASSWORD)
if [ -z "$NTFY_USER" ] || [ -z "$NTFY_PASSWORD" ]; then
  printf 'ntfy: DEFAULT_USER / DEFAULT_PASSWORD missing in %s\n' "$NTFY_ENV_FILE" >&2
  exit 66
fi

for tool in curl python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'ntfy: %s not found\n' "$tool" >&2
    exit 69
  fi
done

# Build the JSON body with a real encoder: messages, labels and URLs can hold
# quotes, backslashes, newlines or unicode that hand-built JSON would break on.
build_json() {
  NTFY_J_TOPIC=$TOPIC NTFY_J_MESSAGE=$MESSAGE NTFY_J_TITLE=$TITLE \
  NTFY_J_PRIORITY=$PRIORITY NTFY_J_TAGS=$TAGS NTFY_J_CLICK=$CLICK \
  NTFY_J_LINKS=$LINKS python3 - <<'PY'
import json, os, sys
from urllib.parse import urlparse

env = os.environ.get
body = {"topic": env("NTFY_J_TOPIC"), "message": env("NTFY_J_MESSAGE")}

if env("NTFY_J_TITLE"):
    body["title"] = env("NTFY_J_TITLE")

priority = env("NTFY_J_PRIORITY", "").strip().lower()
if priority:
    names = {"min": 1, "low": 2, "default": 3, "high": 4, "max": 5, "urgent": 5}
    value = names.get(priority, int(priority) if priority.isdigit() else None)
    if value not in (1, 2, 3, 4, 5):
        sys.exit(f"ntfy: invalid priority {priority!r} (use 1-5 or min/low/default/high/max/urgent)")
    body["priority"] = value

tags = [t.strip() for t in env("NTFY_J_TAGS", "").split(",") if t.strip()]
if tags:
    body["tags"] = tags

actions = []
for line in env("NTFY_J_LINKS", "").splitlines():
    if not line:
        continue
    label, _, url = line.partition("\t")
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        sys.exit(f"ntfy: link must be an http(s) URL: {url!r}")
    actions.append({"action": "view", "label": label or f"Open {parsed.netloc}", "url": url})
if len(actions) > 3:
    sys.exit("ntfy: at most 3 links (ntfy shows up to 3 action buttons)")
if actions:
    body["actions"] = actions

# Tapping the notification itself opens the first link unless -u says otherwise;
# some clients (iOS web push) may not show action buttons at all.
click = env("NTFY_J_CLICK") or (actions[0]["url"] if actions else "")
if click:
    body["click"] = click

json.dump(body, sys.stdout, ensure_ascii=False)
PY
}

tmp_body=$(mktemp)
tmp_cfg=$(mktemp)
trap 'rm -f "$tmp_body" "$tmp_cfg"' EXIT INT TERM
chmod 600 "$tmp_cfg"

if ! build_json > "$tmp_body"; then
  exit 64
fi

if [ "$DRY_RUN" -eq 1 ]; then
  printf 'POST %s/ as %s\n' "$NTFY_URL" "$NTFY_USER"
  python3 -m json.tool --no-ensure-ascii "$tmp_body"
  exit 0
fi

# Backslashes and double quotes are escaped for curl's quoted-string syntax.
curl_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
{
  printf 'user = "%s:%s"\n' "$(curl_quote "$NTFY_USER")" "$(curl_quote "$NTFY_PASSWORD")"
  printf 'header = "Content-Type: application/json"\n'
} > "$tmp_cfg"

send_to() {
  curl -sS --fail-with-body -m 20 -K "$tmp_cfg" --data-binary "@$tmp_body" "$1/"
}

if response=$(send_to "$NTFY_URL" 2>&1); then
  printf '%s\n' "$response"
  exit 0
else
  status=$?
fi

# 6 = DNS, 7 = connect, 28 = timeout, 35 = TLS: the tunnel/DNS path is down,
# but the server itself may be fine on this Mac. Anything else (401/403/400) is real.
case $status in
  6|7|28|35)
    printf 'ntfy: %s unreachable (curl exit %s), retrying %s\n' "$NTFY_URL" "$status" "$NTFY_LOCAL_URL" >&2
    send_to "$NTFY_LOCAL_URL"
    ;;
  *)
    printf 'ntfy: publish failed (curl exit %s): %s\n' "$status" "$response" >&2
    exit "$status"
    ;;
esac
