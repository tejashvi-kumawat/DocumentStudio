// Business and office templates.

const invoiceHtml = r'''<!doctype html>
<html>
<head><meta charset="utf-8"><title>Invoice INV-2026-0142</title><style>@page { size: A4; }</style></head>
<body>
  <h1 style="color:#0d47a1">INVOICE</h1>
  <p><b>Sovaria Tech Pvt. Ltd.</b><br>
  42, Residency Road, Bengaluru 560025<br>
  GSTIN: 29ABCDE1234F1Z5 · accounts@sovaria.example · +91 80 4000 1234</p>

  <table>
    <tr><th>Invoice no.</th><th>Invoice date</th><th>Due date</th><th>PO / Ref.</th></tr>
    <tr><td>INV-2026-0142</td><td>6 Oct 2026</td><td>5 Nov 2026</td><td>PO-88213</td></tr>
  </table>

  <h3>Bill to</h3>
  <p><b>Northwind Retail LLP</b><br>
  Plot 9, HITEC City, Hyderabad 500081<br>
  GSTIN: 36PQRSX9876L1Z2</p>

  <table>
    <tr><th>#</th><th>Description</th><th style="text-align:center">Qty</th><th style="text-align:right">Rate (₹)</th><th style="text-align:right">Amount (₹)</th></tr>
    <tr><td>1</td><td>Document workflow consulting (hours)</td><td style="text-align:center">24</td><td style="text-align:right">3,500.00</td><td style="text-align:right">84,000.00</td></tr>
    <tr><td>2</td><td>Custom PDF form templates</td><td style="text-align:center">6</td><td style="text-align:right">7,500.00</td><td style="text-align:right">45,000.00</td></tr>
    <tr><td>3</td><td>Annual support plan</td><td style="text-align:center">1</td><td style="text-align:right">36,000.00</td><td style="text-align:right">36,000.00</td></tr>
    <tr><td></td><td><b>Subtotal</b></td><td></td><td></td><td style="text-align:right"><b>1,65,000.00</b></td></tr>
    <tr><td></td><td>CGST 9%</td><td></td><td></td><td style="text-align:right">14,850.00</td></tr>
    <tr><td></td><td>SGST 9%</td><td></td><td></td><td style="text-align:right">14,850.00</td></tr>
    <tr><td></td><td><b>Total due</b></td><td></td><td></td><td style="text-align:right"><b>1,94,700.00</b></td></tr>
  </table>
  <p><i>Amount in words: Rupees One Lakh Ninety-Four Thousand Seven Hundred only.</i></p>

  <h3>Payment details</h3>
  <p>Bank: HDFC Bank, MG Road · A/c 50200012345678 · IFSC HDFC0000123 · UPI: sovaria@hdfcbank</p>

  <h3>Terms</h3>
  <ol>
    <li>Payment due within 30 days of the invoice date.</li>
    <li>Late payments attract interest at 1.5% per month.</li>
  </ol>
  <p style="text-align:right">For Sovaria Tech Pvt. Ltd.<br><br><br><b>Authorised Signatory</b></p>
</body>
</html>
''';

const quotationHtml = r'''<!doctype html>
<html>
<head><meta charset="utf-8"><title>Quotation Q-2026-031</title></head>
<body>
  <h1 style="color:#2e7d32">QUOTATION</h1>
  <p><b>GreenBuild Interiors</b> · 12 Park Street, Kolkata · +91 33 2200 4455</p>
  <p><b>Quotation no.:</b> Q-2026-031 &nbsp; <b>Date:</b> 6 Oct 2026 &nbsp; <b>Valid until:</b> 5 Nov 2026</p>
  <p><b>To:</b> Ms. Tejashvi Kumawat, 7B Lake View Apartments, Delhi</p>
  <p>Subject: Modular kitchen and wardrobe work</p>
  <table>
    <tr><th>Item</th><th>Specification</th><th style="text-align:right">Amount (₹)</th></tr>
    <tr><td>Modular kitchen</td><td>BWP plywood, acrylic finish, soft-close hardware</td><td style="text-align:right">2,40,000</td></tr>
    <tr><td>Wardrobes (2)</td><td>Laminate finish, sliding doors, 8 ft</td><td style="text-align:right">1,20,000</td></tr>
    <tr><td>Installation</td><td>Labour, transport, site cleaning</td><td style="text-align:right">25,000</td></tr>
    <tr><td><b>Total</b></td><td>(GST extra as applicable)</td><td style="text-align:right"><b>3,85,000</b></td></tr>
  </table>
  <h3>Terms</h3>
  <ul>
    <li>50% advance, 40% on delivery, 10% after installation.</li>
    <li>Delivery in 4 weeks from design approval.</li>
    <li>5-year warranty on hardware.</li>
  </ul>
  <p>We look forward to working with you.</p>
  <p><b>Tejashvi Kumawat</b><br>Founder & CEO</p>
</body>
</html>
''';

