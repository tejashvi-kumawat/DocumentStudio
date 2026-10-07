# Authenticode signing for Windows release files (removes the SmartScreen
# "unrecognized app" block once the certificate has reputation).
#
# Dot-source it, then call Invoke-DsSign / Get-DsInnoSignCommand:
#   . scripts\windows\sign_windows.ps1
#
# Configure ONE of these (nothing is signed when none is set):
#   A) PFX file:        DS_WIN_CERT_PFX=<path to .pfx>   DS_WIN_CERT_PASSWORD=<password>
#   B) Cert in store:   DS_WIN_CERT_SHA1=<thumbprint>    (USB token / cloud HSM such as Certum SimplySign)
#   C) Azure Trusted Signing (Artifact Signing):
#                       DS_WIN_TRUSTED_SIGNING_DLIB=<path to Azure.CodeSigning.Dlib.dll>
#                       DS_WIN_TRUSTED_SIGNING_METADATA=<path to metadata.json>
# Optional: DS_WIN_TIMESTAMP_URL (default http://timestamp.digicert.com)

function Get-DsSignTool {
  if ($env:DS_SIGNTOOL -and (Test-Path $env:DS_SIGNTOOL)) { return $env:DS_SIGNTOOL }
  $kits = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
  if (Test-Path $kits) {
    $found = Get-ChildItem $kits -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\x64\\' } |
      Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
  }
  $onPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }
  return $null
}

function Get-DsSignMode {
  if ($env:DS_WIN_TRUSTED_SIGNING_DLIB -and $env:DS_WIN_TRUSTED_SIGNING_METADATA) { return "trusted" }
  if ($env:DS_WIN_CERT_PFX) { return "pfx" }
  if ($env:DS_WIN_CERT_SHA1) { return "store" }
  return $null
}

# signtool arguments (without the files) for the configured mode.
function Get-DsSignArgs {
  $ts = if ($env:DS_WIN_TIMESTAMP_URL) { $env:DS_WIN_TIMESTAMP_URL } else { "http://timestamp.digicert.com" }
  switch (Get-DsSignMode) {
    "trusted" {
      return @("sign", "/v", "/fd", "SHA256", "/tr", "http://timestamp.acs.microsoft.com", "/td", "SHA256",
        "/dlib", $env:DS_WIN_TRUSTED_SIGNING_DLIB, "/dmdf", $env:DS_WIN_TRUSTED_SIGNING_METADATA)
    }
    "pfx" {
      return @("sign", "/fd", "SHA256", "/tr", $ts, "/td", "SHA256",
        "/f", $env:DS_WIN_CERT_PFX, "/p", $env:DS_WIN_CERT_PASSWORD)
    }
    "store" {
      return @("sign", "/fd", "SHA256", "/tr", $ts, "/td", "SHA256", "/sha1", $env:DS_WIN_CERT_SHA1)
    }
    default { return $null }
  }
}

# Signs [Files] that are not already validly signed by someone (bundled
# third-party tools keep their own publishers' signatures).
function Invoke-DsSign {
  param([string[]] $Files)
  $mode = Get-DsSignMode
  if (-not $mode) {
    Write-Host "==> Code signing not configured (see scripts\windows\sign_windows.ps1); files stay unsigned."
    return
  }
  $tool = Get-DsSignTool
  if (-not $tool) { throw "signtool.exe not found (install the Windows 10/11 SDK or set DS_SIGNTOOL)." }
  $todo = @()
  foreach ($f in $Files) {
    if (-not (Test-Path $f)) { continue }
    $sig = Get-AuthenticodeSignature -FilePath $f
    if ($sig.Status -eq "Valid") { continue }
    $todo += $f
  }
  if ($todo.Count -eq 0) { return }
  Write-Host "==> Signing $($todo.Count) file(s) ($mode)"
  $signArgs = Get-DsSignArgs
  # signtool takes many files per call; keep command lines short.
  for ($i = 0; $i -lt $todo.Count; $i += 50) {
    $chunk = $todo[$i..([Math]::Min($i + 49, $todo.Count - 1))]
    & $tool @signArgs @chunk
    if ($LASTEXITCODE -ne 0) { throw "signtool failed with exit code $LASTEXITCODE" }
  }
}

# ISCC /S value so Inno Setup signs Setup.exe and its uninstaller.
function Get-DsInnoSignCommand {
  if (-not (Get-DsSignMode)) { return $null }
  $tool = Get-DsSignTool
  if (-not $tool) { return $null }
  $quoted = (Get-DsSignArgs | ForEach-Object { if ($_ -match '\s') { "`$q$_`$q" } else { $_ } }) -join ' '
  return "ds=`$q$tool`$q $quoted `$f"
}
