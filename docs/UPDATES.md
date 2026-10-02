# Updates (CLI, in place)

Users should be able to upgrade without reinstalling from scratch. Prefer the channel they already used.

## End-user commands

| How they installed | Upgrade (in place) |
| --- | --- |
| Any desktop build with CLI | `document_studio --update` |
| Check only | `document_studio --check-update` |
| winget | `winget upgrade --id DocumentStudio.DocumentStudio` |
| Homebrew | `brew upgrade --cask document-studio` |
| Flatpak | `flatpak update com.documentstudio.document_studio` |
| `.deb` (direct) | `sudo apt install ./document-studio_<ver>_amd64.deb` |
| Scripts (no PATH binary) | `bash scripts/update/update_inplace.sh` / `powershell -File scripts\update\update_inplace.ps1` |

`--update` order:

1. Compare installed version to **GitHub Releases** `latest`.
2. If a package manager owns the install (**winget** / **brew cask** / **flatpak**), use that.
3. Else download the platform asset and replace **in place**:
   - **Windows:** silent Inno Setup (`/VERYSILENT` + `/CLOSEAPPLICATIONS`) over the same `AppId` / install dir.
   - **macOS:** mount DMG, replace `/Applications/Document Studio.app`.
   - **Linux:** `apt install` / `dpkg -i` the new `.deb`.

## Version string

- Marketing version: `lib/app/app_version.dart` (`kAppVersion`) and `pubspec.yaml` (before `+`).
- Optional release override: `--dart-define=APP_VERSION=1.0.4` on `flutter build`.

## Maintainer notes

- Windows Inno uses `CloseApplications=yes` and a fixed `AppId` so upgrades overwrite the same folder.
- Homebrew / winget listings must point at the same GitHub Release assets.
- See [HOMEBREW.md](HOMEBREW.md) and [PACKAGE-MANAGERS.md](PACKAGE-MANAGERS.md).
