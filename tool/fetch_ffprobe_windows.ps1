<#
.SYNOPSIS
  Vendors the ffprobe binary for the Windows build bundle.

.DESCRIPTION
  ffprobe is the fast path in SubtitleSkipCheck (read a file's subtitle streams
  without spinning up a Player). media_kit ships libmpv with ffmpeg linked as a
  LIBRARY, NOT the ffprobe command-line tool, so a clean release has none. This
  downloads BtbN's self-contained static FFmpeg build, verifies its SHA-256, and
  extracts just ffprobe.exe to third_party/ffprobe/win-x64/ffprobe.exe. The
  windows/ CMake install rule copies it next to the app exe; SubtitleSkipCheck
  invokes it by absolute path.

  Source: BtbN/FFmpeg-Builds — the LGPL variant (no GPL-only encoders), the
  cleanest license posture for redistribution. These are big all-codec static
  builds (~100MB); a personal single-machine app can afford it, and ffprobe is an
  optional speed upgrade (the app degrades to the libmpv fallback without it).

  NOTE on pinning: BtbN publishes immutable per-build `autobuild-*` release tags
  but prunes old ones over time. If this URL 404s, bump $BuildTag/$Asset to a
  current autobuild release (https://github.com/BtbN/FFmpeg-Builds/releases) and
  refresh $ExpectedSha256. A missing binary is non-fatal — the CMake rule is
  guarded and the app falls back — so a stale pin degrades gracefully.

  third_party/ is gitignored. Idempotent: a no-op if the exe is already present.
  The GitHub Actions Windows build runs this before `flutter build windows`.
#>
$ErrorActionPreference = 'Stop'

# --- Pinned build (bump deliberately; update $ExpectedSha256 when you do) ---
$BuildTag       = 'autobuild-2026-07-08-13-30'
$Asset          = 'ffmpeg-n7.1.5-1-g7d0e842004-win64-lgpl-7.1.zip'
$Url            = "https://github.com/BtbN/FFmpeg-Builds/releases/download/$BuildTag/$Asset"
$ExpectedSha256 = 'ADF7C790DDFF381341CF47186D7B94663F03F5499E93E048F7E98A98BBCAC9D7'

$Root        = Split-Path -Parent $PSScriptRoot
$VendorRoot  = Join-Path $Root 'third_party\ffprobe'
$DestDir     = Join-Path $VendorRoot 'win-x64'
$Dest        = Join-Path $DestDir 'ffprobe.exe'
$LicenseDest = Join-Path $VendorRoot 'LICENSE-ffmpeg.txt'

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

if ((Test-Path $Dest) -and (Test-Path $LicenseDest)) {
  Write-Host "OK ffprobe.exe already vendored: $Dest"
  exit 0
}

$tmp     = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP ("ffprobe_" + [guid]::NewGuid()))
$archive = Join-Path $tmp 'ffmpeg.zip'
try {
  Write-Host "Downloading FFmpeg (LGPL static, win64) $BuildTag ..."
  Invoke-WebRequest -Uri $Url -OutFile $archive

  $hash = (Get-FileHash -Algorithm SHA256 $archive).Hash
  if ($hash -ne $ExpectedSha256) {
    throw "SHA-256 mismatch: expected $ExpectedSha256 but got $hash"
  }

  Write-Host "Extracting ffprobe.exe ..."
  Expand-Archive -Path $archive -DestinationPath $tmp -Force
  $probe   = Get-ChildItem -Path $tmp -Recurse -Filter 'ffprobe.exe' | Select-Object -First 1
  $license = Get-ChildItem -Path $tmp -Recurse -Filter 'LICENSE.txt'  | Select-Object -First 1
  if (-not $probe) { throw "ffprobe.exe not found in archive" }

  Copy-Item -Path $probe.FullName -Destination $Dest -Force
  Write-Host "OK Vendored: $Dest"
  if ($license) {
    Copy-Item -Path $license.FullName -Destination $LicenseDest -Force
    Write-Host "OK License: $LicenseDest"
  }
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "Done."
