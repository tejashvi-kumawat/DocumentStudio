# Microsoft Store package (.msix). The Store signs it on publication, so
# installs from the Store (or `winget install` from the msstore source) show
# no SmartScreen warning.
#
# Needs the product identity from Partner Center
# (Apps and games -> your app -> Product identity):
#   DS_MSSTORE_IDENTITY_NAME            Package/Identity/Name
#   DS_MSSTORE_PUBLISHER                Package/Identity/Publisher (CN=...)
#   DS_MSSTORE_PUBLISHER_DISPLAY_NAME   Package/Properties/PublisherDisplayName
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\package_store_msix.ps1
#
# Output: dist\windows\DocumentStudio-<version>-store.msix (upload it in
# Partner Center -> Packages).

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root

foreach ($name in "DS_MSSTORE_IDENTITY_NAME", "DS_MSSTORE_PUBLISHER", "DS_MSSTORE_PUBLISHER_DISPLAY_NAME") {
  if (-not [Environment]::GetEnvironmentVariable($name)) {
    Write-Host "Skipping the Store package: $name is not set (copy it from Partner Center -> Product identity)."
    exit 0
  }
}

$VersionLine = Select-String -Path (Join-Path $Root "pubspec.yaml") -Pattern '^version:\s*([^\+]+)' | Select-Object -First 1
$Version = $VersionLine.Matches.Groups[1].Value.Trim()

Write-Host "==> flutter build windows --release (Store build: no self-updater)"
flutter build windows --release --dart-define=DS_STORE_BUILD=true
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed with exit code $LASTEXITCODE" }

$ReleaseDir = Join-Path $Root "build\windows\x64\runner\Release"
if (-not (Test-Path $ReleaseDir)) { $ReleaseDir = Join-Path $Root "build\windows\runner\Release" }

if ($env:DS_SKIP_LIBREOFFICE -ne "1") { $env:DS_BUNDLE_LIBREOFFICE = "1" }
Write-Host "==> bundle engines into $ReleaseDir"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts\bundle_windows_engines.ps1") -BundleDir $ReleaseDir
if ($LASTEXITCODE -ne 0) { throw "bundle_windows_engines.ps1 failed with exit code $LASTEXITCODE" }

Write-Host "==> dart run msix:create (Store)"
dart run msix:create --store --build-windows false `
  --version "$Version.0" `
  --identity-name "$env:DS_MSSTORE_IDENTITY_NAME" `
  --publisher "$env:DS_MSSTORE_PUBLISHER" `
  --publisher-display-name "$env:DS_MSSTORE_PUBLISHER_DISPLAY_NAME" `
  --output-path (Join-Path $Root "dist\windows") `
  --output-name "DocumentStudio-$Version-store"
if ($LASTEXITCODE -ne 0) { throw "msix:create failed with exit code $LASTEXITCODE" }

Write-Host "Done: dist\windows\DocumentStudio-$Version-store.msix"
Write-Host "Upload it in Partner Center -> your app -> Submission -> Packages."
