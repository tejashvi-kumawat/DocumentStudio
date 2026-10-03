# Quick start

## 1. Install the app

Follow [Download & install](#/install) for your OS. Prefer the GUI installer / DMG / `.deb` so the app shows up in system search.

## 2. Open Document Studio

- **Windows:** Start → Document Studio  
- **macOS:** Spotlight → Document Studio  
- **Linux:** Activities → Document Studio  

## 3. Open a file

- Use **Open** / drag-and-drop a PDF or images onto the window  
- Or from a terminal: `document_studio ~/Documents/file.pdf`  
- Or right-click a PDF → **Open with Document Studio** (after Setup / `.deb`)

## 4. Run a tool

From the home tools grid, the PDF viewer ribbon, or the organize workspace:

1. Pick a tool (e.g. **Compress**, **Merge**, **Encrypt**, **Searchable PDF**).  
2. Adjust options in the panel.  
3. Run the job and wait for progress.  
4. Choose where to **save/export** the result.

Nothing is uploaded. Outputs stay on disk where you save them.

## 5. Everyday recipes

| I want to… | Do this |
| --- | --- |
| Combine 3 PDFs | **Merge** → add files in order → export |
| Shrink a scan | Open PDF → **Compress** → pick quality → export |
| Lock a file | **Encrypt** → set password → export |
| Unlock (I know the password) | **Decrypt** → enter password → export |
| Make a scan searchable | **Searchable PDF** / OCR → export |
| Word → PDF | Desktop → **Office convert** → pick `.docx` → export PDF |
| Photos → PDF | **Images to PDF** → order pages → export |

Detailed steps: [How to use tools](#/how-to).

## 6. Keep updated

```bash
document_studio --update
```

Or reinstall the newer Setup / DMG / deb from Releases.
