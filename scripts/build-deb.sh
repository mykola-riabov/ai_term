#!/usr/bin/env bash
# Build a .deb package for Aiterm (install on Debian/Ubuntu/Kali).
# Bundles LDC + GtkD/VteD D bindings so ABI matches the built binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$(cd "$ROOT/.." && pwd)"
PKG_NAME="aiterm"
VERSION="0.1.0"
REVISION="5"
ARCH="$(dpkg --print-architecture)"
DEB_FILE="$OUT_DIR/${PKG_NAME}_${VERSION}-${REVISION}_${ARCH}.deb"
STAGING="$ROOT/deb-staging"
BUILD="$ROOT/build"
LIBDIR="$STAGING/usr/lib/aiterm"
MULTIARCH="/lib/x86_64-linux-gnu"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing: $1" >&2
    exit 1
  }
}

bundle_versioned_lib() {
  local base="$1"
  local resolved
  resolved="$(readlink -f "${MULTIARCH}/${base}.so.0")"
  if [[ ! -f "$resolved" ]]; then
    echo "Missing library: ${MULTIARCH}/${base}.so.0" >&2
    exit 1
  fi
  local verfile
  verfile="$(basename "$resolved")"
  cp "$resolved" "$LIBDIR/"
  ln -sf "$verfile" "$LIBDIR/${base}.so.0"
  ln -sf "${base}.so.0" "$LIBDIR/${base}.so"
  echo "  bundled ${base} -> ${verfile}"
}

bundle_private_libs() {
  mkdir -p "$LIBDIR"
  for base in libphobos2-ldc-shared libdruntime-ldc-shared; do
    local real="${MULTIARCH}/${base}.so.2.0.98"
    if [[ ! -f "$real" ]]; then
      echo "Missing LDC library: $real" >&2
      exit 1
    fi
    cp "$real" "$LIBDIR/"
    ln -sf "${base}.so.2.0.98" "$LIBDIR/${base}.so.98"
    ln -sf "${base}.so.98" "$LIBDIR/${base}.so"
    echo "  bundled ${base}"
  done
  bundle_versioned_lib libgtkd-3
  bundle_versioned_lib libvted-3
}

install_wrapper() {
  local bin="$STAGING/usr/bin/aiterm"
  local real="$LIBDIR/aiterm.bin"
  if [[ ! -f "$bin" ]]; then
    echo "Missing installed binary: $bin" >&2
    exit 1
  fi
  mv "$bin" "$real"
  chmod 755 "$real"
  cat > "$bin" <<'EOF'
#!/bin/sh
export LD_LIBRARY_PATH="/usr/lib/aiterm${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec /usr/lib/aiterm/aiterm.bin "$@"
EOF
  chmod 755 "$bin"
}

need meson
need ninja
need ldc2
need dpkg-deb
need glib-compile-schemas
need gtk-update-icon-cache

cd "$ROOT"
rm -rf "$STAGING"
mkdir -p "$STAGING/DEBIAN"

echo "==> Meson build"
export PATH="/usr/bin:/bin:${HOME}/.local/bin:${PATH}"
meson setup "$BUILD" --prefix=/usr --buildtype=release -Dstrip=true 2>/dev/null || \
  meson setup "$BUILD" --prefix=/usr --buildtype=release -Dstrip=true --reconfigure
ninja -C "$BUILD"

echo "==> Install into staging"
DESTDIR="$STAGING" ninja -C "$BUILD" install

echo "==> Bundle private libraries + launcher"
bundle_private_libs
install_wrapper

echo "==> DEBIAN metadata"
cat > "$STAGING/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}-${REVISION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: Mykola Riabov <mykola.riabov@gmail.com>
Depends: libgtk-3-0t64 | libgtk-3-0, libvte-2.91-0, libglib2.0-0t64 | libglib2.0-0, libcairo2, libpango-1.0-0, libx11-6, libsecret-1-0, curl
Description: Aiterm — tiling terminal with AI and quick commands
 GTK+ 3 tiling terminal (modified Tilix) with nested quick bar menus,
 SSH shortcuts, command snippets, and OpenAI-compatible AI chat (curl).
EOF

cat > "$STAGING/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
case "$1" in
  configure)
    if command -v glib-compile-schemas >/dev/null; then
      glib-compile-schemas /usr/share/glib-2.0/schemas
    fi
    if command -v gtk-update-icon-cache >/dev/null; then
      gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
    fi
    if command -v update-desktop-database >/dev/null; then
      update-desktop-database -q /usr/share/applications 2>/dev/null || true
    fi
    ;;
esac
exit 0
EOF
chmod 755 "$STAGING/DEBIAN/postinst"

cat > "$STAGING/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
exit 0
EOF
chmod 755 "$STAGING/DEBIAN/prerm"

echo "==> Build .deb"
dpkg-deb --root-owner-group --build "$STAGING" "$DEB_FILE"
rm -rf "$STAGING"

rm -f "$OUT_DIR/${PKG_NAME}_${VERSION}"-[1234]_${ARCH}.deb

echo ""
echo "OK: $DEB_FILE"
echo "Install on target host:"
echo "  sudo apt install ./${PKG_NAME}_${VERSION}-${REVISION}_${ARCH}.deb"
