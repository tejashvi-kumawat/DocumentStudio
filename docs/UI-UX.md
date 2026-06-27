# UI / UX — Document Studio

## Product feel

One application: **Home → Document workspace → Tools → Export**. Tools are not separate “mini apps” with different navigation paradigms—they share the shell and design system.

## Navigation model

| Area | Phone | Tablet | Desktop |
| --- | --- | --- | --- |
| Library / recents | Home tab | Home rail item | Sidebar top |
| Tools catalog | Tools tab | Tools rail | Sidebar section |
| Active document | Full screen | Split master/detail | Center workspace |
| Properties / queue | Sheet | Side panel | Right inspector |
| Settings | Tab | Rail | Sidebar bottom |

## Document workspace

Shared structure:

1. **Top bar:** document title, save/share, search toggle
2. **Canvas:** PDF viewer or organize grid
3. **Page strip:** horizontal thumbs (collapsible on phone)
4. **Tool context bar:** mode-specific (annotate, organize, etc.)
5. **Inspector (desktop/tablet):** metadata, security, job output

## Tool flows

Standard pattern:

1. Entry from Tools or document menu
2. Input selection (pre-filled if from open doc)
3. Options screen with defaults
4. Run → progress
5. Result: open output, show in folder, share

Destructive or lossy steps use **DsDialog** confirm.

## Mobile gestures (reader)

- Pinch zoom; double-tap fit width
- Swipe horizontal optional (single-page mode)
- Long press: selection / context menu

## Desktop interactions

See **[KEYBOARD-SHORTCUTS.md](KEYBOARD-SHORTCUTS.md)** for the current shortcut map (`DS-SHELL-003` partial).

- Ctrl/⌘ O open, Ctrl/⌘ F find, Ctrl/⌘ P print (viewer when wired), Ctrl/⌘ K command palette
- Ctrl+Shift+S save as — planned; not wired globally yet
- Drag-drop files onto window opens or offers tool choice
- Command palette (`DS-SHELL-002` partial): organize tools + navigation + compress/create/images routes; rail/Home discoverability; fuzzy ranking not implemented

## Product craft

Apple-inspired **behavior** (see [DESIGN-SYSTEM.md](DESIGN-SYSTEM.md) for tokens):

| Principle | Implementation |
| --- | --- |
| Clear next step | Home empty recents show **Open PDF** + **Create PDF**; tool cards show document-entry badges (**Requires open PDF**, **Pick file**, **Works standalone**). |
| Acrobat-like open paths | Home open chooser explains **View** (reader) vs **Edit pages** (workspace grid) before routing. |
| Calm loading | Viewer shows skeleton + progress while open validation runs — not a bare spinner. |
| Recoverable errors | Viewer open failures offer **Try another file**, **Unlock** (password or unlock tool), and **Go back**. |
| Tool form rhythm | `DsToolStickyActionBar` — primary **Export / Save / Apply** fixed to the bottom; **Cancel** returns via `handleDsToolFormCancel` (viewer when launched from a document). |
| No lost handoffs | `shellNavigationContextProvider` keeps the active PDF when switching **Home ↔ Tools**; viewer launches remember return context. |

## Empty & error states

| State | Copy direction |
| --- | --- |
| No recents | “Open a file or scan a document” |
| Permission denied | Link to system settings / pick again |
| Corrupt PDF | “This file could not be read” + try repair (Phase 10) |
| Tool unavailable on platform | “Available on desktop” |

## Privacy dashboard (Settings)

Static rows with green checkmarks (no network call):

- Document upload: off
- Cloud processing: off
- Local processing: on
- Strict offline mode: toggle

## Fidelity messaging (conversion)

Show **Fidelity class** badge (A–D) from [MASTER-SPECIFICATION.md](MASTER-SPECIFICATION.md) §15.1 before running Office or PDF→Word tools.

## Batch UI (Phase 11)

Table: file name, status, output, error; “Continue on error” checkbox in options.
