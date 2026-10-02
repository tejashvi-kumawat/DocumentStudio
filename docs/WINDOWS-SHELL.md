# Windows shell / context menus

## Why Adobe shows and Document Studio did not

Windows 11 has **two** right-click menus:

1. **Modern (primary)** — Adobe, Copilot, “Edit in Notepad”. Needs a **sparse AppX package** + `IExplorerCommand` COM handler.
2. **Classic** — “Show more options”. Plain registry verbs appear here.

Classic-only registration (registry cascades) never appears next to Adobe. That is expected OS behavior, not a bug in the `.exe`.

## Register (on the Windows PC after building Release)

```powershell
cd C:\Users\ASUS\Desktop\Projects\DocumentStudio

# 1) Start Menu + Open with + classic "Show more options" verbs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\register_windows_shell.ps1 `
  -AppDir ".\build\windows\x64\runner\Release"

# 2) Windows 11 modern menu (Adobe-style) — requires Developer Mode + .NET 8 SDK
#    Settings → System → For developers → Developer Mode = On
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\register_win11_context_menu.ps1 `
  -AppDir ".\build\windows\x64\runner\Release"
```

Then restart Explorer or sign out/in, right-click a PDF: **Document Studio** should appear in the main menu with Open / Compress / Encrypt / …

## Unregister

```powershell
powershell -File scripts\windows\register_windows_shell.ps1 -Unregister
```

## Sources

- Classic: `scripts/windows/register_windows_shell.ps1` + Inno `document_studio.iss`
- Modern: `windows/shell/` (`DocumentStudio.Shell` COM host + sparse `Package.appxmanifest`) + `register_win11_context_menu.ps1`
