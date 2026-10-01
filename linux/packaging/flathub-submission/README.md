# Flathub submission — Document Studio

App ID: `com.documentstudio.document_studio`

Prepared files live in `com.documentstudio.document_studio/` (manifest, metainfo, desktop, wrapper). They match the local Flatpak packaging under `linux/packaging/flatpak/`.

## Manual PR steps (do this on GitHub — no `gh` from this machine)

1. Open https://github.com/flathub/flathub and click **Fork** (your account).
2. Clone **your fork**, then create a branch from Flathub’s `new-pr` branch (not `master`):

```bash
git clone https://github.com/<YOUR_GITHUB_USER>/flathub.git
cd flathub
git remote add upstream https://github.com/flathub/flathub.git
git fetch upstream
git checkout -b add-com.documentstudio.document_studio upstream/new-pr
```

3. Copy the app directory into the repo root (same folder name as the app id):

```bash
cp -a /path/to/DocumentStudio/linux/packaging/flathub-submission/com.documentstudio.document_studio \
  ./com.documentstudio.document_studio
```

4. Edit `com.documentstudio.document_studio/com.documentstudio.document_studio.yml`: replace the local `type: dir` `AppDir` source with a public `type: archive` (or `file`) URL **and** its `sha256`. Flathub will not accept a dir source from this PC.
5. Commit and push the branch to **your fork**.
6. On GitHub, open a Pull Request:
   - **base repository:** `flathub/flathub`
   - **base branch:** `new-pr` (not `master`)
   - **compare:** your `add-com.documentstudio.document_studio` branch
   - **title:** `Add com.documentstudio.document_studio`

## Human blockers (still required before / during review)

- **Public tarball URL + sha256** of the Linux AppDir (or release archive). The local `type: dir` / `AppDir` source is for this machine only.
- **Screenshots** in the metainfo (`<screenshots>`) — Flathub expects them; none are included here.
- **Proof of `documentstudio.com`** (or Flathub domain verification) if reviewers reject the reverse-DNS id `com.documentstudio.document_studio`.
- **Replace `[your email]` in `PRIVACY.md`** (and keep LICENSE/TERMS contact details accurate) before pointing Flathub at those URLs or shipping privacy claims.

## Local verification already done on this PC

- Built/installed from existing `dist/linux/DocumentStudio.AppDir` (no Flutter rebuild).
- `flatpak run com.documentstudio.document_studio` starts (Impeller).
- Manifest lint: `finish-args-home-filesystem-access` fixed by dropping `--filesystem=home`.
- Lint leftovers (need human / external assets):
  - `appid-url-not-reachable` — `https://documentstudio.com` timed out (domain proof / hosting).
  - Runtime update warning to `org.freedesktop.Platform` 26.08 (optional; info only).
  - AppStream: homepage/bugtracker GitHub URLs not reachable from this environment; screenshots still missing.
