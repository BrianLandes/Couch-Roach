#!/usr/bin/env bash
#
# Vendors the qBittorrent-nox daemon binary for the Linux build bundle.
#
# Source: userdocs/qbittorrent-nox-static — a *fully static* qbittorrent-nox
# (no Qt/shared-lib deps), which is exactly what a portable bundle needs. The
# binary is dropped at third_party/qbittorrent/linux-x64/qbittorrent-nox, from
# where the linux/ CMake install rule copies it next to the app executable and
# QbittorrentProcess resolves it at runtime.
#
# third_party/ is gitignored — run this before packaging a Linux build (and it
# is the step a future Linux CI job would invoke, mirroring the Windows one).
#
# Idempotent: re-running with the binary already present + checksum-matching is
# a no-op. Override the install dir with QBITTORRENT_VENDOR_DIR if needed.
set -euo pipefail

# --- Pinned version (bump deliberately; update EXPECTED_SHA256 when you do) ---
VERSION="5.2.2"
LIBTORRENT="v2.0.13"                       # libtorrent baked into this static tag
STATIC_TAG="release-${VERSION}_${LIBTORRENT}"
URL="https://github.com/userdocs/qbittorrent-nox-static/releases/download/${STATIC_TAG}/x86_64-qbittorrent-nox"
EXPECTED_SHA256="0d219aa16905d75161e5eaee82288358c5d63947ffd48623997fc5dd481664e3"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_ROOT="${QBITTORRENT_VENDOR_DIR:-$ROOT/third_party/qbittorrent}"
DEST_DIR="$VENDOR_ROOT/linux-x64"
DEST="$DEST_DIR/qbittorrent-nox"
LICENSE_DEST="$VENDOR_ROOT/LICENSE-qbittorrent.txt"

mkdir -p "$DEST_DIR"

if [[ -f "$DEST" ]] && echo "${EXPECTED_SHA256}  ${DEST}" | sha256sum -c --status 2>/dev/null; then
  echo "✓ qbittorrent-nox already vendored and verified: $DEST"
else
  echo "Downloading qbittorrent-nox ${VERSION} (static, x86_64) ..."
  curl -fSL --retry 3 -o "$DEST" "$URL"
  echo "${EXPECTED_SHA256}  ${DEST}" | sha256sum -c -
  chmod +x "$DEST"
  echo "✓ Vendored: $DEST"
fi

# GPL license text (COPYING) — required alongside the redistributed binary
# (source is GPLv2+, the binary distribution is GPLv3+; COPYING covers both).
if [[ ! -f "$LICENSE_DEST" ]]; then
  curl -fSL --retry 3 -o "$LICENSE_DEST" \
    "https://raw.githubusercontent.com/qbittorrent/qBittorrent/release-${VERSION}/COPYING"
  echo "✓ License: $LICENSE_DEST"
fi

echo "Done."
