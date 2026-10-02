# Homebrew — publish Document Studio (macOS)

Goal: users run `brew install --cask document-studio` and later
`brew upgrade --cask document-studio`.

The **`.dmg` is built on GitHub Actions** (`macos-14`). You do **not** need a
local Mac for the first publish if CI is unlocked.

---

## 0. Unlock GitHub Actions (required)

Recent runs fail with:

> The job was not started because your account is locked due to a billing issue.

Fix that first or **no** workflow (Windows / macOS / Release) will run:

1. Open [GitHub Settings → Billing](https://github.com/settings/billing)
2. Clear the billing lock / update payment method / accept terms
3. Confirm Actions works: repo → **Actions** → green check on a workflow

Public repos get free Actions minutes (including `macos-14`). Billing lock still blocks everything.

---

## 1. Push the CI workflows + tag a release

From this repo (after merging the macOS CI changes to `main`/`master`):

```bash
# Bump version in pubspec.yaml AND lib/app/app_version.dart (same X.Y.Z)
git add -A && git commit -m "ci: build macOS DMG on GitHub Actions for Homebrew"
git push origin HEAD

git tag v1.0.3
git push origin v1.0.3
```

That triggers:

| Workflow | What it produces |
| --- | --- |
| **Release** | Windows + Linux + **macOS DMG/ZIP** → GitHub Release assets |
| **Build macOS DMG** | Same DMG (also on tag); usable alone via **Run workflow** |

Watch: https://github.com/tejashvi-kumawat/DocumentStudio/actions

When green, the release should list:

`DocumentStudio-1.0.3-macos.dmg`

### Manual DMG only (no tag)

Actions → **Build macOS DMG** → **Run workflow** → download the artifact from the run page (not yet on Releases unless you tagged).

---

## 2. Point the cask at that release

```bash
bash scripts/release/sync_homebrew_cask_from_release.sh 1.0.3
```

This downloads the DMG from the Release URL and sets `version` / `sha256` / `url` in:

`packaging/homebrew/Casks/document-studio.rb`

Commit that file in **this** repo so the template stays current.

---

## 3. Put it on Homebrew (pick A or B)

### A — Personal tap (do this first — minutes, not days)

1. Create a **public** GitHub repo named exactly:
   `https://github.com/tejashvi-kumawat/homebrew-tap`
2. Add file:
   `Casks/document-studio.rb`  
   (copy from `packaging/homebrew/Casks/document-studio.rb` in DocumentStudio)
3. Commit + push on the tap’s `main`.

Users install:

```bash
brew tap tejashvi-kumawat/tap
brew install --cask document-studio
```

Upgrade later:

```bash
brew update
brew upgrade --cask document-studio
# or:
document_studio --update
```

**Each new version:** tag → wait for CI DMG on Release → run `sync_homebrew_cask_from_release.sh` → copy updated rb into `homebrew-tap` → push tap.

### B — Official Homebrew Cask (wide reach, slower review)

Only after A works and Gatekeeper is acceptable (notarized preferred):

1. Fork [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask)
2. Add `Casks/d/document-studio.rb` (same content as your tap)
3. On a Mac:
   ```bash
   brew audit --cask --online document-studio
   brew style --fix --cask document-studio
   brew install --cask ./Casks/d/document-studio.rb
   ```
4. Open a PR. Docs: [Adding a cask](https://docs.brew.sh/Adding-Software-to-Homebrew#casks)

Later bumps:

```bash
brew bump-cask-pr document-studio --version 1.0.4
```

---

## 4. Verify

```bash
brew info --cask document-studio
brew install --cask document-studio
# open Document Studio.app, then:
brew upgrade --cask document-studio
```

CI DMG is **ad-hoc signed** (not Apple-notarized). First open may need:
**Finder → right-click app → Open → Open**. For official cask acceptance, plan Apple notarization later.

---

## Checklist

- [ ] GitHub billing / Actions unlocked
- [ ] Version bumped (`pubspec.yaml` + `app_version.dart`)
- [ ] `git tag vX.Y.Z && git push origin vX.Y.Z`
- [ ] Actions green; Release has `DocumentStudio-X.Y.Z-macos.dmg`
- [ ] `bash scripts/release/sync_homebrew_cask_from_release.sh X.Y.Z`
- [ ] Copy cask into `homebrew-tap` (or PR to homebrew-cask)
- [ ] `brew install --cask document-studio` works on a Mac

Template: [`packaging/homebrew/Casks/document-studio.rb`](../packaging/homebrew/Casks/document-studio.rb)
Workflows: [`.github/workflows/release.yml`](../.github/workflows/release.yml), [`.github/workflows/build-macos.yml`](../.github/workflows/build-macos.yml)
