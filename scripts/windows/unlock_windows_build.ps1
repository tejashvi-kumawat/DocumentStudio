# Stop Document Studio / Explorer locks that break "flutter build windows" INSTALL step.
#   powershell -File scripts\windows\unlock_windows_build.ps1

$ErrorActionPreference = "Continue"
Get-Process -Name "document_studio","Document Studio" -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "Stopped document_studio processes (if any)."
Write-Host "If build still fails with MSB3073, close File Explorer windows under build\windows and retry:"
Write-Host "  flutter clean"
Write-Host "  flutter build windows --release"
