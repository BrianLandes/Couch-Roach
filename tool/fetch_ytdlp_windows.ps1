<#
.SYNOPSIS
  Vendors the yt-dlp binary for the Windows build bundle.

.DESCRIPTION
  media_kit/libmpv resolves YouTube URLs (the inline Trailer feature) through its
  builtin ytdl_hook, which shells out to yt-dlp. A clean release has none, so this
  fetches the official self-contained yt-dlp.exe (bundles its own Python — no
  system Python needed), verifies its SHA-256, and drops it at
  third_party/yt-dlp/win-x64/yt-dlp.exe. The windows/ CMake install rule copies it
  next to the app exe, and PlayerScreen points libmpv at it by absolute path.

  third_party/ is gitignored. Idempotent: a no-op if the exe is already present.
  The GitHub Actions Windows build runs this before `flutter build windows`.

  yt-dlp is released under The Unlicense (public domain); its LICENSE is vendored
  alongside anyway.

  NOTE this deliberately tracks the LATEST release rather than a pinned version.
  YouTube breaks extractors constantly and yt-dlp's entire value is keeping up
  with that — a pin guarantees the Trailer feature dies every few weeks, which is
  exactly what happened on 2026.07.04. $ExpectedSha256 is therefore optional:
  empty reports the hash without enforcing it, a value pins and fails on
  mismatch. The download is HTTPS from the official repo either way.
#>
$ErrorActionPreference = 'Stop'

# --- Latest release. $ExpectedSha256 is optional: empty = report only (above) ---
$Version        = 'latest'
$Url            = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
$ExpectedSha256 = ''

$Root        = Split-Path -Parent $PSScriptRoot
$VendorRoot  = Join-Path $Root 'third_party\yt-dlp'
$DestDir     = Join-Path $VendorRoot 'win-x64'
$Dest        = Join-Path $DestDir 'yt-dlp.exe'
$LicenseDest = Join-Path $VendorRoot 'LICENSE-yt-dlp.txt'

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

if (Test-Path $Dest) {
  Write-Host "OK yt-dlp.exe already vendored: $Dest"
} else {
  Write-Host "Downloading yt-dlp $Version (standalone, win-x64) ..."
  Invoke-WebRequest -Uri $Url -OutFile $Dest

  $hash = (Get-FileHash -Algorithm SHA256 $Dest).Hash
  if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    Write-Host "NOTE downloaded SHA-256: $hash (unpinned; set `$ExpectedSha256 to enforce)"
  } elseif ($hash -ne $ExpectedSha256) {
    Remove-Item -Force $Dest -ErrorAction SilentlyContinue
    throw "SHA-256 mismatch: expected $ExpectedSha256 but got $hash"
  } else {
    Write-Host "OK SHA-256 verified against the pin"
  }
  Write-Host "OK Vendored: $Dest"
}

if (-not (Test-Path $LicenseDest)) {
  # `$Version` is "latest", which is a release alias and not a git ref — the
  # LICENSE has to come off a real branch.
  Invoke-WebRequest -Uri "https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/LICENSE" -OutFile $LicenseDest
  Write-Host "OK License: $LicenseDest"
}

Write-Host "Done."
