# Building from source

Requirements depend on the target OS: Flutter stable, platform desktop/mobile toolchains, and (for full desktop bundles) network access to fetch engines during the packaging scripts.

```bash
git clone https://github.com/tejashvi-kumawat/DocumentStudio.git
cd DocumentStudio
flutter pub get
```

## Run (dev)

```bash
flutter run -d windows   # or linux / macos / chrome / android
```

## Package (examples)

| Target | Entry script |
| --- | --- |
| Windows installer | `scripts/windows/package_release.ps1` |
| macOS DMG | `scripts/macos/package_release.sh` |
| Linux deb | `scripts/linux/package_deb.sh` |

CI workflows exist under `.github/workflows/` and are currently **manual** (`workflow_dispatch`) so routine pushes don’t burn Actions minutes.

## Notes

- Engine bundling downloads large dependencies (LibreOffice especially). University mirrors are preferred when Document Foundation CDN times out.
- Do not commit secrets, keystores, or `dist/` outputs.
