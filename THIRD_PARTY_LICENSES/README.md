# Third-party licenses (Document Studio)

This directory contains **complete license texts** and **component-specific notices**
for software that Document Studio **bundles** (standalone executables/libraries in
`engines/`) or **invokes as external processes**, separate from the proprietary
application code in `LICENSE`.

Release packaging copies this tree to **`engines/THIRD_PARTY_LICENSES/`** inside
desktop installers (Windows Inno, Linux `.deb`, macOS `.app`).

| Document | Purpose |
| --- | --- |
| [BUNDLED_COMPONENTS.md](BUNDLED_COMPONENTS.md) | Version pins, license summary, distribution mode, obligations |
| [../docs/CORRESPONDING_SOURCE.md](../docs/CORRESPONDING_SOURCE.md) | GPL / corresponding-source offers |
| [Apache-2.0.txt](Apache-2.0.txt) | Full Apache License 2.0 text |
| [GPL-2.0-or-later.txt](GPL-2.0-or-later.txt) | Full GPL v2 text (Poppler tools when bundled) |
| [MPL-2.0.txt](MPL-2.0.txt) | Full Mozilla Public License 2.0 text |
| [BSD-2-Clause.txt](BSD-2-Clause.txt) | BSD 2-Clause (e.g. Leptonica) |
| [components/](components/) | Per-component NOTICE / attribution / uncertainty notes |

Do **not** treat Document Studio's proprietary `LICENSE` as applying to these works.
