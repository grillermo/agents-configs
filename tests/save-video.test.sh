#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT_DIR/skills/save_video/scripts/save-video.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

assert_exit() {
  expected_status=$1
  shift

  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e

  if [ "$status" -ne "$expected_status" ]; then
    printf 'expected exit %s, got %s\noutput:\n%s\n' "$expected_status" "$status" "$output" >&2
    exit 1
  fi
}

assert_contains() {
  needle=$1
  haystack=$2

  case "$haystack" in
    *"$needle"*) ;;
    *)
      printf 'expected output to contain %s\noutput:\n%s\n' "$needle" "$haystack" >&2
      exit 1
      ;;
  esac
}

# A stand-in curl that answers /api/groups and fails anything else, so no
# test reaches a real server.
mkdir -p "$work/bin"
cat >"$work/bin/curl" <<'CURL'
#!/bin/sh
cat >/dev/null
case "$*" in
  */api/groups*) printf '{"groups":[{"id":1,"name":"children","label":"Videos musicales"},{"id":9,"name":"inbox","label":"inbox"}]}' ;;
  *) exit 7 ;;
esac
CURL
chmod +x "$work/bin/curl"
printf 'UPLOAD_TOKEN=secret\n' >"$work/.env"

run() {
  PATH="$work/bin:$PATH" PATATATUBE_ENV_FILE="$work/.env" "$SCRIPT" "$@"
}

assert_exit 64 run
assert_exit 66 run "$work/missing.mp4"
assert_exit 66 env PATATATUBE_ENV_FILE="$work/none" "$SCRIPT" https://youtu.be/x

output=$(run --dry-run https://youtu.be/x)
assert_contains '/upload {"url": "https://youtu.be/x"}' "$output"

# Groups match name or label, case-insensitively.
output=$(run --dry-run -g "videos MUSICALES" https://youtu.be/x)
assert_contains '"group_id": 1' "$output"

assert_exit 65 run --dry-run -g nope https://youtu.be/x
assert_contains "children (Videos musicales)" "$output"

# A file with no group goes to the inbox, which /upload/file requires.
: >"$work/clip.mp4"
output=$(run --dry-run "$work/clip.mp4")
assert_contains "/upload/file file=$work/clip.mp4 group_id=9" "$output"

# The token never reaches argv or output.
case "$output" in *secret*) printf 'token leaked into output\n' >&2; exit 1 ;; esac

printf 'ok\n'
