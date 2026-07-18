# Distribution — Document Studio

This project ships **one store listing** and **direct-download installers**.

| Channel | Artifact | Who builds it |
| --- | --- | --- |
| **Google Play** | Signed `.aab` | You (or CI with keystore secrets) |
| **macOS direct** | `.dmg` (or `.zip`) | A **Mac** (`flutter build macos`) |
| **Windows direct** | Setup `.exe` + portable `.zip` | A **Windows** PC |
| **Linux direct** | `.deb` + AppImage | This Linux machine / Ubuntu CI |

Host desktop installers on **GitHub Releases** (attach the files to a `v*` tag). Do not invent a separate download site until you need one.

**Not in scope:** Apple App Store / Mac App Store (no Apple Developer subscription). Microsoft Store (undecided — not set up). iOS is skipped for distribution.

---

## 1. Google Play (Android)

**Package ID (do not change after first upload):** `com.documentstudio.document_studio`  
**Version:** `pubspec.yaml` → `version: X.Y.Z+BUILD` (`versionName` + `versionCode`)

### Create the upload keystore (once)

```bash
keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties
# edit android/key.properties with real passwords / alias / storeFile
```

`android/key.properties` and `*.jks` are gitignored. Back them up offline.

### Build the AAB

```bash
make appbundle
# same as: flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

Without `key.properties`, Gradle signs with the **debug** key — never upload that to Play.

### Play Console steps

Listing copy, rating notes, privacy outline, screenshots: **[docs/store/play/](store/play/)**.

1. Open [Google Play Console](https://play.google.com/console) (you already have a developer account).
2. Create app → name **Document Studio** → app / free → declarations.
3. Complete **Store listing**, **Content rating**, **Target audience**, **Privacy policy** URL, **Data safety**.
4. **Testing → Internal testing** → create release → upload the `.aab` → add yourself as tester → smoke-test.
5. Promote to **Closed** / **Open** testing if desired, then **Production**.

CI can produce an AAB without secrets (labeled debug-signed). For Play upload, either build locally with `key.properties` or set GitHub Secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`.

---

## 2. macOS direct download (.dmg)

Must run on a **Mac** (not this Linux machine):

```bash
bash scripts/macos/package_release.sh
```

Outputs under `dist/macos/`: `DocumentStudio-<version>-macos.dmg` and a `.zip` of the `.app`.

Engines (qpdf, tesseract+tessdata, poppler/NSS, ffmpeg, LibreOffice from official DMG): **[ENGINES.md](ENGINES.md)**. Host-arch only unless you lipo universal binaries. Ad-hoc codesign is applied by the package script; notarization optional.

**Notarization** needs an Apple ID / Developer Program and is **optional**. Without it, users right-click the app → **Open** the first time. No Mac App Store submission.

Upload the `.dmg` (or `.zip`) to a GitHub Release.

---

## 3. Windows direct download (.exe + zip)

Must run on **Windows**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\package_release.ps1
```

- Portable zip: `dist/windows/DocumentStudio-<version>-portable-windows.zip`
- Installer: `dist/windows/DocumentStudio-<version>-Setup.exe` (needs [Inno Setup 6](https://jrsoftware.org/isinfo.php))

Engines are copied into `Release\engines\` by `bundle_windows_engines.ps1` (see **[ENGINES.md](ENGINES.md)** for URLs). LibreOffice is extracted from the official MSI into `engines/libreoffice` at build time (same idea as Linux).

No Microsoft Store packaging. Attach both files to a GitHub Release.

---

## 4. Linux direct download (.deb + AppImage)

Install for the current user (qpdf and tesseract already inside the app; LibreOffice stays the system `soffice`):

```bash
bash scripts/linux/install_local.sh
```

qpdf lands at `~/.local/lib/document-studio/engines/qpdf`. See **[ENGINES.md](ENGINES.md)**.

To build a `.deb` / AppImage (this machine or Ubuntu CI), after `flutter build linux --release`:

```bash
bash scripts/linux/package_deb.sh
bash scripts/linux/package_appimage.sh
```

Artifacts: `dist/linux/document-studio_<ver>_<arch>.deb` and AppImage (or AppDir tarball if `appimagetool` is missing).

**Flathub (optional, later):** free if you have a public GitHub repo; submit a Flatpak manifest when you want distro-store discoverability. Not required for v1 — ship `.deb` + AppImage on GitHub Releases first.

**Engines:** `.deb` and AppImage must include `engines/` (qpdf, tesseract+tessdata, signing tools, ffmpeg). LibreOffice is the system `soffice`, not a bundled download. See **[ENGINES.md](ENGINES.md)**. Packaging refuses to ship without qpdf and tesseract.

---

## GitHub Actions

Workflow: `.github/workflows/release.yml` (manual dispatch or `v*` tags).

| Job | Runner | Artifact |
| --- | --- | --- |
| `linux` | ubuntu | `.deb` + AppImage/AppDir |
| `android` | ubuntu | AAB (Play-signed only if keystore secrets exist) |
| `windows` | windows | portable zip (+ Setup.exe if Inno is on the runner) |
| `macos` | macos | `.dmg` + `.zip` |

Download artifacts from the Actions run, then attach them to a GitHub Release.

---

## Checklist — what you must do

1. **Create & back up** `android/upload-keystore.jks` + `android/key.properties`.
2. **Play Console:** create the app, fill listing from `docs/store/play/`, content rating, Data safety, **privacy policy URL** (host a page; outline is in `docs/store/play/privacy-outline.md`).
3. **Screenshots** per `docs/store/play/screenshots.md`.
4. **Build & upload AAB** to Internal testing, then Production (`make appbundle`).
5. On a **Mac:** build `.dmg` → upload to GitHub Releases.
6. On a **Windows PC:** build Setup `.exe` + portable zip → upload to GitHub Releases.
7. On **Linux / CI:** build `.deb` + AppImage → upload to GitHub Releases.
8. Bump `version:` in `pubspec.yaml` for every store / release upload.
