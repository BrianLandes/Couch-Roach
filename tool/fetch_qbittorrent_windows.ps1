<#
.SYNOPSIS
  Vendors the qBittorrent daemon binary for the Windows build bundle.

.DESCRIPTION
  There is no official *headless* qbittorrent-nox.exe for Windows — the only
  official Windows release is the GUI installer. So this fetches that official
  signed installer, verifies its SHA-256, and extracts the self-contained,
  statically-linked qbittorrent.exe from it with 7-Zip. The app runs that exe
  hidden (start-minimized-to-tray) driven by its WebUI — see QbittorrentProcess.

  Output: third_party/qbittorrent/win-x64/qbittorrent.exe, from where the
  windows/ CMake install rule copies it next to the app exe (and the GitHub
  Actions Windows build runs this script before `flutter build windows`).

  third_party/ is gitignored. Idempotent: a no-op if the exe is already present.
  Requires 7-Zip (preinstalled on GitHub windows-latest runners).
#>
$ErrorActionPreference = 'Stop'

# --- Pinned version (bump deliberately; update InstallerSha256 when you do) ---
$Version         = '5.2.2'
$InstallerUrl    = "https://github.com/qbittorrent/qBittorrent/releases/download/release-$Version/qbittorrent_${Version}_x64_setup.exe"
$InstallerSha256 = '219DE2B0133BF8408F40450A389C227F8D1C2BB520D6D10D1833BC528CA2CD10'

$Root        = Split-Path -Parent $PSScriptRoot
$VendorRoot  = Join-Path $Root 'third_party\qbittorrent'
$DestDir     = Join-Path $VendorRoot 'win-x64'
$Dest        = Join-Path $DestDir 'qbittorrent.exe'
$LicenseDest = Join-Path $VendorRoot 'LICENSE-qbittorrent.txt'

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

if (Test-Path $Dest) {
  Write-Host "OK qbittorrent.exe already vendored: $Dest"
  exit 0
}

# Locate 7-Zip (on PATH, or the default install location).
$sevenZip = (Get-Command 7z -ErrorAction SilentlyContinue).Source
if (-not $sevenZip) { $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe' }
if (-not (Test-Path $sevenZip)) {
  throw "7-Zip not found (needed to extract the installer). Install it or add 7z to PATH."
}

$tmp       = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP ("qb_" + [guid]::NewGuid()))
$installer = Join-Path $tmp 'qb_setup.exe'
try {
  Write-Host "Downloading qBittorrent $Version installer ..."
  Invoke-WebRequest -Uri $InstallerUrl -OutFile $installer

  $hash = (Get-FileHash -Algorithm SHA256 $installer).Hash
  if ($hash -ne $InstallerSha256) {
    throw "SHA-256 mismatch: expected $InstallerSha256 but got $hash"
  }

  # Extract just qbittorrent.exe (it sits at the archive root) from the NSIS installer.
  & $sevenZip e $installer 'qbittorrent.exe' "-o$DestDir" -y | Out-Null
  if (-not (Test-Path $Dest)) { throw "Extraction failed: $Dest not found" }
  Write-Host "OK Vendored: $Dest"

  # GPL license text (COPYING) — required alongside the redistributed binary
  # (source is GPLv2+, the binary distribution is GPLv3+; COPYING covers both).
  if (-not (Test-Path $LicenseDest)) {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/qbittorrent/qBittorrent/release-$Version/COPYING" -OutFile $LicenseDest
    Write-Host "OK License: $LicenseDest"
  }
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "Done."
