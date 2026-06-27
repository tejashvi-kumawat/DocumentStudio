# Bundle desktop CLI engines into a Flutter Windows Release output folder.
# Non-interactive: downloads pinned portable archives into .tools\windows\ when
# PATH / local installs are missing. LibreOffice is extracted from the official
# MSI into engines\libreoffice (same approach as Linux's Document Foundation
# tarball) — not left as a first-run download.
#
# Usage (on Windows, after flutter build windows --release):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bundle_windows_engines.ps1
#   powershell -File scripts\bundle_windows_engines.ps1 -BundleDir build\windows\x64\runner\Release
#
# Skip LibreOffice (huge): $env:DS_SKIP_LIBREOFFICE = "1"
# Override LO version:     $env:DS_LIBREOFFICE_VERSION = "26.2.6"
param(
  [Parameter(Mandatory = $false)]
  [string]$BundleDir = ""
)

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $BundleDir) {
  $candidates = @(
    (Join-Path $Root "build\windows\x64\runner\Release"),
    (Join-Path $Root "build\windows\runner\Release")
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { $BundleDir = $c; break }
  }
}
if (-not $BundleDir -or -not (Test-Path $BundleDir)) {
  Write-Error "BundleDir not found. Pass -BundleDir <Release folder> or build windows --release first."
  exit 2
}

$BundleDir = (Resolve-Path $BundleDir).Path
$engines = Join-Path $BundleDir "engines"
$bin = Join-Path $engines "bin"
$lib = Join-Path $engines "lib"
$tessdata = Join-Path $engines "tessdata"
$cache = Join-Path $Root ".tools\windows"
New-Item -ItemType Directory -Force -Path $bin, $lib, $tessdata, $cache | Out-Null

# --- pinned versions / URLs (override via env) ---
$QpdfVersion = if ($env:DS_QPDF_VERSION) { $env:DS_QPDF_VERSION } else { "12.4.2" }
$PopplerVersion = if ($env:DS_POPPLER_VERSION) { $env:DS_POPPLER_VERSION } else { "24.08.0-0" }
$LoVersion = if ($env:DS_LIBREOFFICE_VERSION) { $env:DS_LIBREOFFICE_VERSION } else { "26.2.6" }
$TesseractSetupUrl = if ($env:DS_TESSERACT_SETUP_URL) {
  $env:DS_TESSERACT_SETUP_URL
} else {
  "https://github.com/tesseract-ocr/tesseract/releases/download/5.5.3/tesseract-ocr-w64-setup-5.5.3.20260724.exe"
}
$OpenSslLightUrl = if ($env:DS_OPENSSL_URL) {
  $env:DS_OPENSSL_URL
} else {
  "https://slproweb.com and/download/Win64OpenSSL_Light-4_0_2.exe".Replace(" and/", "/")
}
$FfmpegUrl = if ($env:DS_FFMPEG_URL) {
  $env:DS_FFMPEG_URL
} else {
  "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
}
$ZstdUrl = "https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-v1.5.7-win64.zip"
$MsysBase = "https://repo.msys2.org/mingw/mingw64"
$NssPkg = if ($env:DS_NSS_PKG) { $env:DS_NSS_PKG } else { "mingw-w64-x86_64-nss-3.129-1-any.pkg.tar.zst" }
$NsprPkg = if ($env:DS_NSPR_PKG) { $env:DS_NSPR_PKG } else { "mingw-w64-x86_64-nspr-4.40-1-any.pkg.tar.zst" }
$SqlitePkg = if ($env:DS_SQLITE_PKG) { $env:DS_SQLITE_PKG } else { "mingw-w64-x86_64-sqlite3-3.53.4-1-any.pkg.tar.zst" }
$ZlibPkg = if ($env:DS_ZLIB_PKG) { $env:DS_ZLIB_PKG } else { "mingw-w64-x86_64-zlib-1.3.2-2-any.pkg.tar.zst" }

