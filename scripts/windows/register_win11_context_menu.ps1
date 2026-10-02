# Builds DocumentStudio.Shell (Win11 modern context menu COM host) and registers a
# sparse package so Document Studio appears in the primary Windows 11 right-click
# menu (same place as Adobe), not only under Show more options.
#
# Prerequisites on the Windows build PC:
#   - .NET 8 SDK (dotnet)
#   - Developer Mode OR sideloading enabled
#     (Settings > System > For developers)
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\register_win11_context_menu.ps1
#   powershell -File scripts\windows\register_win11_context_menu.ps1 -AppDir "C:\...\Release"

param(
  [string]$AppDir = "",
  [switch]$Unregister
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ShellProj = Join-Path $Root "windows\shell\DocumentStudio.Shell\DocumentStudio.Shell.csproj"
$ManifestSrc = Join-Path $Root "windows\shell\Package.appxmanifest"
$PackageName = "DocumentStudio.ContextMenu"

if ($Unregister) {
  Write-Host "Removing sparse package $PackageName ..."
  Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
    Remove-AppxPackage -ErrorAction SilentlyContinue
  Write-Host "Unregistered Win11 modern context menu package."
  exit 0
}

function Find-AppDir {
  param([string]$Hint)
  if ($Hint -and (Test-Path (Join-Path $Hint "document_studio.exe"))) {
    return (Resolve-Path $Hint).Path
  }
  foreach ($c in @(
      (Join-Path $Root "build\windows\x64\runner\Release"),
      (Join-Path $Root "build\windows\runner\Release"),
      (Join-Path $env:LOCALAPPDATA "Programs\Document Studio")
    )) {
    if (Test-Path (Join-Path $c "document_studio.exe")) {
      return (Resolve-Path $c).Path
    }
  }
  return $null
}

$AppDir = Find-AppDir -Hint $AppDir
if (-not $AppDir) {
  throw "document_studio.exe not found. Build Windows release first, or pass -AppDir."
}

$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) {
  throw ".NET SDK not found. Install .NET 8 SDK from https://dotnet.microsoft.com/download then re-run."
}

Write-Host "==> Building DocumentStudio.Shell (COM host for Win11 menu)"
$out = Join-Path $Root "windows\shell\out"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
& dotnet publish $ShellProj -c Release -r win-x64 --self-contained false -o $out
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

$comhost = Join-Path $out "DocumentStudio.Shell.comhost.dll"
$shellDll = Join-Path $out "DocumentStudio.Shell.dll"
if (-not (Test-Path $comhost) -or -not (Test-Path $shellDll)) {
  throw "COM host outputs missing under $out (expected DocumentStudio.Shell.dll + .comhost.dll)"
}

Write-Host "==> Copying shell binaries next to document_studio.exe"
Copy-Item -Force (Join-Path $out "*") -Destination $AppDir

# Logo for sparse package
$assets = Join-Path $AppDir "Assets"
New-Item -ItemType Directory -Force -Path $assets | Out-Null
$logoSrc = Join-Path $Root "linux\packaging\icons\hicolor\256x256\apps\document-studio.png"
$logoDst = Join-Path $assets "StoreLogo.png"
if (Test-Path $logoSrc) {
  Copy-Item -Force $logoSrc $logoDst
} else {
  [IO.File]::WriteAllBytes($logoDst, [Convert]::FromBase64String(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
}

$manifestDst = Join-Path $AppDir "AppxManifest.xml"
Copy-Item -Force $ManifestSrc $manifestDst

$devMode = $false
try {
  $prop = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" `
    -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
  $devMode = $prop.AllowDevelopmentWithoutDevLicense -eq 1
} catch {}

Write-Host "==> Registering sparse package (Win11 modern context menu)"
Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
  Remove-AppxPackage -ErrorAction SilentlyContinue

try {
  Add-AppxPackage -Path $manifestDst -ExternalLocation $AppDir -Register
  Write-Host ""
  Write-Host "SUCCESS. Right-click a PDF - you should see Document Studio in the main Windows 11 menu."
  Write-Host "If not: enable Developer Mode (Settings > System > For developers), then re-run this script."
  Write-Host "Restart Explorer if needed:  Stop-Process -Name explorer -Force; Start-Process explorer"
} catch {
  Write-Warning ("Sparse package register failed: " + $_)
  if (-not $devMode) {
    Write-Warning "Enable Developer Mode, then re-run. Classic Show more options menus still work via register_windows_shell.ps1."
  }
  throw
}
