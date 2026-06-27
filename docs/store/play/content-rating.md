# Google Play — content rating & Data safety notes

## Content rating (IARC questionnaire)

Document Studio is a **productivity / utility** app. Expected answers for a typical questionnaire:

| Topic | Guidance |
| --- | --- |
| Violence / weapons / sexual content | No |
| User-generated content shared with others | No (local files only; share sheet is user-initiated OS export) |
| Location / unrestricted web | No unrestricted social; optional network only for explicit downloads if enabled |
| Age | Suitable for **Everyone** / PEGI 3-style utility |

Complete the official questionnaire in Play Console — do not guess final ratings; the tool assigns them.

## Data safety form (outline)

Declare honestly in Console:

| Data type | Collected? | Shared? | Notes |
| --- | --- | --- | --- |
| Files / docs user opens | Processed **on device** | No (unless user uses OS Share) | Not uploaded to your servers |
| Personal info / account | No | — | No account |
| Location | No | — | |
| App activity / analytics | No by default | — | See `docs/PRIVACY.md` |
| Crash logs | No by default | — | |

**Encryption in transit:** N/A for core offline work.  
**Deletion:** Users delete local files / clear app data / uninstall.

Link your hosted **privacy policy URL** in both Store listing and Data safety.
