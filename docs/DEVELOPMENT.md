| `make test-changed` | Tests for paths changed vs `main` (when git available) |
| `make install-engines` | Linux: `apt` install **qpdf** + **tesseract-ocr** via [scripts/install_desktop_engines.sh](../scripts/install_desktop_engines.sh) |

The Flutter Linux build runs [scripts/bundle_linux_engines.sh](../scripts/bundle_linux_engines.sh) during `cmake install` (invoked by `flutter build linux`). That copies **qpdf** (from PATH or `.tools/qpdf`) and **tesseract** (when present) into the bundle’s `engines/` folder. The running app resolves engines next to the binary, then `engines/`, then PATH — so a normal debug build should not depend on remembering `make install-engines`.

`make install-engines` remains a system-wide fallback for hosts without a portable `.tools/qpdf` and without network to download one.

Implementation: [scripts/test_changed.sh](../scripts/test_changed.sh).