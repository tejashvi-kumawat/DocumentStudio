# Design System — Document Studio

Professional utility aesthetic—not a generic Flutter demo. Tokens below are v0; refine when UI implementation starts.

## Principles

- Clarity over decoration; dense desktop layouts, touch-friendly 48dp targets on mobile.
- One component library in `lib/design_system/`; features consume tokens only.
- Light / dark / system via `ThemeData` extensions.

## Color tokens

| Token | Light | Dark | Usage |
| --- | --- | --- | --- |
| `primary` | `#2563EB` | `#3B82F6` | Primary actions, “Studio” accent |
| `onPrimary` | `#FFFFFF` | `#FFFFFF` | Text on primary |
| `surface` | `#FFFFFF` | `#0F172A` | Main background |
| `surfaceContainer` | `#F8FAFC` | `#1E293B` | Cards, sidebars |
| `textPrimary` | `#0F172A` | `#F1F5F9` | Headings, body |
| `textSecondary` | `#64748B` | `#A8B4C8` | Hints, metadata (dark lifted for AA on grouped surfaces) |
| `groupedBackground` | `#F2F4F8` | `#0B1220` | Home / settings backdrop (iOS Settings) |
| `groupedCell` | `#FFFFFF` | `#1E293B` | Inset grouped lists, hero cards |
| `border` | `#E2E8F0` | `#334155` | Dividers |
| `success` | `#059669` | `#34D399` | Saved space, done |
| `warning` | `#D97706` | `#FBBF24` | Lossy compress, caution |
| `error` | `#DC2626` | `#F87171` | Failures |

Brand icon accents (document stack): red `#EF4444`, amber `#F59E0B`, blue `#2563EB` — use sparingly in logo/splash only.

## Typography

| Role | Desktop | Mobile |
| --- | --- | --- |
| Display | 28sp semibold | 24sp semibold |
| Title | 20sp semibold | 18sp semibold |
| Body | 14sp regular | 16sp regular |
| Label | 12sp medium | 12sp medium |
| Mono | 12sp monospace | paths in debug only |

Font family: platform default (`Roboto`, `SF Pro`, `Segoe UI`).

## Spacing

Base unit **4dp**. Scale: 4, 8, 12, 16, 24, 32, 48.

## Radius & elevation

- Buttons/inputs: 8dp (`DsSpacing.radiusButton`)
- Grouped lists / tool grids: 10dp (`DsSpacing.radiusGrouped`)
- Cards/dialogs: 12dp (`DsSpacing.radiusCard`)
- Hero / modals: 14dp (`DsSpacing.radiusHero`, `radiusDialog`)
- Light-mode cards: single soft shadow (`DsSpacing.cardShadowLight`); dark flat + hairline border

## Apple-inspired patterns (v0.1)

- **Inset grouped lists** — recents/favorites on `groupedBackground` with elevated `groupedCell` rows (Settings-style).
- **Hero open card** — primary CTA + calm gradient surface on Home.
- **Segmented toolbar controls** — macOS-style fit width/page and scroll layout clusters in the PDF viewer (`DsToolbarSegmentedControl`).
- **Shell fade** — 220ms opacity when switching rail destinations (`DsAppShell` + `DsMotion.shellDuration`).
- **Modal motion** — fade + 0.96 scale for choosers (`DsMotion.fadeScaleTransition`).

## App shell layout

Shell tab pages (**Home**, **Tools**, **Settings**) share one chrome scaffold inside [DsAppShell](lib/design_system/shell/ds_app_shell.dart):

| Piece | Role |
| --- | --- |
| `DsShellPageFrame` | Centers content, `DsSpacing.contentMaxWidth` (960dp), horizontal `lg` inset |
| `DsShellPageHeader` | Page title + subtitle (brand block on narrow / collapsed rail) |
| `DsSectionHeader` | In-page sections (Recents, Favorites, tool categories) |
| `dsShellContentHorizontalPadding` | Aligns full-bleed grouped lists with the content column |
| `DsSpacing.shellSectionGap` / `shellPageBottom` | Vertical rhythm between sections and scroll bottom |

Tool grids use a shared minimum cell height so badges and trailing labels align across columns. Controls stack below **480dp** width to avoid overflow.

### Home layout

Home uses a **three-zone** desktop layout inside the shell content column (not a single long form):

| Zone | Role |
| --- | --- |
| In-page left nav (≥720dp) | Search, **Recent**, **Starred**, **Your documents** — switches the document panel filter |
| Center | Calm hero (“What would you like to work on?”) with **Open PDF** / **Create PDF**, then **Suggested tools** icon tiles |
| Right document panel (≥1100dp) | Grouped recent/starred list with sort; stacks below center on narrower widths |

**Tools** tab uses search + large **Open** tool cards in a grid (featured workflows), with the full categorized catalog beneath when not searching.

## Components (implement once)

**Implemented (lib/design_system/):** `DsTheme`, `DsTypography`, `DsSectionHeader`, `DsToolCard`, `DsDocumentAppBar`, `DsAppShell`, `DsShellPageFrame`, `DsShellPageHeader`, `DsToolFormLayout`, `DsToolPanel`, `DsToolbar`, `DsPrimaryButton`, `DsSecondaryButton`, `DsEmptyState`.

**Planned:** `DsGhostButton`, `DsDestructiveButton`, `DsTextField`, `DsDropdown`, `DsDialog`, `DsBottomSheet`, `DsSidePanel`, `DsToolbar`, `DsPageThumbnail`, `DsDocumentTab`, `DsProgressBlock`, `DsToast`, `DsErrorState`.

## Icons

Material Symbols Outlined; size 24 default, 20 in dense toolbar.

## Motion

- Switch / list updates: 180ms `easeOutCubic` (`DsMotion.switchDuration`)
- Shell destination change: 220ms fade (`DsMotion.shellDuration`)
- Dialog / chooser: 240ms fade + scale (`DsMotion.dialogDuration`, `dialogScaleBegin` 0.96)
- Avoid heavy animation on low-end devices during PDF scroll

## Accessibility

- Minimum contrast WCAG AA for text on surfaces
- Semantics labels on icon-only tools
- Focus order: sidebar → canvas → inspector on desktop

See [UI-UX.md](UI-UX.md) for layout shells.
