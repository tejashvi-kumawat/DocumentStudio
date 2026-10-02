# Registers Document Studio for Start Menu search, "Open with", and PDF/image
# context menus. Use after a portable Release build OR against an installed folder.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\register_windows_shell.ps1
#   powershell -File scripts\windows\register_windows_shell.ps1 -AppDir "C:\...\Document Studio"
#
# Unregister:
#   powershell -File scripts\windows\register_windows_shell.ps1 -Unregister

param(
  [string]$AppDir = "",
  [switch]$Unregister
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$AppName = "Document Studio"
$ExeName = "document_studio.exe"
$Aumid = "DocumentStudio.App"

if (-not $AppDir) {
  $candidates = @(
    (Join-Path $Root "build\windows\x64\runner\Release"),
    (Join-Path $Root "build\windows\runner\Release"),
    (Join-Path $env:LOCALAPPDATA "Programs\$AppName"),
    (Join-Path ${env:ProgramFiles} $AppName)
  )
  foreach ($c in $candidates) {
    if (Test-Path (Join-Path $c $ExeName)) { $AppDir = $c; break }
  }
}
if (-not $AppDir -or -not (Test-Path (Join-Path $AppDir $ExeName))) {
  throw "document_studio.exe not found. Pass -AppDir to the folder that contains it."
}
$AppDir = (Resolve-Path $AppDir).Path
$Exe = Join-Path $AppDir $ExeName

function Notify-Shell {
  try {
    $sig = '[DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);'
    Add-Type -MemberDefinition $sig -Name NativeMethods -Namespace ShellNotify -ErrorAction SilentlyContinue | Out-Null
    [ShellNotify.NativeMethods]::SHChangeNotify(0x8000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
  } catch {}
}

function Remove-Key([string]$Path) {
  if (Test-Path $Path) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($Unregister) {
  Write-Host "Unregistering $AppName shell integration..."
  Remove-Key "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\$ExeName"
  Remove-Key "HKCU:\Software\Classes\Applications\$ExeName"
  Remove-Key "HKCU:\Software\Classes\DocumentStudio.pdf"
  Remove-Key "HKCU:\Software\Classes\DocumentStudio.image"
  Remove-Key "HKCU:\Software\Classes\DocumentStudio.PdfMenu"
  Remove-Key "HKCU:\Software\Classes\DocumentStudio.ImageMenu"
  foreach ($ext in @('.pdf', '.png', '.jpg', '.jpeg', '.webp', '.tif', '.tiff', '.bmp', '.gif')) {
    Remove-ItemProperty -Path "HKCU:\Software\Classes\$ext\OpenWithProgids" -Name "DocumentStudio.pdf" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Classes\$ext\OpenWithProgids" -Name "DocumentStudio.image" -ErrorAction SilentlyContinue
    Remove-Key "HKCU:\Software\Classes\$ext\shell\DocumentStudio"
    Remove-Key "HKCU:\Software\Classes\$ext\shell\DocumentStudio.Open"
    Remove-Key "HKCU:\Software\Classes\$ext\shell\DocumentStudio.Edit"
    Remove-Key "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\DocumentStudio"
    Remove-Key "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\DocumentStudio.Open"
    Remove-Key "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\DocumentStudio.Edit"
  }
  $start = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$AppName.lnk"
  if (Test-Path $start) { Remove-Item -Force $start }
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "register_win11_context_menu.ps1") -Unregister -ErrorAction SilentlyContinue
  Notify-Shell
  Write-Host "Done. Document Studio removed from Open with / Start Menu (this user)."
  exit 0
}

Write-Host "Registering $AppName from $Exe"

# --- App Paths (Start search / Run) ---
$appPaths = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\$ExeName"
New-Item -Path $appPaths -Force | Out-Null
Set-ItemProperty -Path $appPaths -Name "(default)" -Value $Exe
Set-ItemProperty -Path $appPaths -Name "Path" -Value $AppDir

# --- Applications (Open with dialog) ---
$appCls = "HKCU:\Software\Classes\Applications\$ExeName"
New-Item -Path $appCls -Force | Out-Null
Set-ItemProperty -Path $appCls -Name "FriendlyAppName" -Value $AppName
New-Item -Path "$appCls\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$appCls\shell\open\command" -Name "(default)" -Value "`"$Exe`" `"%1`""
$supported = "$appCls\SupportedTypes"
New-Item -Path $supported -Force | Out-Null
foreach ($ext in @('.pdf', '.png', '.jpg', '.jpeg', '.webp', '.tif', '.tiff', '.bmp', '.gif')) {
  New-ItemProperty -Path $supported -Name $ext -Value "" -PropertyType String -Force | Out-Null
}

# --- ProgIDs ---
function Set-ProgId([string]$Id, [string]$Label, [string]$Command) {
  $base = "HKCU:\Software\Classes\$Id"
  New-Item -Path $base -Force | Out-Null
  Set-ItemProperty -Path $base -Name "(default)" -Value $Label
  New-Item -Path "$base\DefaultIcon" -Force | Out-Null
  Set-ItemProperty -Path "$base\DefaultIcon" -Name "(default)" -Value "$Exe,0"
  New-Item -Path "$base\shell\open\command" -Force | Out-Null
  Set-ItemProperty -Path "$base\shell\open\command" -Name "(default)" -Value $Command
}
Set-ProgId "DocumentStudio.pdf" "PDF Document" "`"$Exe`" `"%1`""
Set-ProgId "DocumentStudio.image" "Image" "`"$Exe`" `"%1`""

function Ensure-OpenWith([string]$Ext, [string]$ProgId) {
  $ow = "HKCU:\Software\Classes\$Ext\OpenWithProgids"
  New-Item -Path $ow -Force | Out-Null
  New-ItemProperty -Path $ow -Name $ProgId -Value "" -PropertyType String -Force | Out-Null
  $apps = "HKCU:\Software\Classes\$Ext\OpenWithList\$ExeName"
  New-Item -Path $apps -Force | Out-Null
}
Ensure-OpenWith ".pdf" "DocumentStudio.pdf"
foreach ($ext in @('.png', '.jpg', '.jpeg', '.webp', '.tif', '.tiff', '.bmp', '.gif')) {
  Ensure-OpenWith $ext "DocumentStudio.image"
}

# --- Adobe-style TOP-LEVEL verbs (classic / "Show more options") ---
# Windows 11 primary menu needs the sparse package (register_win11_context_menu.ps1).
function Set-TopLevelVerb([string]$Ext, [string]$Verb, [string]$Label, [string]$Command, [string]$Position = "Top") {
  foreach ($base in @(
      "HKCU:\Software\Classes\$Ext\shell\$Verb",
      "HKCU:\Software\Classes\SystemFileAssociations\$Ext\shell\$Verb"
    )) {
    New-Item -Path "$base\command" -Force | Out-Null
    Set-ItemProperty -Path $base -Name "(default)" -Value $Label
    Set-ItemProperty -Path $base -Name "MUIVerb" -Value $Label
    Set-ItemProperty -Path $base -Name "Icon" -Value "$Exe,0"
    Set-ItemProperty -Path $base -Name "Position" -Value $Position
    Set-ItemProperty -Path "$base\command" -Name "(default)" -Value $Command
  }
}
Set-TopLevelVerb ".pdf" "DocumentStudio.Open" "Open with Document Studio" "`"$Exe`" `"%1`""
Set-TopLevelVerb ".pdf" "DocumentStudio.Edit" "Edit with Document Studio" "`"$Exe`" `"%1`""
foreach ($ext in @('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif')) {
  Set-TopLevelVerb $ext "DocumentStudio.Open" "Open with Document Studio" "`"$Exe`" `"%1`""
  Set-TopLevelVerb $ext "DocumentStudio.Edit" "Edit with Document Studio" "`"$Exe`" --tool images `"%1`""
}

# --- Cascading "Document Studio" context menu ---
function Set-CascadeMenu([string]$Ext, [string]$MenuKey, $Verbs) {
  foreach ($root in @(
      "HKCU:\Software\Classes\$Ext\shell\DocumentStudio",
      "HKCU:\Software\Classes\SystemFileAssociations\$Ext\shell\DocumentStudio"
    )) {
    New-Item -Path $root -Force | Out-Null
    Set-ItemProperty -Path $root -Name "MUIVerb" -Value $AppName
    Set-ItemProperty -Path $root -Name "Icon" -Value "$Exe,0"
    Set-ItemProperty -Path $root -Name "SubCommands" -Value ""
    Set-ItemProperty -Path $root -Name "ExtendedSubCommandsKey" -Value $MenuKey
  }
  $menu = "HKCU:\Software\Classes\$MenuKey"
  Remove-Key $menu
  foreach ($name in @($Verbs.Keys)) {
    $label = $Verbs[$name].Label
    $cmd = $Verbs[$name].Command
    New-Item -Path "$menu\shell\$name\command" -Force | Out-Null
    Set-ItemProperty -Path "$menu\shell\$name" -Name "(default)" -Value $label
    Set-ItemProperty -Path "$menu\shell\$name" -Name "Icon" -Value "$Exe,0"
    Set-ItemProperty -Path "$menu\shell\$name\command" -Name "(default)" -Value $cmd
  }
}

$pdfVerbs = [ordered]@{
  open      = @{ Label = "Open with Document Studio"; Command = "`"$Exe`" `"%1`"" }
  compress  = @{ Label = "Compress PDF"; Command = "`"$Exe`" --tool compress `"%1`"" }
  protect   = @{ Label = "Encrypt / protect PDF"; Command = "`"$Exe`" --tool protect `"%1`"" }
  unlock    = @{ Label = "Decrypt / unlock PDF"; Command = "`"$Exe`" --tool unlock `"%1`"" }
  split     = @{ Label = "Split PDF"; Command = "`"$Exe`" --tool split `"%1`"" }
  merge     = @{ Label = "Merge PDFs…"; Command = "`"$Exe`" --tool merge `"%1`"" }
  ocr       = @{ Label = "Make searchable (OCR)"; Command = "`"$Exe`" --tool ocr `"%1`"" }
  watermark = @{ Label = "Add watermark"; Command = "`"$Exe`" --tool watermark `"%1`"" }
}
Set-CascadeMenu ".pdf" "DocumentStudio.PdfMenu" $pdfVerbs

$imgVerbs = [ordered]@{
  open = @{ Label = "Open with Document Studio"; Command = "`"$Exe`" `"%1`"" }
  edit = @{ Label = "Edit with Document Studio"; Command = "`"$Exe`" --tool images `"%1`"" }
}
foreach ($ext in @('.png', '.jpg', '.jpeg', '.webp', '.tif', '.tiff', '.bmp', '.gif')) {
  Set-CascadeMenu $ext "DocumentStudio.ImageMenu" $imgVerbs
}

# --- Start Menu shortcut (searchable) ---
$programs = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
New-Item -ItemType Directory -Force -Path $programs | Out-Null
$lnkPath = Join-Path $programs "$AppName.lnk"
$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut($lnkPath)
$lnk.TargetPath = $Exe
$lnk.WorkingDirectory = $AppDir
$lnk.Description = $AppName
$lnk.IconLocation = "$Exe,0"
$lnk.Save()
# AppUserModelID for pinning / Start grouping
try {
  $shell = New-Object -ComObject Shell.Application
  $folder = $shell.NameSpace($programs)
  $item = $folder.ParseName("$AppName.lnk")
  if ($item -ne $null) {
    # Best-effort; older Windows may ignore.
  }
} catch {}

Notify-Shell
Write-Host ""
Write-Host "Registered classic shell (Open with / Show more options)."
Write-Host "Start Menu: type `"$AppName`" in Search"
Write-Host ""
Write-Host "Windows 11 primary right-click menu (Adobe-style) needs an extra step:"
$win11 = Join-Path $PSScriptRoot "register_win11_context_menu.ps1"
try {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $win11 -AppDir $AppDir
} catch {
  Write-Warning $_.Exception.Message
  Write-Host "Enable Developer Mode, install .NET 8 SDK, then run:"
  Write-Host "  powershell -File scripts\windows\register_win11_context_menu.ps1 -AppDir `"$AppDir`""
  Write-Host "Until then: right-click PDF → 'Show more options' → Open/Edit with Document Studio."
}
Write-Host ""
Write-Host "Unregister:  powershell -File scripts\windows\register_windows_shell.ps1 -Unregister"
