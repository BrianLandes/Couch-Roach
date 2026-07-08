#!/usr/bin/env bash
#
# Vendors the Jackett indexer sidecar for the Linux build bundle.
#
# Jackett is the content-agnostic Torznab proxy the app runs as an invisible
# localhost child (DECISIONS §D, same model as qBittorrent-nox). It's C#/.NET 9;
# this fetches the **self-contained** build (bundles the .NET runtime — the TV PC
# needs no .NET installed) and drops the whole tree at third_party/jackett/
# linux-x64/, from where the linux/ CMake rule bundles it as <bundle>/jackett/.
# JackettProcess launches <bundle>/jackett/jackett at runtime.
#
# GOVERNANCE (CLAUDE.md invariant / DECISIONS §D): this ships stock, unmodified
# Jackett. No indexer is enabled by default — the user configures their own
# legal/public-domain indexers in the local Jackett UI; indexer selection (and
# its legal responsibility) lives in the user's instance, not this repo.
#
# third_party/ is gitignored — run this before packaging a Linux build. Idempotent:
# a no-op once vendored. Override the install dir with JACKETT_VENDOR_DIR.
set -euo pipefail

# --- Pinned version (bump deliberately; update EXPECTED_SHA256 when you do) ---
VERSION="0.24.2187"
ASSET="Jackett.Binaries.LinuxAMDx64.tar.gz"
URL="https://github.com/Jackett/Jackett/releases/download/v${VERSION}/${ASSET}"
EXPECTED_SHA256="980d6501973e077a5cdc329bdce345c112175bae6f041ad6ce5473ad137d09eb"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_ROOT="${JACKETT_VENDOR_DIR:-$ROOT/third_party/jackett}"
DEST_DIR="$VENDOR_ROOT/linux-x64"
LAUNCHER="$DEST_DIR/jackett"
LICENSE_DEST="$VENDOR_ROOT/LICENSE-jackett.txt"

if [[ -x "$LAUNCHER" ]] && [[ -f "$LICENSE_DEST" ]]; then
  echo "✓ Jackett already vendored: $DEST_DIR"
  echo "Done."
  exit 0
fi

mkdir -p "$DEST_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

archive="$tmp/jackett.tar.gz"
echo "Downloading Jackett ${VERSION} (self-contained, linux-x64) ..."
curl -fSL --retry 3 -o "$archive" "$URL"
echo "${EXPECTED_SHA256}  ${archive}" | sha256sum -c -

# The archive is a single top-level Jackett/ folder — strip it so the launcher
# lands directly at $DEST_DIR/jackett.
echo "Extracting ..."
tar -xzf "$archive" --strip-components=1 -C "$DEST_DIR"
[[ -f "$LAUNCHER" ]] || { echo "jackett launcher not found after extract" >&2; exit 1; }
chmod +x "$LAUNCHER"
echo "✓ Vendored: $DEST_DIR"

# Jackett is GPLv2 — vendor its license alongside the redistributed binaries.
# Best-effort: a moved LICENSE path shouldn't block packaging.
if [[ ! -f "$LICENSE_DEST" ]]; then
  curl -fSL --retry 3 -o "$LICENSE_DEST" \
    "https://raw.githubusercontent.com/Jackett/Jackett/v${VERSION}/LICENSE" \
    || echo "! Could not fetch Jackett LICENSE (non-fatal)"
fi

echo "Done."
