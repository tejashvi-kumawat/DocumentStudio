# Keyboard shortcuts (`DS-SHELL-003`)

Document Studio desktop shortcuts use **Ctrl** on Linux/Windows and **⌘ (Meta)** on macOS unless noted.

## Global (app root)

Registered in `lib/app/keyboard/app_shortcuts.dart` via [AppShortcuts] at the app root (`DocumentStudioApp`).

| Shortcut | Action |
| --- | --- |
| Ctrl/⌘ O | Open PDF (file picker from Home flow) |
| Ctrl/⌘ P | Print active document when the PDF viewer has registered a print handler |
| Ctrl/⌘ F | Find in document when the viewer has registered find |
| Ctrl/⌘ K | Command palette (tools, workspace, home) |

[AppShortcuts]: ../lib/app/keyboard/app_shortcuts.dart

## App shell tabs (`DsAppShell`)

Home, Tools, and Settings live under nested branch navigators. **Ctrl/⌘ K** is duplicated on the shell via `DsShellKeyboardScope` so the command palette opens without requiring root focus. Open / print / find still use the root scope.

Implementation: `lib/app/keyboard/ds_shell_keyboard_scope.dart`, `lib/design_system/shell/ds_app_shell.dart`.

## Document workspace (`/workspace`)

| Shortcut | Action |
| --- | --- |
| Ctrl/⌘ Z | Undo page edits |
| Ctrl/⌘ Y | Redo |
| Ctrl/⌘ S | Export workspace PDF |
| Ctrl/⌘ K | Command palette (workspace actions + global entries) |

## PDF viewer

Page navigation (`DS-READ-009-C`): PgUp/PgDn, Home/End, arrow keys — see `lib/features/pdf_viewer/pdf_viewer_page_shortcuts.dart`.

| Shortcut | Action |
| --- | --- |
| Ctrl/⌘ F | Toggle **Find in document** bar (inline search, prev/next match) |
| Ctrl/⌘ C | Copy selected text (when text selection is active) |

Toolbar **File** menu: workspace, print, export/compress, markup (headers, watermark, page numbers), protect/unlock, metadata.

Toolbar **Tools** menu: find, bookmarks, copy/select-all, organize tools (split, extract, …) on the open document.

| Shortcut | Action |
| --- | --- |
| Escape | Exit **presentation mode** when active |

**View** menu: page layout (**Continuous**, **Single page**, **Two page** spread on wide layouts).

Additional viewer shortcuts are documented in [DS-READ-PDF-VIEWER](../features/DS-READ-PDF-VIEWER.md).

## Command palette (`DS-SHELL-002` partial)

- **Shortcut:** Ctrl/⌘ K (global + shell + workspace).
- **Contents:** Organize tool routes from `OrganizeToolCatalog`, navigation to workspace / organize hub / home; workspace adds “Add PDF” and “Export workspace” when on `/workspace`.
- **UI:** `lib/features/command_palette/ds_command_palette.dart`.

## Platform notes

- Shortcuts are intended for desktop; mobile/tablet rely on touch chrome.
- Text fields and pdfrx canvas may consume keys first; viewer page shortcuts use pdfrx `onKey` where applicable.
- Full platform-specific maps and missing shortcuts (e.g. Ctrl+Shift+S save as) remain **partial** until `DS-SHELL-003` exit gate.

## Related docs

- [UI-UX.md](UI-UX.md) — navigation and desktop interaction overview
- [MASTER-SPECIFICATION.md](MASTER-SPECIFICATION.md) — `DS-SHELL-003` inventory row
