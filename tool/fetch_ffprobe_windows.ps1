<#
.SYNOPSIS
  Vendors the ffprobe + ffmpeg binaries for the Windows build bundle.

.DESCRIPTION
  ffprobe is the fast path in SubtitleSkipCheck (read a file's subtitle streams
  without spinning up a Player). media_kit ships libmpv with ffmpeg linked as a
  LIBRARY, NOT the ffprobe command-line tool, so a clean release has none. This
  downloads BtbN's self-contained static FFmpeg build, verifies its SHA-256, and
  extracts ffprobe.exe AND ffmpeg.exe to third_party/ffprobe/win-x64/. The
  windows/ CMake install rule copies them next to the app exe; callers invoke
  them by absolute path.

  ffmpeg.exe rides along because the archive already contains it -- the download
  and hash check are shared, so the only cost is bundle size. It backs the
  downscale of a 4K file this box can't play smoothly (see TASKS.md).

  NOTE the vendor directory is still named `ffprobe/` for continuity with the
  existing CI references; it holds both tools.

  Source: BtbN/FFmpeg-Builds — the LGPL variant (no GPL-only encoders), the
  cleanest license posture for redistribution. These are big all-codec static
  builds (~100MB); a personal single-machine app can afford it, and ffprobe is an
  optional speed upgrade (the app degrades to the libmpv fallback without it).

  NOTE on pinning: this used to pin an immutable `autobuild-<date>` tag, but BtbN
  PRUNES those after a few weeks and the build then dies on a 404 — which is
  exactly what happened. It now uses the `latest` rolling release, whose asset
  names are stable and never 404.

  The trade: `latest` moves, so a fixed checksum can't be kept in step (BtbN
  rebuilds daily). $ExpectedSha256 is therefore OPTIONAL — leave it empty and the
  script reports the hash it downloaded without verifying; set it to pin a known
  build and the script fails on any mismatch. Either way the download is HTTPS
  from the known publisher and the archive is checked for the binaries we want.
  To pin: run this once, copy the reported SHA-256 in, and expect to refresh it
  whenever you deliberately take a newer build.

  third_party/ is gitignored. Idempotent: a no-op if the exe is already present.
  The GitHub Actions Windows build runs this before `flutter build windows`.
#>
$ErrorActionPreference = 'Stop'

# --- Source build. $ExpectedSha256 is optional: empty = report only (see above) ---
$BuildTag       = 'latest'
$Asset          = 'ffmpeg-master-latest-win64-lgpl.zip'
$Url            = "https://github.com/BtbN/FFmpeg-Builds/releases/download/$BuildTag/$Asset"
$ExpectedSha256 = ''

$Root        = Split-Path -Parent $PSScriptRoot
$VendorRoot  = Join-Path $Root 'third_party\ffprobe'
$DestDir     = Join-Path $VendorRoot 'win-x64'
$Dest        = Join-Path $DestDir 'ffprobe.exe'
$DestFfmpeg  = Join-Path $DestDir 'ffmpeg.exe'
$LicenseDest = Join-Path $VendorRoot 'LICENSE-ffmpeg.txt'

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

if ((Test-Path $Dest) -and (Test-Path $DestFfmpeg) -and (Test-Path $LicenseDest)) {
  Write-Host "OK ffprobe.exe + ffmpeg.exe already vendored: $DestDir"
  exit 0
}

$tmp     = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP ("ffprobe_" + [guid]::NewGuid()))
$archive = Join-Path $tmp 'ffmpeg.zip'
try {
  Write-Host "Downloading FFmpeg (LGPL static, win64) $BuildTag ..."
  Invoke-WebRequest -Uri $Url -OutFile $archive

  $hash = (Get-FileHash -Algorithm SHA256 $archive).Hash
  if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    Write-Host "NOTE downloaded SHA-256: $hash (unpinned; set `$ExpectedSha256 to enforce)"
  } elseif ($hash -ne $ExpectedSha256) {
    throw "SHA-256 mismatch: expected $ExpectedSha256 but got $hash"
  } else {
    Write-Host "OK SHA-256 verified against the pin"
  }

  Write-Host "Extracting ffprobe.exe + ffmpeg.exe ..."
  Expand-Archive -Path $archive -DestinationPath $tmp -Force
  $probe   = Get-ChildItem -Path $tmp -Recurse -Filter 'ffprobe.exe' | Select-Object -First 1
  $ffmpeg  = Get-ChildItem -Path $tmp -Recurse -Filter 'ffmpeg.exe'  | Select-Object -First 1
  $license = Get-ChildItem -Path $tmp -Recurse -Filter 'LICENSE.txt'  | Select-Object -First 1
  if (-not $probe)  { throw "ffprobe.exe not found in archive" }
  if (-not $ffmpeg) { throw "ffmpeg.exe not found in archive" }

  Copy-Item -Path $probe.FullName  -Destination $Dest       -Force
  Copy-Item -Path $ffmpeg.FullName -Destination $DestFfmpeg -Force
  Write-Host "OK Vendored: $Dest"
  Write-Host "OK Vendored: $DestFfmpeg"
  if ($license) {
    Copy-Item -Path $license.FullName -Destination $LicenseDest -Force
    Write-Host "OK License: $LicenseDest"
  }
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "Done."
