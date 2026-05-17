#!/usr/bin/env bash
# Build Aiterm (system apt deps if available, else local sysroot).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if command -v ldc2 >/dev/null && pkg-config --exists gtkd-3 2>/dev/null; then
  export PATH="/usr/bin:/bin:${HOME}/.local/bin:${PATH}"
else
  BUILD_ROOT="${AITERM_BUILD:-$HOME/.local/aiterm-build}"
  SYSROOT="$BUILD_ROOT/sysroot"
  if [[ ! -f "$HOME/dlang/ldc-1.42.0/bin/ldc2" ]]; then
    echo "Install deps: sudo apt install ldc meson ninja-build libgtkd-3-dev libvted-3-dev ..."
    echo "Or LDC: curl -fsSL https://dlang.org/install.sh | bash -s ldc"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$HOME/dlang/ldc-1.42.0/activate"
  export PATH="$HOME/.local/bin:${HOME}/dlang/ldc-1.42.0/bin:/usr/bin:/bin"
  export PKG_CONFIG_PATH="$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig:$SYSROOT/usr/share/pkgconfig"
  export LIBRARY_PATH="$SYSROOT/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu"
  export LD_LIBRARY_PATH="$SYSROOT/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu"
fi

cd "$ROOT"
meson setup build --prefix="${PREFIX:-$HOME/.local}" --reconfigure 2>/dev/null || \
  meson setup build --prefix="${PREFIX:-$HOME/.local}"
ninja -C build aiterm
echo "OK: $ROOT/build/aiterm"
