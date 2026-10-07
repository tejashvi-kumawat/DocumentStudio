# Download & install

This page is the full install guide. The homepage also shows the same downloads up top.

**Latest version: v1.2.0**  
**All files:** [github.com/tejashvi-kumawat/DocumentStudio/releases/tag/v1.2.0](https://github.com/tejashvi-kumawat/DocumentStudio/releases/tag/v1.2.0)

---

## Windows (recommended path)

### Download

[**DocumentStudio-1.2.0-Setup.exe**](https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.2.0/DocumentStudio-1.2.0-Setup.exe)

### Install

1. Double-click the Setup file.
2. Walk through the wizard (destination folder, optional desktop icon, shell menus).
3. Finish — the app registers for your user.
4. Open **Start** and search **Document Studio**.

You should see a normal app entry (not only a terminal command).

### What the Setup gives you

- Start Menu shortcut  
- App Paths (`document_studio` resolvable)  
- Open with / right-click verbs for PDF and images  
- Bundled engines (qpdf, Tesseract, LibreOffice, …)

### Portable zip (optional)

`DocumentStudio-1.2.0-portable-windows.zip` is for advanced users. Prefer Setup.exe so Start Menu and context menus work.

---

## macOS

### Download

[**DocumentStudio-1.2.0-macos.dmg**](https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.2.0/DocumentStudio-1.2.0-macos.dmg)

### Install

1. Open the DMG.
2. Drag **Document Studio** into **Applications**.
3. First launch: if macOS blocks it, **Finder → right-click app → Open → Open**.
4. Search Spotlight for **Document Studio**.

### Homebrew

```bash
brew tap tejashvi-kumawat/tap
brew install --cask document-studio
```

Upgrade later:

```bash
brew upgrade --cask document-studio
```

One-shot without a prior tap:

```bash
brew install --cask tejashvi-kumawat/tap/document-studio
```

---

## Linux (Debian / Ubuntu amd64)

### Download

[**document-studio_1.2.0_amd64.deb**](https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.2.0/document-studio_1.2.0_amd64.deb)

### Install

```bash
cd ~/Downloads   # or wherever you saved the file
sudo apt install ./document-studio_1.2.0_amd64.deb
```

Then:

- Press the Super key and search **Document Studio**, or  
- Run `document-studio` / `document_studio` in a terminal.

The `.deb` installs a desktop entry and icons under `/usr/share/...` so the app appears in GNOME/KDE menus.

### Homebrew on Linux

```bash
brew tap tejashvi-kumawat/tap
brew install document-studio
brew upgrade document-studio
```

---

## After install — verify

| Check | Expected |
| --- | --- |
| App search | “Document Studio” appears |
| Version | `document_studio --version` → `Document Studio 1.2.0` |
| Help | `document_studio --help` |
| Update | `document_studio --check-update` |

---

## Uninstall

| OS | How |
| --- | --- |
| Windows | Settings → Apps → Document Studio → Uninstall (or Start Menu uninstall shortcut) |
| macOS | Delete the app from Applications · or `brew uninstall --cask document-studio` |
| Linux | `sudo apt remove document-studio` · or `brew uninstall document-studio` |

---

## Next

- [Quick start](#/quick-start) — first 5 minutes in the app  
- [How to use tools](#/how-to) — step-by-step for each major feature  
- [Updates](#/updates) — keep current without re-downloading manually  
