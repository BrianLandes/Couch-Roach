<#
.SYNOPSIS
  Vendors the Jackett indexer sidecar for the Windows build bundle.

.DESCRIPTION
  Jackett is the content-agnostic Torznab proxy the app runs as an invisible
  localhost child (DECISIONS §D, same model as qBittorrent). It's C#/.NET 9; this
  fetches the **self-contained** build (bundles the .NET runtime — the TV PC needs
  no .NET installed), verifies its SHA-256, and drops the whole tree at
  third_party/jackett/win-x64/, from where the windows/ CMake rule bundles it as
  <bundle>/jackett/. JackettProcess launches <bundle>/jackett/JackettConsole.exe.

  GOVERNANCE (CLAUDE.md invariant / DECISIONS §D): this ships stock, unmodified
  Jackett. No indexer is enabled by default — the user configures their own
  legal/public-domain indexers in the local Jackett UI; indexer selection (and its
  legal responsibility) lives in the user's instance, not this repo.

  third_party/ is gitignored. Idempotent: a no-op once vendored. The GitHub Actions
  Windows build runs this before `flutter build windows`.
#>
$ErrorActionPreference = 'Stop'

# --- Pinned version (bump deliberately; update $ExpectedSha256 when you do) ---
$Version        = '0.24.2187'
$Asset          = 'Jackett.Binaries.Windows.zip'
$Url            = "https://github.com/Jackett/Jackett/releases/download/v$Version/$Asset"
$ExpectedSha256 = '0519866B89943A44FE07FA9AC0663AB661D847D4B2D905E6840CF6F3880412D0'

$Root        = Split-Path -Parent $PSScriptRoot
$VendorRoot  = Join-Path $Root 'third_party\jackett'
$DestDir     = Join-Path $VendorRoot 'win-x64'
$Launcher    = Join-Path $DestDir 'JackettConsole.exe'
$LicenseDest = Join-Path $VendorRoot 'LICENSE-jackett.txt'

if ((Test-Path $Launcher) -and (Test-Path $LicenseDest)) {
  Write-Host "OK Jackett already vendored: $DestDir"
  exit 0
}

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
$tmp     = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP ("jackett_" + [guid]::NewGuid()))
$archive = Join-Path $tmp 'jackett.zip'
try {
  Write-Host "Downloading Jackett $Version (self-contained, win-x64) ..."
  Invoke-WebRequest -Uri $Url -OutFile $archive

  $hash = (Get-FileHash -Algorithm SHA256 $archive).Hash
  if ($hash -ne $ExpectedSha256) {
    throw "SHA-256 mismatch: expected $ExpectedSha256 but got $hash"
  }

  # The archive is a single top-level Jackett/ folder — flatten it so the launcher
  # lands directly at $DestDir\JackettConsole.exe.
  Write-Host "Extracting ..."
  Expand-Archive -Path $archive -DestinationPath $tmp -Force
  Copy-Item -Path (Join-Path $tmp 'Jackett\*') -Destination $DestDir -Recurse -Force
  if (-not (Test-Path $Launcher)) { throw "JackettConsole.exe not found after extract" }
  Write-Host "OK Vendored: $DestDir"

  if (-not (Test-Path $LicenseDest)) {
    try {
      Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Jackett/Jackett/v$Version/LICENSE" -OutFile $LicenseDest
    } catch {
      Write-Host "! Could not fetch Jackett LICENSE (non-fatal)"
    }
  }
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "Done."
