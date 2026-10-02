# Corresponding source (copyleft components)

Document Studio may **redistribute binaries** of third-party programs that are
licensed under **GPL** or similar copyleft terms when those programs are **bundled
as separate executables** invoked by the app (not linked into the Flutter binary).

This document describes how recipients can obtain **corresponding source** for those
components. It does **not** constitute legal advice.

## Components that may trigger source-offer obligations

| Component | When bundled | Upstream source |
| --- | --- | --- |
| **Poppler** (`pdfsig`, `libpoppler` via poppler-utils on Linux) | Windows: optional `pdfsig.exe` from [poppler-windows](https://github.com/oschwartz10612/poppler-windows); Linux: Ubuntu `poppler-utils` debs | https://poppler.freedesktop.org/ — https://gitlab.freedesktop.org/poppler/poppler |
| **FFmpeg** (`ffmpeg.exe` / distro package) | Windows: [gyan.dev essentials build](https://www.gyan.dev/ffmpeg/builds/); Linux: Ubuntu `ffmpeg` debs | https://ffmpeg.org/download.html — exact configure flags **not verified by this repo** (see `THIRD_PARTY_LICENSES/components/FFMPEG-NOTICE.md`) |
| **LibreOffice** | Official MSI/DMG/tarball extracted into `engines/` | https://www.libreoffice.org/download/source-code/ — version pinned in `bundled-versions.json` |

## Offer mechanism (project)

1. **GitHub repository:** https://github.com/tejashvi-kumawat/DocumentStudio  
   Tag matching the release (e.g. `v1.0.3`) identifies the packaging scripts and
   version pins used to produce that installer.

2. **`engines/THIRD_PARTY_LICENSES/bundled-versions.json`** inside the installed
   application lists pinned versions and download URLs used at build time.

3. **Written request:** For GPL-corresponding source of a specific bundled
   binary version, contact the address in `PRIVACY.md` / release maintainer with
   the Document Studio version and platform. We will provide upstream source URLs
   or a written offer to supply source per the applicable license, **to the extent
   required** for that component.

## Not covered here

- **qpdf, Tesseract, OpenSSL, NSS (MPL), PDFium** — permissive licenses; see
  `THIRD_PARTY_LICENSES/` for notices. No GPL corresponding-source offer required
  for typical Apache/BSD/MPL distribution of unmodified binaries.
- **Flutter / Dart SDK** — see https://github.com/flutter/flutter and
  https://github.com/dart-lang/sdk

## Uncertainty

Whether a given **FFmpeg** or **Poppler** build is GPL-only, LGPL, or mixed
depends on **upstream build configuration**. Document Studio does not rebuild
these from source in-repo; license classification should be confirmed from the
binary (`ffmpeg -version`, package metadata) before claiming a specific license
variant.
