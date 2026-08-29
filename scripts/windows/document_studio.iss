; Inno Setup script — Document Studio Windows installer (direct download).
; Requires: Inno Setup 6+ on a Windows machine, and a Release build at
;   build\windows\x64\runner\Release\
;
; Build steps (on Windows) — prefer the one-shot script:
;   powershell -File scripts\windows\package_release.ps1
; Or manually:
;   flutter build windows --release
;   powershell -File scripts\bundle_windows_engines.ps1 -BundleDir build\windows\x64\runner\Release
;   ISCC.exe scripts\windows\document_studio.iss
;
; engines\ is included via recursesubdirs on the Release folder (qpdf,
; tesseract+tessdata, LibreOffice, poppler/pdfsig, NSS, openssl, ffmpeg —
; see docs/ENGINES.md).
;
; Optional Authenticode: sign the resulting Setup-*.exe after compile.
; Not for Microsoft Store — GitHub Releases / website download only.

#define MyAppName "Document Studio"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "Document Studio"
#define MyAppExeName "document_studio.exe"
#define MyAppId "com.documentstudio.document_studio"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\dist\windows
OutputBaseFilename=DocumentStudio-{#MyAppVersion}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "DocumentStudio.pdf"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.pdf"; ValueType: string; ValueData: "PDF Document"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.pdf\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.pdf\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""
