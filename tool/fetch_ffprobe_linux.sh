#!/usr/bin/env bash
#
# Vendors the ffprobe + ffmpeg binaries for the Linux build bundle.
#
# ffprobe is the fast path in SubtitleSkipCheck (read a file's subtitle streams
# without spinning up a Player). media_kit ships libmpv with ffmpeg linked as a
# LIBRARY, NOT the ffprobe command-line tool, so a clean release has none. This
# extracts ffprobe AND ffmpeg from BtbN's self-contained static FFmpeg build into
# third_party/ffprobe/linux-x64/, from where the linux/ CMake install rule copies
# them next to the app executable. Callers invoke them by absolute path (Linux
# Process.run doesn't search the executable's own directory).
#
# ffmpeg rides along because the archive already contains it -- the download and
# checksum are shared, so the only cost is bundle size. It backs the downscale of
# a 4K file a weak box can't play smoothly (see TASKS.md). The vendor directory
# keeps the `ffprobe` name for continuity with existing references.
#
# Source: BtbN/FFmpeg-Builds — the LGPL variant (no GPL-only encoders), the
# cleanest license posture for redistribution. These are big all-codec static
# builds (~100MB); a personal single-machine app can afford it, and ffprobe is an
# optional speed upgrade (the app degrades to the libmpv fallback without it).
#
# NOTE on pinning: this used to pin an immutable `autobuild-<date>` tag, but BtbN
# PRUNES those after a few weeks and the build then dies on a 404. It now uses the
# `latest` rolling release, whose asset names are stable and never 404.
#
# The trade: `latest` moves, so a fixed checksum can't be kept in step (BtbN
# rebuilds daily). EXPECTED_SHA256 is therefore OPTIONAL — leave it empty and the
# script reports the hash it downloaded without verifying; set it to pin a known
# build and the script fails on any mismatch.
#
# third_party/ is gitignored. Idempotent: re-running with the binary present +
# checksum-matching is a no-op. Override the install dir with FFPROBE_VENDOR_DIR.
set -euo pipefail

# --- Source build. EXPECTED_SHA256 is optional: empty = report only (see above) ---
BUILD_TAG="latest"
ASSET="ffmpeg-master-latest-linux64-lgpl.tar.xz"
URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/${BUILD_TAG}/${ASSET}"
EXPECTED_SHA256=""

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_ROOT="${FFPROBE_VENDOR_DIR:-$ROOT/third_party/ffprobe}"
DEST_DIR="$VENDOR_ROOT/linux-x64"
DEST="$DEST_DIR/ffprobe"
DEST_FFMPEG="$DEST_DIR/ffmpeg"
LICENSE_DEST="$VENDOR_ROOT/LICENSE-ffmpeg.txt"

mkdir -p "$DEST_DIR"

if [[ -f "$DEST" ]] && [[ -f "$DEST_FFMPEG" ]] && [[ -f "$LICENSE_DEST" ]]; then
  echo "✓ ffprobe + ffmpeg already vendored: $DEST_DIR"
  echo "Done."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

archive="$tmp/ffmpeg.tar.xz"
echo "Downloading FFmpeg (LGPL static, linux64) ${BUILD_TAG} ..."
curl -fSL --retry 3 -o "$archive" "$URL"
actual_sha="$(sha256sum "$archive" | cut -d' ' -f1)"
if [[ -z "$EXPECTED_SHA256" ]]; then
  echo "NOTE downloaded SHA-256: $actual_sha (unpinned; set EXPECTED_SHA256 to enforce)"
elif [[ "$actual_sha" != "$EXPECTED_SHA256" ]]; then
  echo "SHA-256 mismatch: expected $EXPECTED_SHA256 but got $actual_sha" >&2
  exit 1
else
  echo "✓ SHA-256 verified against the pin"
fi

# Extract just bin/ffprobe and the LICENSE from the single top-level folder.
echo "Extracting ffprobe + ffmpeg ..."
tar -xf "$archive" --wildcards -C "$tmp" '*/bin/ffprobe' '*/bin/ffmpeg' '*/LICENSE.txt'
found_probe="$(find "$tmp" -type f -name ffprobe -path '*/bin/*' | head -1)"
found_ffmpeg="$(find "$tmp" -type f -name ffmpeg -path '*/bin/*' | head -1)"
found_license="$(find "$tmp" -type f -name 'LICENSE.txt' | head -1)"
[[ -n "$found_probe" ]] || { echo "ffprobe not found in archive" >&2; exit 1; }
[[ -n "$found_ffmpeg" ]] || { echo "ffmpeg not found in archive" >&2; exit 1; }

install -m 0755 "$found_probe" "$DEST"
install -m 0755 "$found_ffmpeg" "$DEST_FFMPEG"
echo "✓ Vendored: $DEST"
echo "✓ Vendored: $DEST_FFMPEG"
if [[ -n "$found_license" ]]; then
  cp "$found_license" "$LICENSE_DEST"
  echo "✓ License: $LICENSE_DEST"
fi

echo "Done."
