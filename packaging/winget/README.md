# WinGet (Windows Package Manager)

Package: **`DocumentStudio.DocumentStudio`** — this identifier never changes.
Installer: the Inno Setup `DocumentStudio-<version>-Setup.exe` asset of the
GitHub Release (user scope, x64). Nothing else is hosted: WinGet downloads the
installer straight from GitHub Releases.

Manifests live under `manifests/d/DocumentStudio/DocumentStudio/<version>/`,
the same path they take in `microsoft/winget-pkgs`.

## First submission (one time)

1. On Windows, validate and test the manifest:
   `powershell -ExecutionPolicy Bypass -File packaging\winget\test_manifest.ps1 -Version 1.2.0`
2. Fork https://github.com/microsoft/winget-pkgs, then in the fork:
   ```
   git checkout -b add-documentstudio-1.2.0
   mkdir -p manifests/d/DocumentStudio/DocumentStudio/1.2.0
   cp <this repo>/packaging/winget/manifests/d/DocumentStudio/DocumentStudio/1.2.0/* manifests/d/DocumentStudio/DocumentStudio/1.2.0/
   git add manifests/d/DocumentStudio/DocumentStudio/1.2.0
   git commit -m "New package: DocumentStudio.DocumentStudio version 1.2.0"
   git push origin add-documentstudio-1.2.0
   ```
3. Open a PR to `microsoft/winget-pkgs:master` titled
   `New package: DocumentStudio.DocumentStudio version 1.2.0` and follow the
   bot's validation results. The package is on WinGet only once merged.

## Every new release

GitHub Release → new version → new installer URL → new SHA256 → new version
manifest → PR to microsoft/winget-pkgs → validation → merge.

Easiest, on Windows (wingetcreate fills URL, SHA256 and ProductCode):
```
winget install Microsoft.WingetCreate
wingetcreate update DocumentStudio.DocumentStudio --version 1.0.4 ^
  --urls https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.0.4/DocumentStudio-1.0.4-Setup.exe ^
  --submit
```
Or by hand: copy the previous version folder to the new version, change
`PackageVersion`, `InstallerUrl`, `InstallerSha256` (`sha256sum` of the
released .exe, or the `digest` GitHub shows for the asset), `ReleaseDate`
and `ReleaseNotesUrl`, then PR as above.

Users update with `winget upgrade DocumentStudio.DocumentStudio`, or from
inside the app (Settings → Updates), which uses the same release asset.
