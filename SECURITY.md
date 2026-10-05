# Security policy

Document Studio processes documents **on the user’s device**. We take vulnerabilities that could compromise confidentiality, integrity, or availability of local document workflows seriously.

Please read this policy before disclosing a security issue.

---

## Supported versions

Security fixes are prioritized for the **latest published release** on [GitHub Releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases).

| Version | Supported |
| --- | --- |
| **1.1.x** (current: **1.1.0**) | Yes |
| **1.0.x** | Best effort — please upgrade |
| Older than 1.0.x | Best effort — please upgrade |
| Unreleased `master` / nightlies | Best effort while investigating |

Desktop installers (Windows Setup, macOS DMG, Linux `.deb`) and Homebrew packages tracking those releases are in scope when they ship Document Studio binaries from this project.

---

## What is in scope

We especially want reports about:

- Remote or local code execution via malicious PDFs, images, or Office files opened in Document Studio
- Path traversal, arbitrary file write/delete outside the intended save/export flow
- Bypass of PDF password / permission enforcement **inside the app** (not “I forgot my password”)
- Incomplete **redaction** that leaves recoverable text, images, or metadata when the UI claims content was removed
- Insecure update mechanisms (e.g. unsigned download tampering) if attributable to Document Studio’s updater
- Secrets hard-coded in the repository or release artifacts that grant unintended access
- XSS or similar issues in the **documentation site** that could harm visitors (lower severity than native RCE, still welcome)

---

## What is out of scope

The following are generally **not** treated as vulnerabilities in Document Studio:

- **Forgotten passwords** — the app will not and must not crack or bypass encryption
- Issues that require **already having** the document open password or OS admin rights on the machine
- Purely local denial-of-service by opening an absurdly large crafted file (please still report if it is an easy unprivileged crash with a tiny PoC)
- Vulnerabilities solely in **upstream** engines (qpdf, Tesseract, LibreOffice, PDFium, Flutter, OS libraries) with no Document Studio-specific trigger — report those upstream; tell us if we should bump a bundled version
- Social engineering, physical access, or malware unrelated to Document Studio
- Missing Apple notarization / SmartScreen warnings on unsigned or newly published builds (distribution trust UX, not an app logic bug)
- Feature requests framed as security issues (use GitHub Issues)

---

## How to report a vulnerability

### Preferred: GitHub private advisory

1. Open the repository’s **Security** tab:  
   https://github.com/tejashvi-kumawat/DocumentStudio/security  
2. Choose **Report a vulnerability** (private advisory), if available on the repo.  
3. Include the details listed below.

### Alternative

If private advisories are unavailable, contact the maintainer privately via the channels on  
[tejashvi-kumawat.github.io](https://tejashvi-kumawat.github.io)  
and mark the message as a **security disclosure**.

**Do not** file a public GitHub Issue with exploit code, weaponized PDFs, or step-by-step attack instructions.

---

## What to include

A useful report typically contains:

1. **Affected version** — release tag (e.g. `v1.1.0`) or commit SHA; OS and CPU arch  
2. **Impact** — confidentiality / integrity / availability in plain language  
3. **Reproduction** — minimal steps; prefer a **synthetic** fixture, not a real passport or contract  
4. **Expected vs actual** behavior  
5. **PoC** — smallest file or script that demonstrates the issue  
6. **Mitigations** you already see (if any)  
7. Whether you are okay being **credited** in release notes

We will acknowledge receipt as soon as practical and keep you updated on triage status.

---

## Disclosure timeline

We aim for:

| Stage | Target |
| --- | --- |
| Initial acknowledgement | Within **7 days** |
| Triage (valid / invalid / needs info) | Within **14 days** of a complete report |
| Fix or mitigation plan for confirmed high-impact issues | As soon as practical; coordinated disclosure preferred |

Please give us a reasonable window to fix and ship a release before public blog posts or full exploit write-ups. We are happy to credit researchers who disclose responsibly.

If a fix is published, we may reference the issue in release notes without publishing weaponized details until users have had time to update.

---

## Product security expectations (for users)

- Keep Document Studio updated (`document_studio --check-update` / `--update`, Homebrew, or a newer installer from Releases).
- Store encryption passwords outside the PDF; **lost passwords cannot be recovered**.
- On shared computers, save outputs to a private folder.
- Prefer **Redact** over drawing black boxes when removing sensitive content.
- Treat third-party engines as part of your trust boundary; install only from [official Releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases) or the project Homebrew tap.

More user-facing guidance:  
[Security page](https://tejashvi-kumawat.github.io/DocumentStudio/#/security) ·  
[Privacy page](https://tejashvi-kumawat.github.io/DocumentStudio/#/privacy)

Engineering threat-model notes for contributors: [`docs/SECURITY.md`](docs/SECURITY.md).

---

## Safe harbor

We will not pursue legal action against researchers who:

- Make a good-faith effort to avoid privacy violations and service disruption  
- Do not access data that is not theirs beyond what is needed to demonstrate the issue  
- Do not exploit the issue beyond a minimal PoC  
- Report findings to us promptly and keep details private until we have addressed them or agreed on disclosure  

This is not a bug bounty program unless separately announced. Appreciation and public credit are the default thank-you.

---

## Non-security bugs

Usability bugs, crashes without security impact, and feature requests belong in  
[GitHub Issues](https://github.com/tejashvi-kumawat/DocumentStudio/issues).