const proposalMd = r'''# Project Proposal: Digital Records for City Clinics
**Prepared for:** Municipal Health Department · **Prepared by:** Sovaria Tech · **Date:** 6 October 2026

---

## 1. Executive summary
The city's 46 clinics keep patient records on paper. We propose a phased rollout of an
offline-first digital record system that works on low-cost tablets, syncs when a
connection is available and keeps data inside the state data centre.

**Outcome in 12 months:** all clinics digital, average visit time −20%, monthly reports
generated automatically.

## 2. Problem
- Records are lost or duplicated; follow-ups are missed.
- Monthly reporting takes each clinic ~3 staff-days.
- No view of disease trends across the city.

## 3. Proposed solution
1. **Tablet app** for registration, consultation notes and prescriptions.
2. **Sync server** in the state data centre with daily encrypted backups.
3. **Dashboard** for the department: footfall, diseases, stock levels.

## 4. Scope and deliverables
| Phase | Deliverables | Duration |
|------|--------------|----------|
| 1. Pilot | App + server for 5 clinics, training | 3 months |
| 2. Rollout | Remaining 41 clinics, data migration of last 2 years | 6 months |
| 3. Analytics | Dashboard, monthly report automation | 3 months |

## 5. Budget
| Item | Cost (₹ lakh) |
|------|--------------:|
| Software development | 48.0 |
| Tablets (120) | 24.0 |
| Training and support (1 year) | 12.0 |
| **Total** | **84.0** |

## 6. Risks and mitigations
- **Connectivity** — app works offline; sync resumes automatically.
- **Adoption** — on-site champions in each clinic; two-week parallel run.
- **Data privacy** — encryption at rest and in transit; role-based access.

## 7. Next steps
- [ ] Approve pilot scope and clinics
- [ ] Sign agreement
- [ ] Kick-off workshop (week 1)
''';

const meetingMinutesMd = r'''# Minutes — Product Review Meeting
**Date:** 6 October 2026 · **Time:** 10:00–11:00 · **Location:** Room 4B / video call
**Chair:** Tejashvi Kumawat · **Minutes:** T. Kumawat
**Present:** R. Gupta, A. Sharma, M. Iyer, T. Kumawat · **Apologies:** S. Das

---

## 1. Previous minutes
Approved without changes.

## 2. Release 1.1 status
- Feature freeze reached on 2 October; 14 open bugs, 3 high priority.
- **Decision:** release moves to 13 October to fix the high-priority bugs.

## 3. Customer feedback
- Users ask for Word and PowerPoint editing; prototype shown and well received.
- **Decision:** include basic editing in 1.2.

## 4. Any other business
None.

## Action items
| # | Action | Owner | Due |
|---|--------|-------|-----|
| 1 | Fix three high-priority bugs | A. Sharma | 10 Oct |
| 2 | Update release notes | T. Kumawat | 11 Oct |
| 3 | Plan 1.2 scope | R. Gupta | 15 Oct |

**Next meeting:** 13 October 2026, 10:00.
''';

