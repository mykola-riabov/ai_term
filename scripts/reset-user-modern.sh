#!/usr/bin/env bash
# Remove user modern.json so Aiterm recreates factory defaults on next start.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}/aiterm/modern.json"
if [[ -f "$CFG" ]]; then
  rm -f "$CFG"
  echo "Removed: $CFG"
else
  echo "No file: $CFG"
fi
echo "Start Aiterm to create factory defaults (quick bar buttons off)."
