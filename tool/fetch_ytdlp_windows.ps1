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
  alongside anyway. YouTube periodically breaks extractors, so bump $Version to
  refresh (and update $ExpectedSha256 from the release's SHA2-256SUMS file).
#>
$ErrorActionPreference = 'Stop'

# --- Pinned version (bump deliberately; update $ExpectedSha256 when you do) ---
$Version        = '2026.07.04'
$Url            = "https://github.com/yt-dlp/yt-dlp/releases/download/$Version/yt-dlp.exe"
$ExpectedSha256 = '52FE3C26DCF71FBDC85B528589020BB0B8E383155CFA81B64DD447BBE35E24B8'

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
  if ($hash -ne $ExpectedSha256) {
    Remove-Item -Force $Dest -ErrorAction SilentlyContinue
    throw "SHA-256 mismatch: expected $ExpectedSha256 but got $hash"
  }
  Write-Host "OK Vendored: $Dest"
}

if (-not (Test-Path $LicenseDest)) {
  Invoke-WebRequest -Uri "https://raw.githubusercontent.com/yt-dlp/yt-dlp/$Version/LICENSE" -OutFile $LicenseDest
  Write-Host "OK License: $LicenseDest"
}

Write-Host "Done."
