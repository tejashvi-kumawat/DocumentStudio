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
; Portable builds (no Setup.exe): after unzip, run
;   powershell -File scripts\windows\register_windows_shell.ps1 -AppDir <folder>
; so Start Menu / Open with / right-click menus work.
;
; engines\ is included via recursesubdirs on the Release folder.

#define MyAppName "Document Studio"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "Document Studio"
#define MyAppExeName "document_studio.exe"
#define MyAppId "com.documentstudio.document_studio"
#define MyAppAumid "DocumentStudio.App"
#define MyAppURL "https://github.com/tejashvi-kumawat/DocumentStudio"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\Programs\{#MyAppName}
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
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
InfoBeforeFile=installer_welcome.txt
DisableWelcomePage=no
ChangesAssociations=yes
CloseApplications=yes
AppMutex={#MyAppId}
#ifdef SignToolEnabled
; Signs Setup.exe and the uninstaller (ISCC /Sds=... from sign_windows.ps1).
SignTool=ds
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "fileassoc"; Description: "Add Open with / right-click menus for PDF and images"; GroupDescription: "Shell integration:"; Flags: checkedonce

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Direct Programs entry is what Start Search indexes most reliably.
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; AppUserModelID: "{#MyAppAumid}"; Comment: "Offline PDF workspace"
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; AppUserModelID: "{#MyAppAumid}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; AppUserModelID: "{#MyAppAumid}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Registry]
; --- Appear in Start / App Paths ---
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; ValueType: string; ValueName: "Path"; ValueData: "{app}"

; --- Open with list ---
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#MyAppName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".png"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".jpg"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".jpeg"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".webp"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".tif"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".tiff"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".bmp"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".gif"; ValueData: ""; Tasks: fileassoc

; --- PDF ProgID + Open with ---
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.pdf"; ValueType: string; ValueData: "PDF Document"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.pdf\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.pdf\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "DocumentStudio.pdf"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.pdf\OpenWithList\{#MyAppExeName}"; Flags: uninsdeletekey; Tasks: fileassoc

; --- Settings > Default apps registration (user still picks the default) ---
Root: HKCU; Subkey: "Software\DocumentStudio\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "{#MyAppName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\DocumentStudio\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Offline PDF workspace"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\DocumentStudio\Capabilities\FileAssociations"; ValueType: string; ValueName: ".pdf"; ValueData: "DocumentStudio.pdf"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "DocumentStudio"; ValueData: "Software\DocumentStudio\Capabilities"; Flags: uninsdeletevalue; Tasks: fileassoc

; --- Image ProgID ---
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.image"; ValueType: string; ValueData: "Image"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.image\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.image\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: fileassoc

Root: HKCU; Subkey: "Software\Classes\.png\OpenWithProgids"; ValueType: string; ValueName: "DocumentStudio.image"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.jpg\OpenWithProgids"; ValueType: string; ValueName: "DocumentStudio.image"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.jpeg\OpenWithProgids"; ValueType: string; ValueName: "DocumentStudio.image"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.webp\OpenWithProgids"; ValueType: string; ValueName: "DocumentStudio.image"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.tif\OpenWithProgids"; ValueType: string; ValueName: "DocumentStudio.image"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.tiff\OpenWithProgids"; ValueType: string; ValueName: "DocumentStudio.image"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.bmp\OpenWithProgids"; ValueType: string; ValueName: "DocumentStudio.image"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.gif\OpenWithProgids"; ValueType: string; ValueName: "DocumentStudio.image"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc

; --- PDF right-click submenu (Document Studio) ---
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.pdf\shell\DocumentStudio"; ValueType: string; ValueName: "MUIVerb"; ValueData: "{#MyAppName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.pdf\shell\DocumentStudio"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.pdf\shell\DocumentStudio"; ValueType: string; ValueName: "SubCommands"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.pdf\shell\DocumentStudio"; ValueType: string; ValueName: "ExtendedSubCommandsKey"; ValueData: "DocumentStudio.PdfMenu"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.pdf\shell\DocumentStudio"; ValueType: string; ValueName: "MUIVerb"; ValueData: "{#MyAppName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.pdf\shell\DocumentStudio"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.pdf\shell\DocumentStudio"; ValueType: string; ValueName: "SubCommands"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\.pdf\shell\DocumentStudio"; ValueType: string; ValueName: "ExtendedSubCommandsKey"; ValueData: "DocumentStudio.PdfMenu"; Tasks: fileassoc

Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\open"; ValueType: string; ValueData: "Open with Document Studio"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\open"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\compress"; ValueType: string; ValueData: "Compress PDF"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\compress\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" --tool compress ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\protect"; ValueType: string; ValueData: "Encrypt / protect PDF"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\protect\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" --tool protect ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\unlock"; ValueType: string; ValueData: "Decrypt / unlock PDF"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\unlock\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" --tool unlock ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\split"; ValueType: string; ValueData: "Split PDF"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\split\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" --tool split ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\merge"; ValueType: string; ValueData: "Merge PDFs…"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\merge\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" --tool merge ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\ocr"; ValueType: string; ValueData: "Make searchable (OCR)"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\ocr\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" --tool ocr ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\watermark"; ValueType: string; ValueData: "Add watermark"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.PdfMenu\shell\watermark\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" --tool watermark ""%1"""; Tasks: fileassoc

; --- Image right-click submenu ---
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.png\shell\DocumentStudio"; ValueType: string; ValueName: "MUIVerb"; ValueData: "{#MyAppName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.png\shell\DocumentStudio"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.png\shell\DocumentStudio"; ValueType: string; ValueName: "SubCommands"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.png\shell\DocumentStudio"; ValueType: string; ValueName: "ExtendedSubCommandsKey"; ValueData: "DocumentStudio.ImageMenu"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.jpg\shell\DocumentStudio"; ValueType: string; ValueName: "MUIVerb"; ValueData: "{#MyAppName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.jpg\shell\DocumentStudio"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.jpg\shell\DocumentStudio"; ValueType: string; ValueName: "SubCommands"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.jpg\shell\DocumentStudio"; ValueType: string; ValueName: "ExtendedSubCommandsKey"; ValueData: "DocumentStudio.ImageMenu"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.jpeg\shell\DocumentStudio"; ValueType: string; ValueName: "MUIVerb"; ValueData: "{#MyAppName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.jpeg\shell\DocumentStudio"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.jpeg\shell\DocumentStudio"; ValueType: string; ValueName: "SubCommands"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.jpeg\shell\DocumentStudio"; ValueType: string; ValueName: "ExtendedSubCommandsKey"; ValueData: "DocumentStudio.ImageMenu"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.webp\shell\DocumentStudio"; ValueType: string; ValueName: "MUIVerb"; ValueData: "{#MyAppName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.webp\shell\DocumentStudio"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.webp\shell\DocumentStudio"; ValueType: string; ValueName: "SubCommands"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.webp\shell\DocumentStudio"; ValueType: string; ValueName: "ExtendedSubCommandsKey"; ValueData: "DocumentStudio.ImageMenu"; Tasks: fileassoc

Root: HKCU; Subkey: "Software\Classes\DocumentStudio.ImageMenu\shell\open"; ValueType: string; ValueData: "Open with Document Studio"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.ImageMenu\shell\open"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.ImageMenu\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.ImageMenu\shell\edit"; ValueType: string; ValueData: "Edit with Document Studio"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\DocumentStudio.ImageMenu\shell\edit\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" --tool images ""%1"""; Tasks: fileassoc
