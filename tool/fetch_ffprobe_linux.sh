#!/usr/bin/env bash
#
# Vendors the ffprobe binary for the Linux build bundle.
#
# ffprobe is the fast path in SubtitleSkipCheck (read a file's subtitle streams
# without spinning up a Player). media_kit ships libmpv with ffmpeg linked as a
# LIBRARY, NOT the ffprobe command-line tool, so a clean release has none. This
# extracts ffprobe from BtbN's self-contained static FFmpeg build and drops it at
# third_party/ffprobe/linux-x64/ffprobe, from where the linux/ CMake install rule
# copies it next to the app executable. SubtitleSkipCheck invokes it by absolute
# path (Linux Process.run doesn't search the executable's own directory).
#
# Source: BtbN/FFmpeg-Builds — the LGPL variant (no GPL-only encoders), the
# cleanest license posture for redistribution. These are big all-codec static
# builds (~100MB); a personal single-machine app can afford it, and ffprobe is an
# optional speed upgrade (the app degrades to the libmpv fallback without it).
#
# NOTE on pinning: BtbN publishes immutable per-build `autobuild-*` release tags
# but prunes old ones over time. If this URL 404s, bump BUILD_TAG/ASSET to a
# current autobuild release (https://github.com/BtbN/FFmpeg-Builds/releases) and
# refresh EXPECTED_SHA256. A missing binary is non-fatal — the CMake rule is
# guarded and the app falls back — so a stale pin degrades gracefully.
#
# third_party/ is gitignored. Idempotent: re-running with the binary present +
# checksum-matching is a no-op. Override the install dir with FFPROBE_VENDOR_DIR.
set -euo pipefail

# --- Pinned build (bump deliberately; update EXPECTED_SHA256 when you do) ---
BUILD_TAG="autobuild-2026-07-08-13-30"
ASSET="ffmpeg-n7.1.5-1-g7d0e842004-linux64-lgpl-7.1.tar.xz"
URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/${BUILD_TAG}/${ASSET}"
EXPECTED_SHA256="34496c6de1ff9fc9251b9466db3247cadf3d74e369e9e7b158d22944a73cd3a1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_ROOT="${FFPROBE_VENDOR_DIR:-$ROOT/third_party/ffprobe}"
DEST_DIR="$VENDOR_ROOT/linux-x64"
DEST="$DEST_DIR/ffprobe"
LICENSE_DEST="$VENDOR_ROOT/LICENSE-ffmpeg.txt"

mkdir -p "$DEST_DIR"

if [[ -f "$DEST" ]] && [[ -f "$LICENSE_DEST" ]]; then
  echo "✓ ffprobe already vendored: $DEST"
  echo "Done."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

archive="$tmp/ffmpeg.tar.xz"
echo "Downloading FFmpeg (LGPL static, linux64) ${BUILD_TAG} ..."
curl -fSL --retry 3 -o "$archive" "$URL"
echo "${EXPECTED_SHA256}  ${archive}" | sha256sum -c -

# Extract just bin/ffprobe and the LICENSE from the single top-level folder.
echo "Extracting ffprobe ..."
tar -xf "$archive" --wildcards -C "$tmp" '*/bin/ffprobe' '*/LICENSE.txt'
found_probe="$(find "$tmp" -type f -name ffprobe -path '*/bin/*' | head -1)"
found_license="$(find "$tmp" -type f -name 'LICENSE.txt' | head -1)"
[[ -n "$found_probe" ]] || { echo "ffprobe not found in archive" >&2; exit 1; }

install -m 0755 "$found_probe" "$DEST"
echo "✓ Vendored: $DEST"
if [[ -n "$found_license" ]]; then
  cp "$found_license" "$LICENSE_DEST"
  echo "✓ License: $LICENSE_DEST"
fi

echo "Done."
