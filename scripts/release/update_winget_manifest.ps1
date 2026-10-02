# Updates packaging/winget/*.yaml for a new GitHub Release (version + Setup.exe SHA256).
#
#   powershell -File scripts\release\update_winget_manifest.ps1 `
#     -Version 1.0.3 `
#     -SetupExe dist\windows\DocumentStudio-1.0.3-Setup.exe `
#     -Tag v1.0.3

param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$SetupExe,
  [string]$Tag = "",
  [string]$Repo = "tejashvi-kumawat/DocumentStudio"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$WingetDir = Join-Path $Root "packaging\winget"

if (-not (Test-Path -LiteralPath $SetupExe)) {
  throw "Setup.exe not found: $SetupExe"
}
if (-not $Tag) { $Tag = "v$Version" }

$hash = (Get-FileHash -LiteralPath $SetupExe -Algorithm SHA256).Hash
$url = "https://github.com/$Repo/releases/download/$Tag/DocumentStudio-$Version-Setup.exe"
$date = (Get-Date -Format "yyyy-MM-dd")

Write-Host "Version:  $Version"
Write-Host "URL:      $url"
Write-Host "SHA256:   $hash"

function Set-YamlField([string]$Path, [string]$Pattern, [string]$Replacement) {
  $text = Get-Content -LiteralPath $Path -Raw
  $new = $text -replace $Pattern, $Replacement
  if ($new -eq $text) { Write-Warning "No change in $Path for pattern $Pattern" }
  Set-Content -LiteralPath $Path -Value $new -NoNewline
}

Set-YamlField (Join-Path $WingetDir "DocumentStudio.DocumentStudio.yaml") `
  '(?m)^PackageVersion: .*$' "PackageVersion: $Version"

Set-YamlField (Join-Path $WingetDir "DocumentStudio.DocumentStudio.installer.yaml") `
  '(?m)^PackageVersion: .*$' "PackageVersion: $Version"
Set-YamlField (Join-Path $WingetDir "DocumentStudio.DocumentStudio.installer.yaml") `
  '(?m)^ReleaseDate: .*$' "ReleaseDate: $date"
Set-YamlField (Join-Path $WingetDir "DocumentStudio.DocumentStudio.installer.yaml") `
  '(?m)^    InstallerUrl: .*$' "    InstallerUrl: $url"
Set-YamlField (Join-Path $WingetDir "DocumentStudio.DocumentStudio.installer.yaml") `
  '(?m)^    InstallerSha256: .*$' "    InstallerSha256: $hash"

Write-Host "Updated packaging\winget manifests. Commit and open PR to microsoft/winget-pkgs."
