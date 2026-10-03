# Security

## Product rules

- Documents are processed **locally**. There is no Document Studio cloud API that receives your PDF bytes for core tools.
- Password-protected PDFs still need the **correct password** — the app does not crack or bypass encryption.
- **Redaction** is meant to remove underlying content, not only paint a black box on top.

## Packaging notes

| Platform | Note |
| --- | --- |
| Windows | Per-user Setup under Programs by default; elevates only when needed for optional system bits |
| macOS | Builds may be ad-hoc signed until Apple notarization is configured — use right-click → Open once |
| Linux | `.deb` installs under `/usr` with a desktop entry and icons |

Release bundles include third-party engines; license texts ship under `THIRD_PARTY_LICENSES`.

## Recommendations

1. Keep current with `document_studio --update` or your package manager.  
2. Store encryption passwords outside the PDF — we cannot recover them.  
3. On shared PCs, save exports to a private folder.  
4. Prefer **redact** over covering text with a black rectangle in a drawing tool.

## Reporting issues

Security-sensitive bugs: open a private report or issue on [GitHub](https://github.com/tejashvi-kumawat/DocumentStudio/issues) with enough detail to reproduce, without attaching confidential documents.
