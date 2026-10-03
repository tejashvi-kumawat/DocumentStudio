# Install

Download from [GitHub Releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases/tag/v1.0.3) (current: **v1.0.3**).

## Windows

1. Download **`DocumentStudio-1.0.3-Setup.exe`**.
2. Run the installer (GUI wizard).
3. Open **Document Studio** from the Start Menu.

Portable zip is available for advanced users; the **Setup.exe** is what registers Start Menu / Open with / context menus.

```text
winget install --id DocumentStudio.DocumentStudio
```

*(Community winget listing may lag the first release.)*

## macOS

1. Download **`DocumentStudio-1.0.3-macos.dmg`**.
2. Open the DMG and drag **Document Studio** into Applications.
3. First launch may need **right-click → Open** (ad-hoc signed builds).

```bash
brew tap tejashvi-kumawat/tap
brew install --cask document-studio
```

One-shot:

```bash
brew install --cask tejashvi-kumawat/tap/document-studio
```

## Linux (Debian / Ubuntu)

1. Download **`document-studio_1.0.3_amd64.deb`**.
2. Install:

```bash
sudo apt install ./document-studio_1.0.3_amd64.deb
```

Then search **Document Studio** in Activities / your app menu, or run:

```bash
document-studio
```

### Homebrew on Linux

```bash
brew tap tejashvi-kumawat/tap
brew install document-studio
```

## After install

You should see **Document Studio** in:

- Windows → Start search  
- macOS → Spotlight / Launchpad  
- Linux → GNOME/KDE app search  

If the binary works in a terminal but the menu entry is missing, log out/in once, or see [FAQ](#/faq).