function Write-CmdWrapper([string]$Name, [string]$ExeLeaf) {
  @"
@echo off
setlocal
set "ROOT=%~dp0"
set "PATH=%ROOT%bin;%ROOT%lib;%PATH%"
if exist "%ROOT%tessdata\eng.traineddata" set "TESSDATA_PREFIX=%ROOT%tessdata"
"%ROOT%bin\$ExeLeaf" %*
"@ | Set-Content -Encoding ASCII (Join-Path $engines "$Name.cmd")
}

function Get-CachedFile([string]$Url, [string]$FileName) {
  $dest = Join-Path $cache $FileName
  if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 0)) { return $dest }
  Write-Host "Downloading $Url ..."
  try {
    Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -eq 0) {
      throw "empty download"
    }
    return $dest
  } catch {
    Write-Host "WARNING: download failed for $Url : $_"
    Remove-Item -Force $dest -ErrorAction SilentlyContinue
    return $null
  }
}

function Expand-ZipTo([string]$ZipPath, [string]$Dest) {
  if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  Expand-Archive -Path $ZipPath -DestinationPath $Dest -Force
}

function Copy-SiblingDlls([string]$FromDir) {
  if (-not (Test-Path $FromDir)) { return }
  Get-ChildItem $FromDir -Filter "*.dll" -ErrorAction SilentlyContinue |
    ForEach-Object { Copy-Item -Force $_.FullName $bin }
}

# --- qpdf (portable mingw64 zip) ---
function Bundle-Qpdf {
  $existing = Get-Command qpdf -ErrorAction SilentlyContinue
  if ($existing) {
    Copy-Item -Force $existing.Source (Join-Path $bin "qpdf.exe")
    Copy-SiblingDlls (Split-Path -Parent $existing.Source)
    Write-CmdWrapper "qpdf" "qpdf.exe"
    Write-Host "Bundled qpdf from PATH: $($existing.Source)"
    return
  }
  $zipName = "qpdf-$QpdfVersion-mingw64.zip"
  $url = "https://github.com/qpdf/qpdf/releases/download/v$QpdfVersion/$zipName"
  $zip = Get-CachedFile $url $zipName
  if (-not $zip) { Write-Host "WARNING: qpdf not bundled."; return }
  $extract = Join-Path $cache "qpdf_extract"
  Expand-ZipTo $zip $extract
  $qpdfExe = Get-ChildItem -Path $extract -Recurse -Filter qpdf.exe | Select-Object -First 1
  if (-not $qpdfExe) { Write-Host "WARNING: qpdf.exe missing in zip."; return }
  $qpdfBin = $qpdfExe.Directory.FullName
  Copy-Item -Force (Join-Path $qpdfBin "*") $bin -ErrorAction SilentlyContinue
  $qpdfRoot = $qpdfExe.Directory.Parent.FullName
  if (Test-Path (Join-Path $qpdfRoot "lib")) {
    Copy-Item -Force (Join-Path $qpdfRoot "lib\*") $lib -ErrorAction SilentlyContinue
  }
  Write-CmdWrapper "qpdf" "qpdf.exe"
  Write-Host "Bundled portable qpdf $QpdfVersion"
}

