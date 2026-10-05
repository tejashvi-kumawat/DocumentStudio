# Validates and test-installs the WinGet manifest on Windows before it is
# submitted to microsoft/winget-pkgs. Run from the repository root:
#   powershell -ExecutionPolicy Bypass -File packaging\winget\test_manifest.ps1 -Version 1.0.3
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = 'Stop'
$id = 'DocumentStudio.DocumentStudio'
$dir = "packaging\winget\manifests\d\DocumentStudio\DocumentStudio\$Version"

winget --version
winget settings --enable LocalManifestFiles   # needs an elevated shell once

Write-Host "==> Validate"
winget validate --manifest $dir

Write-Host "==> Install from the manifest (downloads the GitHub Release asset)"
winget install --manifest $dir --accept-package-agreements --accept-source-agreements --silent

Write-Host "==> Listed?"
winget list --id $id

Write-Host "==> Uninstall"
winget uninstall --id $id --silent

Write-Host "==> Reinstall, then launch the app to check it starts"
winget install --manifest $dir --silent
Start-Process "$env:LOCALAPPDATA\Programs\Document Studio\document_studio.exe"
