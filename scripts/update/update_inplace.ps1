#Requires -Version 5.1
<#
.SYNOPSIS
  In-place update for Document Studio on Windows.

.DESCRIPTION
  Prefers: document_studio.exe --update
  Else winget upgrade, else downloads Setup.exe and runs silent Inno install
  over the existing AppId (same folder under %LOCALAPPDATA%\Programs\...).

.EXAMPLE
  powershell -File scripts\update\update_inplace.ps1
#>
$ErrorActionPreference = 'Stop'
$Repo = 'tejashvi-kumawat/DocumentStudio'
$WingetId = 'DocumentStudio.DocumentStudio'

function Find-AppExe {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Document Studio\document_studio.exe'),
    (Get-Command document_studio.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path -LiteralPath $c)) { return $c }
  }
  return $null
}

$exe = Find-AppExe
if ($exe) {
  Write-Host "Running: $exe --update"
  & $exe --update
  exit $LASTEXITCODE
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
  Write-Host "Updating via winget..."
  & winget upgrade --id $WingetId --accept-package-agreements --accept-source-agreements --disable-interactivity
  if ($LASTEXITCODE -eq 0) { exit 0 }
  Write-Host "winget upgrade skipped/failed; trying GitHub Setup.exe..."
}

$api = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{
  'User-Agent' = 'DocumentStudio-Updater'
  'Accept'     = 'application/vnd.github+json'
}
$tag = [string]$api.tag_name
$version = $tag.TrimStart('v')
$asset = $api.assets | Where-Object { $_.name -match '(?i)Setup\.exe$' } | Select-Object -First 1
if (-not $asset) {
  throw "No Setup.exe asset on release $tag"
}

$tmp = Join-Path $env:TEMP ("ds-update-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$setup = Join-Path $tmp $asset.name
Write-Host "Downloading $($asset.browser_download_url)"
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $setup

Write-Host "Installing in place (silent)..."
$p = Start-Process -FilePath $setup -ArgumentList @(
  '/VERYSILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
  '/CLOSEAPPLICATIONS',
  '/RESTARTAPPLICATIONS'
) -PassThru -Wait
exit $p.ExitCode
