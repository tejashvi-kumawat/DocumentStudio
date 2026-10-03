# CLI & shell

## Commands

```bash
document_studio --help
document_studio --version
document_studio --check-update
document_studio --update
document_studio path/to/file.pdf
document_studio --tool compress path/to/file.pdf
```

On Linux the hyphenated launcher `document-studio` is also installed.

## Windows shell integration

The full **Setup.exe** registers:

- Start Menu shortcut  
- App Paths (so `document_studio` resolves)  
- Open with / classic context menu verbs for PDF and images  
- Optional Win11 modern context menu (sparse package) when registration succeeds  

Portable zip users can run the included register scripts if they skip the installer.

## “Open with” / file associations

Prefer installing via Setup / `.deb` / `.dmg` so the OS indexes Document Studio as a normal application. Terminal-only copies without desktop entries won’t appear in Start / Spotlight / Activities search.
