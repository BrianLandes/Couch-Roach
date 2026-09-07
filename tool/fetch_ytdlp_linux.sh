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
# LICENSE is vendored alongside anyway.
#
# NOTE this deliberately tracks the LATEST release rather than a pinned version.
# YouTube breaks extractors constantly and yt-dlp's whole value is keeping up with
# that — a pin guarantees the Trailer feature dies every few weeks, which is what
# happened on 2026.07.04. EXPECTED_SHA256 is therefore optional: empty reports the
# hash without enforcing, a value pins and fails on mismatch.
set -euo pipefail

# --- Latest release. EXPECTED_SHA256 is optional: empty = report only (above) ---
VERSION="latest"
URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"
EXPECTED_SHA256=""

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_ROOT="${YTDLP_VENDOR_DIR:-$ROOT/third_party/yt-dlp}"
DEST_DIR="$VENDOR_ROOT/linux-x64"
DEST="$DEST_DIR/yt-dlp"
LICENSE_DEST="$VENDOR_ROOT/LICENSE-yt-dlp.txt"

mkdir -p "$DEST_DIR"

if [[ -f "$DEST" ]]; then
  echo "✓ yt-dlp already vendored: $DEST"
else
  echo "Downloading yt-dlp ${VERSION} (standalone, linux) ..."
  curl -fSL --retry 3 -o "$DEST" "$URL"
  actual_sha="$(sha256sum "$DEST" | cut -d' ' -f1)"
  if [[ -z "$EXPECTED_SHA256" ]]; then
    echo "NOTE downloaded SHA-256: $actual_sha (unpinned; set EXPECTED_SHA256 to enforce)"
  elif [[ "$actual_sha" != "$EXPECTED_SHA256" ]]; then
    rm -f "$DEST"
    echo "SHA-256 mismatch: expected $EXPECTED_SHA256 but got $actual_sha" >&2
    exit 1
  else
    echo "✓ SHA-256 verified against the pin"
  fi
  chmod +x "$DEST"
  echo "✓ Vendored: $DEST"
fi

if [[ ! -f "$LICENSE_DEST" ]]; then
  curl -fSL --retry 3 -o "$LICENSE_DEST" \
    "https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/LICENSE"
  echo "✓ License: $LICENSE_DEST"
fi

echo "Done."
