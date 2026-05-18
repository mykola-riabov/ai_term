#!/usr/bin/env bash
# Remove build trees and staged .deb artifacts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf build cibuild
rm -rf example/aiterm/build example/aiterm/deb-staging 2>/dev/null || true
rm -f example/aiterm_*.deb example/*.deb 2>/dev/null || true

echo "OK: cleaned build and deb artifacts"