# --- tesseract (NSIS silent install into cache, then copy) ---
function Bundle-Tesseract {
  $src = $null
  if ($env:DS_TESSERACT_ROOT -and (Test-Path (Join-Path $env:DS_TESSERACT_ROOT "tesseract.exe"))) {
    $src = Join-Path $env:DS_TESSERACT_ROOT "tesseract.exe"
  } else {
    $cmd = Get-Command tesseract -ErrorAction SilentlyContinue
    if ($cmd) { $src = $cmd.Source }
    $choco = "C:\Program Files\Tesseract-OCR\tesseract.exe"
    if (-not $src -and (Test-Path $choco)) { $src = $choco }
  }

  if (-not $src) {
    $setupName = "tesseract-ocr-w64-setup.exe"
    $setup = Get-CachedFile $TesseractSetupUrl $setupName
    $installDir = Join-Path $cache "tesseract_install"
    if ($setup) {
      if (-not (Test-Path (Join-Path $installDir "tesseract.exe"))) {
        Write-Host "Silent-installing Tesseract into $installDir …"
        if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
        # NSIS: /S silent, /D= must be last and unquoted.
        $p = Start-Process -FilePath $setup -ArgumentList "/S", "/D=$installDir" -Wait -PassThru
        if ($p.ExitCode -ne 0) {
          Write-Host "WARNING: Tesseract setup exit $($p.ExitCode)"
        }
      }
      if (Test-Path (Join-Path $installDir "tesseract.exe")) {
        $src = Join-Path $installDir "tesseract.exe"
      }
    }
  }

  if (-not $src) {
    Write-Host "WARNING: tesseract.exe not bundled."
    return
  }
  $tessRoot = Split-Path -Parent $src
  Copy-Item -Force $src (Join-Path $bin "tesseract.exe")
  Copy-SiblingDlls $tessRoot
  Write-CmdWrapper "tesseract" "tesseract.exe"
  Write-Host "Bundled tesseract from $src"

  $srcTess = @(
    (Join-Path $tessRoot "tessdata"),
    "C:\Program Files\Tesseract-OCR\tessdata",
    (Join-Path $cache "tesseract_install\tessdata")
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  foreach ($lang in @("eng", "osd")) {
    $dest = Join-Path $tessdata "$lang.traineddata"
    if (Test-Path $dest) { continue }
    $local = if ($srcTess) { Join-Path $srcTess "$lang.traineddata" } else { $null }
    if ($local -and (Test-Path $local)) {
      Copy-Item -Force $local $dest
    } else {
      $url = "https://github.com/tesseract-ocr/tessdata_fast/raw/main/$lang.traineddata"
      $cached = Get-CachedFile $url "$lang.traineddata"
      if ($cached) { Copy-Item -Force $cached $dest }
    }
  }
}

# --- poppler (pdfsig) ---
function Bundle-Poppler {
  $cmd = Get-Command pdfsig -ErrorAction SilentlyContinue
  if ($cmd) {
    Copy-Item -Force $cmd.Source (Join-Path $bin "pdfsig.exe")
    Copy-SiblingDlls (Split-Path -Parent $cmd.Source)
    Write-CmdWrapper "pdfsig" "pdfsig.exe"
    Write-Host "Bundled pdfsig from PATH"
    return
  }
  $zipName = "Release-$PopplerVersion.zip"
  $url = "https://github.com/oschwartz10612/poppler-windows/releases/download/v$PopplerVersion/$zipName"
  $zip = Get-CachedFile $url $zipName
  if (-not $zip) {
    Write-Host "WARNING: poppler/pdfsig not bundled."
    return
  }
  $extract = Join-Path $cache "poppler_extract"
  Expand-ZipTo $zip $extract
  $pdfsig = Get-ChildItem -Path $extract -Recurse -Filter pdfsig.exe | Select-Object -First 1
  if (-not $pdfsig) {
    Write-Host "WARNING: pdfsig.exe not in poppler zip (build may omit it)."
    Get-ChildItem -Path $extract -Recurse -Include pdfinfo.exe, pdftotext.exe, pdftoppm.exe |
      ForEach-Object { Copy-Item -Force $_.FullName $bin }
    return
  }
  $popBin = $pdfsig.Directory.FullName
  Copy-Item -Force (Join-Path $popBin "*") $bin -ErrorAction SilentlyContinue
  Write-CmdWrapper "pdfsig" "pdfsig.exe"
  Write-Host "Bundled poppler/pdfsig from $url"
}

# --- openssl (Shining Light Light installer → cache) ---
function Bundle-OpenSsl {
  $cmd = Get-Command openssl -ErrorAction SilentlyContinue
  $src = $null
  if ($cmd) { $src = $cmd.Source }
  if (-not $src) {
    foreach ($p in @(
      "C:\Program Files\OpenSSL-Win64\bin\openssl.exe",
      "C:\Program Files\Git\usr\bin\openssl.exe",
      (Join-Path $cache "openssl_install\bin\openssl.exe")
    )) {
      if (Test-Path $p) { $src = $p; break }
    }
  }
  if (-not $src) {
    $setup = Get-CachedFile $OpenSslLightUrl "Win64OpenSSL_Light.exe"
    $installDir = Join-Path $cache "openssl_install"
    if ($setup) {
      Write-Host "Silent-installing OpenSSL Light into $installDir …"
      if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }
      New-Item -ItemType Directory -Force -Path $installDir | Out-Null
      $args = "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/DIR=$installDir"
      $p = Start-Process -FilePath $setup -ArgumentList $args -Wait -PassThru
      if ($p.ExitCode -ne 0) {
        Write-Host "WARNING: OpenSSL setup exit $($p.ExitCode)"
      }
      if (Test-Path (Join-Path $installDir "bin\openssl.exe")) {
        $src = Join-Path $installDir "bin\openssl.exe"
      }
    }
  }
  if ($src) {
    Copy-Item -Force $src (Join-Path $bin "openssl.exe")
    $dir = Split-Path -Parent $src
    Copy-SiblingDlls $dir
    Get-ChildItem $dir -Filter "lib*.dll" -ErrorAction SilentlyContinue |
      ForEach-Object { Copy-Item -Force $_.FullName $bin }
    Write-CmdWrapper "openssl" "openssl.exe"
    Write-Host "Bundled openssl from $src"
  } else {
    Write-Host "WARNING: openssl not bundled."
  }
}

