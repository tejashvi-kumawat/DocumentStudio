# Package managers — winget, Homebrew, apt, Flatpak

Goal: **`winget install …`**, **`brew install --cask …`**, **`apt` / Flatpak**, while **direct download** users still get a **GUI installer** (Inno Setup on Windows, `.deb` in Software Center, `.dmg` on macOS).

Manifest templates live under **`packaging/`**. Each store points at **GitHub Release** URLs (same binaries you attach to tag `vX.Y.Z`).

---

## End-user commands (after listings are published)

| Platform | Command (target) | GUI install alternative |
| --- | --- | --- |
| **Windows** | `winget install --id DocumentStudio.DocumentStudio` | Download `DocumentStudio-X.Y.Z-Setup.exe` → wizard |
| **macOS** | `brew install --cask document-studio` | Open `.dmg` → drag to Applications |
| **Linux (Debian/Ubuntu)** | `sudo apt install ./document-studio_X.Y.Z_amd64.deb` *or* hosted repo (below) | Same `.deb` in GNOME Software |
| **Linux (Flatpak)** | `flatpak install flathub com.documentstudio.document_studio` | Flathub / Software Center |

Package managers run **silent** installs where supported; **double-clicking your `.exe`** still shows the **Inno wizard** (`InfoBeforeFile`, folder, shortcuts).

---

## 1. Windows — winget

### What you ship

- **`DocumentStudio-<version>-Setup.exe`** (Inno, `scripts/windows/document_studio.iss`)
- Built on CI with Inno (`/.github/workflows/release.yml`) or locally via `build_user_installer.ps1`

### Manifests (this repo)

```
packaging/winget/DocumentStudio.DocumentStudio.yaml
packaging/winget/DocumentStudio.DocumentStudio.locale.en-US.yaml
packaging/winget/DocumentStudio.DocumentStudio.installer.yaml
```

Before each release, update **version**, **InstallerUrl**, and **InstallerSha256** in the installer manifest:

```powershell
powershell -File scripts\release\update_winget_manifest.ps1 -Version 1.0.3 -SetupExe dist\windows\DocumentStudio-1.0.3-Setup.exe
```

### Publish to the community index

1. Tag release: `git tag v1.0.3 && git push origin v1.0.3`
2. Upload **Setup.exe** (+ zip optional) to [GitHub Releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases) for that tag.
3. Fork [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs).
4. Copy the three YAML files into  
   `manifests/d/DocumentStudio/DocumentStudio/<version>/`
5. Open PR; follow [winget contributing](https://github.com/microsoft/winget-pkgs/blob/master/CONTRIBUTING.md).

First merge can take days; updates are usually faster. **Code signing** the Setup.exe helps SmartScreen and winget trust (optional but recommended long-term).

### Interactive winget (GUI-ish)

Users can run:

```powershell
winget install DocumentStudio.DocumentStudio --interactive
```

when the manifest supports it; direct **Setup.exe** download always uses the full wizard.

---

## 2. macOS — Homebrew Cask

### What you ship

- **`DocumentStudio-<version>-macos.dmg`** from `bash scripts/macos/package_release.sh` on a Mac.

### Template

`packaging/homebrew/Casks/document-studio.rb` — set `version`, `sha256`, and `url` to the GitHub Release asset.

### Publish

**Option A — Homebrew Cask (wide reach):** PR to [homebrew-cask](https://github.com/Homebrew/homebrew-cask) adding `Casks/d/document-studio.rb`.

**Option B — Your tap (faster, you control):**

```bash
# One-time: create github.com/tejashvi-kumawat/homebrew-tap with Casks/document-studio.rb
brew tap tejashvi-kumawat/tap
brew install --cask document-studio
```

---

## 3. Linux — apt / Debian

### Today (no custom repo)

Attach **`document-studio_<ver>_amd64.deb`** to GitHub Releases. Users:

```bash
wget https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.0.3/document-studio_1.0.3_amd64.deb
sudo apt install ./document-studio_1.0.3_amd64.deb
```

Build: `bash scripts/linux/package_deb.sh` after `flutter build linux --release`.

### Later — `apt install document-studio` from your repo

See **`packaging/apt/README.md`**: static **`apt` repository** (reprepro + GitHub Pages or release bucket). That is separate from **Debian/Ubuntu official archives** (multi-month process).

### Flatpak (recommended “store-like” Linux)

Submission files: **`linux/packaging/flathub-submission/`**. After [Flathub](https://flathub.org) accepts the app:

```bash
flatpak install flathub com.documentstudio.document_studio
```

---

## 4. Release checklist (all channels)

1. Bump **`pubspec.yaml`** version.
2. Build artifacts (Windows + Linux + macOS).
3. **`git tag vX.Y.Z`** and push; CI uploads to GitHub Release (when enabled).
4. Update **winget** SHA256 / URLs; PR **winget-pkgs**.
5. Update **Homebrew cask** version / SHA256; PR **homebrew-cask** or tap.
6. Attach **`.deb`** / note Flatpak rebuild if using Flathub manifest from tag.

---

## 5. GUI vs silent (summary)

| Channel | Default UX |
| --- | --- |
| Download **Setup.exe** | Inno **GUI** wizard |
| **winget** | Silent Inno (`InstallerType: inno`) |
| **.deb** / Software Center | Distro GUI or `apt` CLI |
| **brew cask** | CLI; opens app after install if `cask` defines `postflight` |
| **Flatpak** | CLI or Software Center |

All paths install the same **bundled `engines/`** when built with full release scripts (see **[ENGINES.md](ENGINES.md)**).
