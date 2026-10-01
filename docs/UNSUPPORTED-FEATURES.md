# Intentionally Unsupported or Non-Local Features

Every item lists **why** Document Studio does not target it in core product (unless future ADR explicitly adds optional online module).

| Feature | Reason | Limitation type | Alternative |
| --- | --- | --- | --- |
| Cloud document upload/processing | Product principle NC-04 | Policy | Local engines only |
| User accounts / login for core | NC-05 | Policy | None required |
| Subscription / paywall | NC-01 | Policy | Free core |
| Advertisements | NC-02 | Policy | — |
| Backend API for PDF ops | NC-03 | Policy | On-device |
| AI summarization / chat / translate | NC-07 | Policy | Manual read/search/OCR |
| iLovePDF AI Summarizer equivalent | NC-07 | Policy | — |
| Remote OCR / remote convert APIs | NC-04, NC-10 | Policy | Tesseract, LO local |
| Send signature request + track signers | Requires server + identity | Cloud workflow | Export PDF; third-party e-sign |
| Bulk e-sign with reminders/notifications | Cloud | — | Local multi-copy export only |
| Adobe Document Cloud sync | Cloud storage | — | OS cloud drives via picker |
| Live collaborative review | Cloud | — | Export annotated PDF |
| MS Purview / IRM labels | Enterprise Adobe/MS stack | Licensing/ecosystem | Standard PDF encryption |
| Braintree payment on sign | Cloud + payments | — | — |
| Web forms hosted on vendor URL | Hosting | — | Local form fill + export |
| Telemetry with document content | Privacy | Policy | Opt-in diagnostics without content (future ADR) |
| Hidden analytics on PDF text | Privacy | Policy | — |
| Crack PDF without password | Security/ethics | Technical + policy | User must supply password |
| Fake redaction (black box only) | Security misrepresentation | Policy | Permanent redaction pipeline |
| Visual signature labeled “digital certificate” | Misrepresentation | Policy | Clear UI labels |
| Overlay-only labeled “edit PDF text” | Misrepresentation | Policy | Mode labels |
| GPL Ghostscript in app binary | License AGPL | Licensing | qpdf, LO external |
| MuPDF AGPL linked default | License | Licensing | PDFium + qpdf |
| Syncfusion as unconditional core | License revenue caps | Licensing | Open engines |
| OS virtual PDF printer driver (v1) | OS integration scope | Platform/engineering | In-app “Print to PDF” export |
| Fax send | Legacy telecom | Scope | — |
| Arbitrary PDF JavaScript execution | Security | Security | Detect/disable/warn |
| Launch actions to arbitrary programs | Security | Security | Block or confirm |
| Embedded multimedia playback (rich) | Scope + engine | Technical | Link to external viewer optional |
| Full XFA dynamic forms | Engine limitation | Technical | AcroForm; warn on XFA |
| Perfect PDF→Word layout parity | Technical | Technical | Fidelity class B/C UI |
| Adobe “paragraph reflow” edit quality | Engine gap | Technical | Add text + OCR export |
| AI auto-tagging for PDF/UA | NC-07 | Policy | Manual tagging investigate Phase 13 |
| Smallpdf/iLovePDF cloud-only mobile processing | Not applicable | — | Local mobile processing |
| Windows-only PDF24 parity on Mac/Linux printer | Platform | Platform | Export PDF from app |
| Continuous fax/email server integration | Scope | — | OS share sheet |

## Cloud features competitors have (record only)

| Competitor feature | Class |
| --- | --- |
| iLovePDF signature tracking portal | F — Cloud |
| Acrobat bulk send agreements | F — Cloud |
| Acrobat AI Assistant | F — AI |
| Adobe Express integration | F — Cloud |
| iLovePDF cloud drive default save | F — Cloud |

## May revisit via optional ADR (not core)

| Feature | Condition |
| --- | --- |
| Optional language pack download | User-initiated; strict offline blocks |
| TSA timestamp for PAdES-T | Explicit network disclosure; opt-in |
| veraPDF CLI bundling | Desktop only; MPL/GPL compliance |

## Agent rule

Do not remove rows without ADR. Do not implement unsupported features without ADR + inventory update.