# --- NSS certutil / pk12util via MSYS2 mingw64 packages ---
function Get-ZstdExe {
  $existing = Get-Command zstd -ErrorAction SilentlyContinue
  if ($existing) { return $existing.Source }
  $local = Join-Path $cache "zstd\zstd.exe"
  if (Test-Path $local) { return $local }
  $zip = Get-CachedFile $ZstdUrl "zstd-win64.zip"
  if (-not $zip) { return $null }
  $dest = Join-Path $cache "zstd"
  Expand-ZipTo $zip $dest
  $exe = Get-ChildItem -Path $dest -Recurse -Filter zstd.exe | Select-Object -First 1
  if ($exe) { return $exe.FullName }
  return $null
}

function Expand-MsysPkg([string]$PkgFile, [string]$DestRoot) {
  $zstd = Get-ZstdExe
  if (-not $zstd) {
    Write-Host "WARNING: zstd.exe unavailable — cannot extract $PkgFile"
    return $false
  }
  New-Item -ItemType Directory -Force -Path $DestRoot | Out-Null
  $tarPath = Join-Path $cache ([IO.Path]::GetFileNameWithoutExtension($PkgFile) + ".tar")
  # pkg.tar.zst → .tar then extract
  & $zstd -d -f -o $tarPath $PkgFile 2>$null
  if (-not (Test-Path $tarPath)) {
    # some zstd builds want different flags
    & $zstd -d -f $PkgFile -o $tarPath 2>$null
  }
  if (-not (Test-Path $tarPath)) {
    Write-Host "WARNING: failed to decompress $PkgFile"
    return $false
  }
  tar -xf $tarPath -C $DestRoot 2>$null
  if ($LASTEXITCODE -ne 0) {
    # Fallback: tar.exe may be absent on older Windows
    Write-Host "WARNING: tar extract failed for $PkgFile (exit $LASTEXITCODE)"
    return $false
  }
  return $true
}

