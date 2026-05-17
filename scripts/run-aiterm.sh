#!/usr/bin/env bash
# Run Aiterm from the build tree (no system install required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
BIN="$BUILD/aiterm"
DEVSHARE="$BUILD/devshare"
SCHEMAS="$BUILD/schemas"

if [[ ! -x "$BIN" ]]; then
  echo "Binary not found, building..."
  "$ROOT/scripts/build-aiterm.sh"
fi

mkdir -p "$DEVSHARE/aiterm/resources" "$DEVSHARE/aiterm/schemes" "$SCHEMAS"

cp -f "$BUILD/data/aiterm.gresource" "$DEVSHARE/aiterm/resources/aiterm.gresource"
cp -f "$ROOT/data/schemes/"*.json "$DEVSHARE/aiterm/schemes/"
cp -f "$ROOT/data/gsettings/"*.xml "$SCHEMAS/"
glib-compile-schemas "$SCHEMAS"

export AITERM_DATADIR="$DEVSHARE"
export XDG_DATA_DIRS="$DEVSHARE${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
export GSETTINGS_SCHEMA_DIR="$SCHEMAS"

exec "$BIN" "$@"
