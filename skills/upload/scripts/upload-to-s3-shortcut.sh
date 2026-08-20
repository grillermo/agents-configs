#!/bin/sh
set -eu

SHORTCUT_NAME="Upload to S3"
DRY_RUN=0

usage() {
  printf 'usage: %s [--dry-run] <file>\n' "$(basename "$0")" >&2
}

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
  shift
fi

if [ "$#" -ne 1 ]; then
  usage
  exit 64
fi

input_path=$1

if [ ! -f "$input_path" ]; then
  printf 'upload: file not found: %s\n' "$input_path" >&2
  exit 66
fi

input_dir=$(CDPATH= cd -- "$(dirname -- "$input_path")" && pwd -P)
input_file=$(basename -- "$input_path")
absolute_path="$input_dir/$input_file"

if [ "$DRY_RUN" -eq 1 ]; then
  printf 'shortcuts run %s --input-path %s\n' "$SHORTCUT_NAME" "$absolute_path"
  exit 0
fi

if ! command -v shortcuts >/dev/null 2>&1; then
  printf 'upload: macOS shortcuts command not found\n' >&2
  exit 69
fi

shortcuts run "$SHORTCUT_NAME" --input-path "$absolute_path"
