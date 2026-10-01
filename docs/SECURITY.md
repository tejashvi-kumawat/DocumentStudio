# Security — Document Studio

Treat every imported file as **untrusted**.

## Threat summary

| Threat | Mitigation |
| --- | --- |
| Malformed PDF crash | Fuzzing; size/page limits; engine updates |
| Decompression bomb | Max stream expansion ratio; timeouts |
| Memory exhaustion | DPI caps; page batch size; LRU cache bounds |
| Path traversal (extract) | Sanitize output names; jail to output dir |
| Malicious attachments | Size limit; user confirm before open externally |
| PDF JavaScript | Do not execute JS in viewer |
| Sensitive data in logs | Policy in [PRIVACY.md](PRIVACY.md) |
| Clipboard after redact | Clear clipboard warning; true redaction pipeline |
| Weak encryption write | Warn when saving RC4-only; prefer AES via qpdf |

## Temporary files

- Directory: app-private temp only
- Naming: random prefix + job id
- Delete on success, failure, and app background timeout where OS allows
- Do not index temp dirs in cloud backup if platform permits exclusion (Android backup rules, iOS excluded paths)

## Passwords

- Never log passwords
- Optional: store encryption password in session memory only
- Keychain for “remember for this session” optional feature—off by default

## Encryption claims

- Unlock/remove restrictions **only** with correct password
- UI must not imply brute-force

## Redaction

**Permanent redaction** must remove underlying text/image operators, not only draw black rectangles. Verify with text extraction tests on corpus.

## External processes

LibreOffice:

- Spawn with dedicated profile dir under temp
- Kill on timeout
- No macro execution surface (headless convert only)

## Supply chain

- Pin engine versions; monitor CVEs for PDFium, qpdf, Tesseract
- Verify checksums of downloaded native binaries in CI

## User-facing security tools

Phase 7+: encrypt, permissions, metadata removal—each confirms output path and warns on weak passwords.

## Reporting

Security issues: document contact process in README when project goes public (placeholder: project owner).
