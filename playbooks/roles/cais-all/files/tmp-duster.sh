#!/usr/bin/env bash
set -euo pipefail

THRESHOLD=90       # percent full at which cleanup starts
BATCH_SIZE=20      # how many oldest entries to consider per pass

get_usage() {
  # Prints integer percent use of the filesystem containing /tmp
  df -P /tmp | awk 'NR==2 {gsub(/%/, "", $5); print $5}'
}

get_oldest_batch() {
  # Oldest top-level entries in /tmp (files or dirs), limited to BATCH_SIZE
  find /tmp -mindepth 1 -maxdepth 1 -xdev \
    -printf '%T@ %p\n' 2>/dev/null \
    | sort -n \
    | head -n "$BATCH_SIZE" \
    | awk '{ $1=""; sub(/^ /, ""); print }'
}

usage=$(get_usage)

while [ "$usage" -gt "$THRESHOLD" ]; do
  victims=$(get_oldest_batch)

  # Nothing left to delete
  [ -z "$victims" ] && break

  # Delete one by one from the current batch
  while IFS= read -r path; do
    [ "$usage" -le "$THRESHOLD" ] && break

    # Safety: never allow these to be removed
    case "$path" in
      /tmp | /tmp/. | /tmp/.. ) continue ;;
    esac

    # Remove file or directory (recursively)
    rm -rf -- "$path"

    # Re-check usage after each deletion
    usage=$(get_usage)
  done <<EOF
$victims
EOF
done