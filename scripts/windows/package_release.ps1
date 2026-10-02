# One-shot Windows release: Flutter build -> bundle engines -> portable zip -> Inno Setup .exe.
# MUST run on Windows with Flutter desktop + (recommended) Inno Setup 6.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\package_release.ps1
#
# Outputs under dist\windows\:
#   DocumentStudio-<version>-Setup.exe
#   DocumentStudio-<version>-portable-windows.zip

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root

if ($env:OS -notmatch "Windows") {
  Write-Error "This script must run on Windows. A Linux host cannot produce document_studio.exe."
}

if (-not (Test-Path (Join-Path $Root "windows\CMakeLists.txt"))) {
  Write-Host "==> Windows runner missing; running flutter create --platforms=windows"
  flutter create --platforms=windows .
}

Write-Host "==> flutter build windows --release"
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
  throw "flutter build windows --release failed with exit code $LASTEXITCODE. Run: flutter clean && flutter pub get && flutter build windows --release -v"
}

$ReleaseDir = Join-Path $Root "build\windows\x64\runner\Release"
if (-not (Test-Path $ReleaseDir)) {
  $ReleaseDir = Join-Path $Root "build\windows\runner\Release"
}
if (-not (Test-Path $ReleaseDir)) {
  throw "Release folder not found after flutter build windows."
}
if (-not (Test-Path (Join-Path $ReleaseDir "document_studio.exe"))) {
  throw "document_studio.exe missing under $ReleaseDir"
}

# LibreOffice MSI is ~300MB+; default off. Set DS_BUNDLE_LIBREOFFICE=1 to embed it.
if (-not $env:DS_BUNDLE_LIBREOFFICE -and $env:DS_SKIP_LIBREOFFICE -ne "0") {
  $env:DS_SKIP_LIBREOFFICE = "1"
}

Write-Host "==> bundle engines into $ReleaseDir"
& powershell -NoProfile -ExecutionPolicy Bypass `
  -File (Join-Path $Root "scripts\bundle_windows_engines.ps1") `
  -BundleDir $ReleaseDir
if ($LASTEXITCODE -ne 0) {
  throw "bundle_windows_engines.ps1 failed with exit code $LASTEXITCODE"
}

Write-Host "==> portable zip"
& powershell -NoProfile -ExecutionPolicy Bypass `
  -File (Join-Path $Root "scripts\windows\package_portable.ps1")
if ($LASTEXITCODE -ne 0) {
  throw "package_portable.ps1 failed with exit code $LASTEXITCODE"
}

$VersionLine = Select-String -Path (Join-Path $Root "pubspec.yaml") -Pattern '^version:\s*([^\+]+)' | Select-Object -First 1
$Version = $VersionLine.Matches.Groups[1].Value.Trim()

$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($iscc) {
  Write-Host "==> Inno Setup installer ($iscc)"
  & $iscc "/DMyAppVersion=$Version" (Join-Path $Root "scripts\windows\document_studio.iss")
  if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }
} else {
  Write-Warning "Inno Setup 6 (ISCC.exe) not found - portable zip only."
  Write-Warning "Install from https://jrsoftware.org/isinfo.php then re-run, or:"
  Write-Warning "  ISCC.exe scripts\windows\document_studio.iss"
}

Write-Host ""
Write-Host ('Done. Expected artifacts under {0}:' -f (Join-Path $Root 'dist\windows'))
Write-Host "  DocumentStudio-$Version-Setup.exe"
Write-Host "  DocumentStudio-$Version-portable-windows.zip"
