# Google Play — screenshot & graphic checklist

Capture from a release or staging build. Prefer real UI, not mockups.

## Phone (required)

- [ ] **Home / tool grid** — first impression of Document Studio
- [ ] **PDF viewer** with a sample document
- [ ] **Organize** flow (merge / page thumbnails) — at least one
- [ ] **OCR or compress** result screen — at least one
- [ ] **Sign / annotate** — at least one

Play typically wants **2–8** phone screenshots. Use a clean device frame or raw captures; avoid cluttered status bars with personal notifications.

## 7-inch / 10-inch tablet (recommended)

- [ ] Same flows on tablet layout (if you support larger screens)

## Feature graphic (required for Play)

- [ ] **1024 × 500** promo graphic with app name + short value line (“Offline PDF tools”)
- Use brand assets under `assets/brand/` as a starting point

## App icon

- [ ] High-res icon (Play generates store sizes from the uploaded icon / Adaptive Icon)
- Replace default Flutter launcher mipmaps with the Document Studio logo before production

## Tips

- Do not show personal documents or real signatures of other people
- Keep text large enough to read in the store thumbnail strip
- Match the short description messaging: offline, privacy-first, no account