const memoHtml = r'''<!doctype html>
<html>
<head><meta charset="utf-8"><title>Memo</title></head>
<body>
  <h1 style="letter-spacing:2px">MEMORANDUM</h1>
  <hr>
  <table>
    <tr><td><b>To:</b></td><td>All staff</td></tr>
    <tr><td><b>From:</b></td><td>Human Resources</td></tr>
    <tr><td><b>Date:</b></td><td>6 October 2026</td></tr>
    <tr><td><b>Subject:</b></td><td>Office closure for Diwali</td></tr>
  </table>
  <hr>
  <p>The office will be closed from <b>Thursday 29 October</b> to <b>Monday 2 November</b> for Diwali.
  Regular hours resume on Tuesday 3 November.</p>
  <p>Please:</p>
  <ul>
    <li>Update your calendar and out-of-office replies.</li>
    <li>Hand over urgent work to the on-call team listed below.</li>
    <li>Switch off and unplug equipment at your desk before leaving.</li>
  </ul>
  <p><b>On-call contacts:</b> IT — 98765 00001 · Facilities — 98765 00002</p>
  <p>Wishing you and your families a happy Diwali.</p>
</body>
</html>
''';

const businessLetterHtml = r'''<!doctype html>
<html>
<head><meta charset="utf-8"><title>Business letter</title></head>
<body>
  <p style="text-align:right"><b>Sovaria Tech Pvt. Ltd.</b><br>42, Residency Road<br>Bengaluru 560025<br>6 October 2026</p>
  <p>Mr. Tejashvi Kumawat<br>Founder & CEO<br>Sovaria Tech Pvt. Ltd.<br>Delhi 110016</p>
  <p><b>Subject: Renewal of the annual support agreement</b></p>
  <p>Dear Mr. Tejashvi Kumawat,</p>
  <p>Thank you for your continued partnership. Your annual support agreement (ref. ASA-2025-07)
  expires on 31 October 2026. We are pleased to offer a renewal at the same price for another year,
  together with two new benefits: priority response within four hours and quarterly training sessions.</p>
  <p>Please find the renewal quotation enclosed. To continue without interruption, kindly confirm
  by 20 October.</p>
  <p>Should you have any questions, I would be happy to help.</p>
  <p>Yours sincerely,<br><br><br><b>Neha Verma</b><br>Account Manager · +91 80 4000 1234</p>
  <p><small>Enclosure: Quotation Q-2026-044</small></p>
</body>
</html>
''';

const formalLetterTex = r'''\documentclass[11pt,a4paper]{article}

\begin{document}

\begin{flushright}
Tejashvi Kumawat \\
Room 214, Kailash Hostel \\
IIT Delhi, New Delhi 110016 \\
\today
\end{flushright}

\noindent The Dean of Students \\
Indian Institute of Technology Delhi \\
New Delhi 110016

\bigskip
\noindent\textbf{Subject: Request for permission to organise a technical workshop}

\bigskip
\noindent Respected Sir/Madam,

I am writing on behalf of the Civil Engineering Society to request permission to
organise a two-day workshop on \textit{Structural Health Monitoring} on 24--25 October
2026 in Lecture Hall Complex, Room 108.

The workshop will host about 120 students and two invited speakers. All expenses will be
met from the society's budget, and we will follow the institute's guidelines on safety
and venue use.

I would be grateful if you could grant the permission and the venue booking.

\bigskip
\noindent Thank you. \\[1em]
\noindent Yours sincerely, \\[2.5em]
\noindent Tejashvi Kumawat \\
General Secretary, Civil Engineering Society

\end{document}
''';

const recommendationMd = r'''**Prof. Sumeet K Sinha**
Department of Civil Engineering, IIT Delhi · sumeet.k.sinha@iitd.ac.in

6 October 2026

To the Admissions Committee,

**Letter of recommendation for Tejashvi Kumawat**

I am pleased to recommend Tejashvi Kumawat for your graduate programme. I have known
Tejashvi for two years as the instructor of *Structural Analysis* and as supervisor of
the B.Tech. project on rainwater harvesting.

In my course Tejashvi ranked in the **top 3 of 120 students**. The project showed
independent thinking: the design method combined hydrology with structural checks and
was adopted by the campus estate office.

Tejashvi communicates clearly, works well in teams and finishes work on time. I recommend
the application **without reservation**.

Sincerely,

**Sumeet K Sinha**
Professor, Department of Civil Engineering, IIT Delhi
''';
