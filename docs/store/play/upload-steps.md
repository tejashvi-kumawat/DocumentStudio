# Google Play Console — upload steps

Exact path after the listing drafts in this folder are ready.

## Prerequisites

- [ ] Developer account (you have this)
- [ ] `android/key.properties` + `upload-keystore.jks` created and backed up
- [ ] Privacy policy **URL** live on the web
- [ ] Screenshots + feature graphic ready
- [ ] `pubspec.yaml` version bumped for this release (`1.0.0+1` → next)

## Build

```bash
make appbundle
# → build/app/outputs/bundle/release/app-release.aab
```

## First app setup

1. Play Console → **Create app**
2. App name: **Document Studio**
3. Complete Dashboard tasks: store listing, graphics, categorization, privacy policy, content rating, target audience, News apps declaration (No), Data safety
4. Paste copy from [`listing.md`](listing.md), rating notes from [`content-rating.md`](content-rating.md)

## Internal testing (do this before Production)

1. **Testing → Internal testing → Create new release**
2. Upload `app-release.aab`
3. Release name e.g. `1.0.0 (1)` matching pubspec
4. Save → Review → **Start rollout to Internal testing**
5. Add your Google account on **Testers** tab
6. Install from the internal testing link; verify open PDF, one tool, share/export

## Production

1. From the tested release: **Promote release** → Production  
   — or create a new Production release with the same / newer AAB
2. Answer any final declarations
3. **Start rollout to Production** (can use staged % rollout)

## After each update

1. Bump `version:` in `pubspec.yaml` (especially the `+BUILD` integer)
2. `make appbundle`
3. New release on Internal testing → promote when happy

Do **not** lose the upload keystore. If you use Play App Signing (recommended default), keep your **upload** key safe; Google holds the app signing key.
