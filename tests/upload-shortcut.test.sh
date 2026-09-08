#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT_DIR/skills/upload/scripts/upload-shortcut.sh"

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

assert_exit 64 "$SCRIPT"
assert_exit 66 "$SCRIPT" "/tmp/upload-skill-missing-file"

tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT
tmp_dir=$(CDPATH= cd -- "$(dirname -- "$tmp_file")" && pwd -P)
tmp_name=$(basename -- "$tmp_file")
canonical_tmp_file="$tmp_dir/$tmp_name"

output=$("$SCRIPT" --dry-run "$tmp_file")
assert_contains "shortcuts run Upload file --input-path $canonical_tmp_file" "$output"
