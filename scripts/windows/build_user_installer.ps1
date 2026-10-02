# Builds the end-user GUI installer (DocumentStudio-*-Setup.exe).
# Run once on a Windows dev machine — distribute the Setup.exe, not this script.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\build_user_installer.ps1
#
# Requires: Flutter Windows desktop, Inno Setup 6 (https://jrsoftware.org/isinfo.php)
# Optional: set DS_SKIP_LIBREOFFICE=1 for a smaller build (Office tools use in-app download).

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root

Write-Host ""
Write-Host "=== Document Studio — user installer build ===" -ForegroundColor Cyan
Write-Host "Output for your users: dist\windows\DocumentStudio-<version>-Setup.exe"
Write-Host "(GUI wizard — they double-click Setup.exe; no PowerShell required.)"
Write-Host ""

& (Join-Path $PSScriptRoot "package_release.ps1")
