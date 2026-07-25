| `make test-changed` | Tests for paths changed vs `main` (when git available) |
| `bash scripts/linux/package_deb.sh` | Build the `.deb` the user installs. qpdf, tesseract, and LibreOffice are inside that package. |
| `bash scripts/install_desktop_engines.sh` | Optional dev fallback: system **qpdf** + **tesseract-ocr** via apt. Not required after the install above. |

`linux/CMakeLists.txt` copies `.tools/linux-engines` into the bundle `engines/` folder (filled by [scripts/bundle_linux_engines.sh](../scripts/bundle_linux_engines.sh)). The running app resolves `engines/qpdf` before PATH. If that binary is missing in a dev run, Settings → Download qpdf fetches it once into app storage and does not block PDF viewing. Android does not install qpdf.

Implementation: [scripts/test_changed.sh](../scripts/test_changed.sh).