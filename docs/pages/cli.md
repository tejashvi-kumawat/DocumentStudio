# CLI & Windows shell

## Commands

```bash
document_studio --help
document_studio --version
document_studio --check-update
document_studio --update
document_studio path/to/file.pdf
document_studio --tool compress path/to/file.pdf
document_studio --tool merge a.pdf b.pdf
```

On Linux the hyphenated launcher `document-studio` is also installed (same app).

## Open a file from the terminal

```bash
document_studio ~/Documents/report.pdf
```

The GUI opens on that file when the desktop session is available.

## Tool shortcuts

`--tool` jumps into a specific workflow when supported (for example compress or merge). Prefer the GUI for complex options; use CLI when scripting a known job.

## Windows shell integration

The full **Setup.exe** registers:

| Integration | What you get |
| --- | --- |
| Start Menu | Searchable **Document Studio** shortcut |
| App Paths | `document_studio` resolves in PowerShell / cmd |
| Open with | PDF / images |
| Classic context menu | Right-click verbs after install |
| Win11 modern menu | Sparse package registration when it succeeds |

Portable zip users can run the included register scripts if they skip the installer — but Setup.exe is strongly recommended.

## “Why isn’t it in Start / Spotlight / Activities?”

You need a real desktop install (Setup / DMG / `.deb`), not only a loose binary. Search for **“Document Studio”** with a space. Details: [FAQ](#/faq) · [Install](#/install).
