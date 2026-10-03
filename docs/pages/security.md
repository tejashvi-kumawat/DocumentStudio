# Security

## Threat model (product)

- Documents are processed locally; compromise of a remote Document Studio API is not in the core model because there isn’t one.
- Password-protected PDFs still need the correct password — the app does not bypass encryption.
- Redaction aims to remove underlying content, not only paint over it.

## Desktop packaging

- Windows Setup installs under the user Programs folder by default (per-user friendly).
- macOS builds may be ad-hoc signed until Apple notarization is configured — Gatekeeper may ask for an explicit Open the first time.
- Release bundles include third-party engines; license texts ship under `THIRD_PARTY_LICENSES`.

## Recommendations

- Keep the app updated (`document_studio --update` or your package manager).
- Treat encrypted PDFs carefully — remember passwords; we can’t recover them.
- On shared machines, save outputs to private folders.
