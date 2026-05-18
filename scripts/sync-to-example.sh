#!/usr/bin/env bash
# Copy project sources into example/aiterm for packaging (example/ is gitignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/example/aiterm"

mkdir -p "$DEST"
rsync -a --delete \
  --exclude 'example/' \
  --exclude 'build/' \
  --exclude 'cibuild/' \
  --exclude '.git/' \
  --exclude '.cursor/' \
  --exclude '*.deb' \
  --exclude 'aiterm' \
  "$ROOT/" "$DEST/"

# Always refresh sources (full-tree sync can miss new files in some environments).
rsync -a --delete "$ROOT/source/" "$DEST/source/"
rsync -a --delete "$ROOT/data/" "$DEST/data/"
rsync -a --delete "$ROOT/scripts/" "$DEST/scripts/"
rsync -a "$ROOT/meson.build" "$DEST/"

echo "OK: synced to $DEST"
