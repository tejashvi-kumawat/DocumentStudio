# File System — Document Studio

## FileStoragePort

Single abstraction for all platforms:

| Method | Purpose |
| --- | --- |
| `resolveToLocalPath(DocumentRef)` | Path or temp copy from URI |
| `pickOpenFiles(filter)` | Native picker |
| `pickSaveLocation(suggestedName)` | Save dialog |
| `writeAtomic(path, bytes\|stream)` | `.partial` then rename |
| `createJobTempDir()` | Per-job workspace |
| `deleteRecursively(temp)` | Cleanup |

## Android

- Prefer **SAF** URIs from `file_picker`
- Take persistable permission when user picks; store URI + display name in recents
- Copy to temp for engines that need `File` path if unavoidable—delete after job
- `android_file_picker` / `FilePicker` androidOptions

## iOS / iPadOS

- Security-scoped URLs from document picker
- Start/stop access around read/write
- Optional bookmark storage for recents (ADR when implementing)

## Desktop

- Direct paths from native pickers
- Drag-drop: validate extension → open or route to tool
- Watch for file lock (Word open) → `PERMISSION_DENIED`

## Atomic write

```
write path.partial
fsync if available
rename path.partial → path
```

On failure: leave original; delete partial.

## Recents / favorites

Local SQLite or preferences only:

- Display name, last opened, URI/path reference
- **No** cloud sync

## Overwrite policy

Default **Save As**. Replace original requires checkbox + confirmation dialog.

## Temp disk space

Pre-flight check available space > input size × factor before large merge/OCR.