function Bundle-NssTools {
  foreach ($name in @("certutil", "pk12util")) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    # Windows ships its own certutil.exe — skip that (no -N / NSS DB).
    if ($c -and $c.Source -notmatch '\\System32\\' -and $c.Source -notmatch '\\SysWOW64\\') {
      Copy-Item -Force $c.Source (Join-Path $bin "$name.exe")
      Copy-SiblingDlls (Split-Path -Parent $c.Source)
      Write-CmdWrapper $name "$name.exe"
    }
  }
  if ((Test-Path (Join-Path $bin "certutil.exe")) -and (Test-Path (Join-Path $bin "pk12util.exe"))) {
    Write-Host "Bundled NSS tools from PATH"
    return
  }

  $msysRoot = Join-Path $cache "msys_nss"
  New-Item -ItemType Directory -Force -Path $msysRoot | Out-Null
  foreach ($pkg in @($NssPkg, $NsprPkg, $SqlitePkg, $ZlibPkg)) {
    $url = "$MsysBase/$pkg"
    $file = Get-CachedFile $url $pkg
    if (-not $file) { continue }
    Expand-MsysPkg $file $msysRoot | Out-Null
  }
  $mingwBin = Join-Path $msysRoot "mingw64\bin"
  if (-not (Test-Path $mingwBin)) {
    Write-Host "WARNING: MSYS2 NSS extract missing mingw64\bin"
    return
  }
  foreach ($name in @("certutil.exe", "pk12util.exe")) {
    $p = Join-Path $mingwBin $name
    if (Test-Path $p) { Copy-Item -Force $p $bin }
  }
  # Copy runtime DLLs next to the tools.
  Get-ChildItem $mingwBin -Filter "*.dll" -ErrorAction SilentlyContinue |
    ForEach-Object { Copy-Item -Force $_.FullName $bin }
  if (Test-Path (Join-Path $bin "certutil.exe")) {
    Write-CmdWrapper "certutil" "certutil.exe"
  }
  if (Test-Path (Join-Path $bin "pk12util.exe")) {
    Write-CmdWrapper "pk12util" "pk12util.exe"
  }
  if ((Test-Path (Join-Path $bin "certutil.exe")) -and (Test-Path (Join-Path $bin "pk12util.exe"))) {
    Write-Host "Bundled NSS certutil/pk12util from MSYS2 packages"
  } else {
    Write-Host "WARNING: NSS certutil/pk12util not fully bundled."
  }
}

# --- ffmpeg ---
function Bundle-Ffmpeg {
  $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($cmd) {
    Copy-Item -Force $cmd.Source (Join-Path $bin "ffmpeg.exe")
    Write-CmdWrapper "ffmpeg" "ffmpeg.exe"
    Write-Host "Bundled ffmpeg from PATH"
    return
  }
  $zip = Get-CachedFile $FfmpegUrl "ffmpeg-release-essentials.zip"
  if (-not $zip) { Write-Host "WARNING: ffmpeg not bundled."; return }
  $extract = Join-Path $cache "ffmpeg_extract"
  Expand-ZipTo $zip $extract
  $ff = Get-ChildItem -Path $extract -Recurse -Filter ffmpeg.exe | Select-Object -First 1
  if ($ff) {
    Copy-Item -Force $ff.FullName (Join-Path $bin "ffmpeg.exe")
    Write-CmdWrapper "ffmpeg" "ffmpeg.exe"
    Write-Host "Bundled portable ffmpeg"
  }
}

