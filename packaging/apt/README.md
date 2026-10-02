# Debian / apt distribution

## Phase 1 — GitHub Release `.deb` (available now)

Build on Linux:

```bash
flutter build linux --release
bash scripts/linux/package_deb.sh
```

Upload `dist/linux/document-studio_<version>_amd64.deb` to tag `v<version>`.

Users install with:

```bash
wget https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.0.3/document-studio_1.0.3_amd64.deb
sudo apt install ./document-studio_1.0.3_amd64.deb
```

GNOME Software / KDE Discover can install the same file with a GUI.

## Phase 2 — `sudo apt install document-studio` (custom repository)

To avoid `./file.deb` paths, host a **signed apt repository**:

1. Build `.deb` artifacts per release.
2. Use `reprepro` or `aptly` to publish `dists/` + `pool/` on GitHub Pages or object storage.
3. Ship `packaging/apt/document-studio.sources` (deb822) pointing at that URL.

Example sources snippet (replace URL when repo is live):

```deb822
Types: deb
URIs: https://tejashvi-kumawat.github.io/document-studio-apt
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/document-studio-archive-keyring.gpg
```

This is optional infrastructure; Flathub (`flatpak install flathub com.documentstudio.document_studio`) is often easier for “install from a store” on Linux.

## Phase 3 — Official Debian / Ubuntu archives

Requires sponsorship and months of review; not required for most indie apps.
