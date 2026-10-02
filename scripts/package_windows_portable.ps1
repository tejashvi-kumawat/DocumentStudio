# Portable Windows zip from a Release build (PowerShell).
# Usage (from repo root, on Windows):
#   flutter build windows --release
#   .\scripts\bundle_windows_engines.ps1
#   .\scripts\package_windows_portable.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$ReleaseDir = Join-Path $Root "build\windows\x64\runner\Release"
if (-not (Test-Path $ReleaseDir)) {
  throw "Missing $ReleaseDir - run flutter build windows --release first"
}

$VersionLine = Select-String -Path (Join-Path $Root "pubspec.yaml") -Pattern '^version:\s*([^\+]+)' | Select-Object -First 1
$Version = $VersionLine.Matches.Groups[1].Value.Trim()
$OutDir = Join-Path $Root "dist\windows"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutZip = Join-Path $OutDir "DocumentStudio-$Version-portable-windows.zip"
if (Test-Path $OutZip) { Remove-Item $OutZip -Force }

Compress-Archive -Path (Join-Path $ReleaseDir "*") -DestinationPath $OutZip -Force
Write-Host "Wrote $OutZip"
