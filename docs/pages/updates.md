# Updates

Keep Document Studio current without a full manual reinstall when possible.

## CLI (all desktop builds)

```bash
document_studio --version
document_studio --check-update
document_studio --update
```

`--update` prefers the channel you already used (**winget**, **Homebrew**, **Flatpak**), otherwise downloads the matching GitHub Release asset and upgrades **in place**.

## Package managers

| Channel | Command |
| --- | --- |
| winget | `winget upgrade --id DocumentStudio.DocumentStudio` |
| Homebrew (macOS) | `brew upgrade --cask document-studio` |
| Homebrew (Linux) | `brew upgrade document-studio` |
| Debian package | `sudo apt install ./document-studio_<ver>_amd64.deb` |

## Direct download

Install the newer **Setup.exe** / **.dmg** / **.deb** from [Releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases). Windows Setup uses the same app id so it replaces the previous install folder.
