#!/usr/bin/env bash
# Sync sources to example/aiterm and build a .deb in example/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/sync-to-example.sh"
"$ROOT/scripts/clean-all.sh"
chmod +x "$ROOT/example/aiterm/scripts/build-deb.sh"
(cd "$ROOT/example/aiterm" && ./scripts/build-deb.sh)