# --- LibreOffice (official MSI → administrative extract into engines/) ---
function Bundle-LibreOffice {
  if ($env:DS_SKIP_LIBREOFFICE -eq "1") {
    Write-Host "Skipping LibreOffice (DS_SKIP_LIBREOFFICE=1)."
    return
  }

  $prog = $null
  if ($env:DS_LIBREOFFICE_ROOT) {
    $cand = Join-Path $env:DS_LIBREOFFICE_ROOT "soffice.exe"
    if (Test-Path $cand) { $prog = $env:DS_LIBREOFFICE_ROOT }
  }
  if (-not $prog) {
    foreach ($p in @(
      "C:\Program Files\LibreOffice\program",
      "C:\Program Files (x86)\LibreOffice\program"
    )) {
      if (Test-Path (Join-Path $p "soffice.exe")) { $prog = $p; break }
    }
  }

  $loDest = Join-Path $engines "libreoffice"
  if (-not $prog) {
    $msiName = "LibreOffice_${LoVersion}_Win_x86-64.msi"
    $url = if ($env:DS_LIBREOFFICE_MSI_URL) {
      $env:DS_LIBREOFFICE_MSI_URL
    } else {
      "https://download.documentfoundation.org/libreoffice/stable/$LoVersion/win/x86_64/$msiName"
    }
    $msi = Get-CachedFile $url $msiName
    if (-not $msi) {
      Write-Host "WARNING: LibreOffice MSI download failed."
      return
    }
    $extract = Join-Path $cache "libreoffice_msi_extract"
    Write-Host "Extracting LibreOffice MSI (administrative install) into $extract …"
    if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList @(
      "/a", $msi, "/qn", "TARGETDIR=$extract"
    ) -Wait -PassThru
    if ($p.ExitCode -ne 0) {
      Write-Host "WARNING: msiexec /a exit $($p.ExitCode)"
    }
    $found = Get-ChildItem -Path $extract -Recurse -Filter soffice.exe -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($found) {
      $prog = $found.Directory.FullName
      # Prefer copying the whole LibreOffice tree under engines/libreoffice
      $srcRoot = $prog
      # Walk up until we find a folder that looks like an LO install root.
      $probe = Get-Item $prog
      while ($probe.Parent -and $probe.Name -ne "LibreOffice" -and $probe.FullName -ne $extract) {
        if (Test-Path (Join-Path $probe.Parent.FullName "program\soffice.exe")) {
          $probe = $probe.Parent
          break
        }
        $probe = $probe.Parent
      }
      if (Test-Path (Join-Path $probe.FullName "program\soffice.exe")) {
        Write-Host "Copying LibreOffice tree from $($probe.FullName) …"
        if (Test-Path $loDest) { Remove-Item -Recurse -Force $loDest }
        Copy-Item -Recurse -Force $probe.FullName $loDest
        $prog = Join-Path $loDest "program"
      } else {
        New-Item -ItemType Directory -Force -Path (Join-Path $loDest "program") | Out-Null
        Copy-Item -Recurse -Force (Join-Path $srcRoot "*") (Join-Path $loDest "program")
        $prog = Join-Path $loDest "program"
      }
    }
  } else {
    # Copy from local install when DS_BUNDLE_LIBREOFFICE_FULL=1 or always for parity with Linux.
    $srcRoot = Split-Path -Parent $prog
    Write-Host "Copying LibreOffice from $srcRoot …"
    if (Test-Path $loDest) { Remove-Item -Recurse -Force $loDest }
    Copy-Item -Recurse -Force $srcRoot $loDest
    $prog = Join-Path $loDest "program"
  }

  if (-not $prog -or -not (Test-Path (Join-Path $prog "soffice.exe"))) {
    Write-Host "WARNING: LibreOffice soffice.exe not bundled."
    return
  }

  @"
@echo off
setlocal
set "ROOT=%~dp0"
if exist "%ROOT%libreoffice\program\soffice.exe" (
  "%ROOT%libreoffice\program\soffice.exe" %*
  exit /b %ERRORLEVEL%
)
if exist "%ROOT%bin\soffice.exe" (
  "%ROOT%bin\soffice.exe" %*
  exit /b %ERRORLEVEL%
)
echo LibreOffice (soffice) not found under engines\ >&2
exit /b 127
"@ | Set-Content -Encoding ASCII (Join-Path $engines "soffice.cmd")
  Write-Host "Bundled LibreOffice soffice → $prog"
}

Bundle-Qpdf
Bundle-Tesseract
Bundle-Poppler
Bundle-OpenSsl
Bundle-NssTools
Bundle-Ffmpeg
Bundle-LibreOffice

Write-Host ""
Write-Host "Windows engines ready under $engines"
$required = @("qpdf", "tesseract", "ffmpeg", "openssl", "pdfsig", "certutil", "pk12util", "soffice")
$missing = @()
foreach ($name in $required) {
  $ok = (Test-Path (Join-Path $engines "$name.cmd")) -or
        (Test-Path (Join-Path $bin "$name.exe")) -or
        ($name -eq "soffice" -and (Test-Path (Join-Path $engines "libreoffice\program\soffice.exe")))
  if (-not $ok) { $missing += $name }
}
if ($missing.Count -gt 0) {
  Write-Host "WARNING: missing engine wrappers/binaries: $($missing -join ', ')"
} else {
  Write-Host "All expected engines present: $($required -join ', ')"
}
Get-ChildItem $engines -ErrorAction SilentlyContinue | Format-Table Name, Length
