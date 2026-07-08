#!/usr/bin/env bash
#
# Vendors the yt-dlp binary for the Linux build bundle.
#
# media_kit/libmpv resolves YouTube URLs (the inline Trailer feature) through its
# builtin ytdl_hook, which shells out to yt-dlp. A clean release has none, so this
# drops the self-contained standalone build (bundles its own Python — no system
# Python needed) at third_party/yt-dlp/linux-x64/yt-dlp, from where the linux/
# CMake install rule copies it next to the app executable. PlayerScreen points
# libmpv at it by absolute path (mpv's ytdl_hook doesn't search the app dir, and
# on Linux nothing searches the executable's own directory).
#
# third_party/ is gitignored — run this before packaging a Linux build (and it is
# the step a future Linux CI job would invoke, mirroring the Windows one).
#
# Idempotent: re-running with the binary already present + checksum-matching is a
# no-op. Override the install dir with YTDLP_VENDOR_DIR if needed.
#
# yt-dlp is released under The Unlicense (public domain) — permissive, but its
# LICENSE is vendored alongside anyway. YouTube periodically breaks extractors,
# so bump VERSION here to refresh (and update EXPECTED_SHA256 from the release's
# SHA2-256SUMS file).
set -euo pipefail

# --- Pinned version (bump deliberately; update EXPECTED_SHA256 when you do) ---
VERSION="2026.07.04"
URL="https://github.com/yt-dlp/yt-dlp/releases/download/${VERSION}/yt-dlp_linux"
EXPECTED_SHA256="6bbb3d314cde4febe36e5fa1d55462e29c974f63444e707871834f6d8cc210ae"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_ROOT="${YTDLP_VENDOR_DIR:-$ROOT/third_party/yt-dlp}"
DEST_DIR="$VENDOR_ROOT/linux-x64"
DEST="$DEST_DIR/yt-dlp"
LICENSE_DEST="$VENDOR_ROOT/LICENSE-yt-dlp.txt"

mkdir -p "$DEST_DIR"

if [[ -f "$DEST" ]] && echo "${EXPECTED_SHA256}  ${DEST}" | sha256sum -c --status 2>/dev/null; then
  echo "✓ yt-dlp already vendored and verified: $DEST"
else
  echo "Downloading yt-dlp ${VERSION} (standalone, linux) ..."
  curl -fSL --retry 3 -o "$DEST" "$URL"
  echo "${EXPECTED_SHA256}  ${DEST}" | sha256sum -c -
  chmod +x "$DEST"
  echo "✓ Vendored: $DEST"
fi

if [[ ! -f "$LICENSE_DEST" ]]; then
  curl -fSL --retry 3 -o "$LICENSE_DEST" \
    "https://raw.githubusercontent.com/yt-dlp/yt-dlp/${VERSION}/LICENSE"
  echo "✓ License: $LICENSE_DEST"
fi

echo "Done."
