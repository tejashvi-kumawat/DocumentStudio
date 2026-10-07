// Résumé, CV and cover-letter templates (original designs).

const resumeClassicTex = r'''\documentclass[10pt,a4paper]{article}
% Classic one-page résumé. Replace the text in brackets; delete what you
% do not need. Sections: Summary, Experience, Projects, Education, Skills.

\begin{document}

\begin{center}
{\Huge \textbf{Tejashvi Kumawat}} \\[4pt]
Delhi, India \quad|\quad +91 98765 43210 \quad|\quad \href{mailto:tejashvi@example.com}{tejashvi@example.com} \quad|\quad \href{https://linkedin.com/in/tejashvi}{linkedin.com/in/tejashvi} \quad|\quad \href{https://github.com/tejashvi}{github.com/tejashvi}
\end{center}

\section*{Summary}
\hrule
\medskip
Software engineer with 4 years of experience building reliable backend services and
developer tools. Led the migration of a payments platform to an event-driven design,
cutting checkout latency by 38\%. Comfortable owning features from design to on-call.

\section*{Experience}
\hrule
\medskip
\noindent\textbf{Senior Software Engineer} \hfill \textbf{Jan 2024 -- Present} \\
\textit{Finvista Payments, Bengaluru} \hfill \textit{Full-time}
\begin{itemize}
  \item Designed an idempotent payment-intent service handling 2.1M requests per day at 99.98\% availability.
  \item Replaced nightly batch reconciliation with streaming jobs; mismatches found within 5 minutes instead of 24 hours.
  \item Mentored 3 engineers; introduced design reviews and an on-call handbook adopted by 6 teams.
\end{itemize}

\noindent\textbf{Software Engineer} \hfill \textbf{Jul 2021 -- Dec 2023} \\
\textit{CloudNest Technologies, Pune} \hfill \textit{Full-time}
\begin{itemize}
  \item Built a multi-tenant job scheduler in Go used by 40+ internal services.
  \item Cut cloud cost by 22\% by right-sizing clusters and adding autoscaling policies.
  \item Wrote the public SDK documentation; support tickets about integration fell by half.
\end{itemize}

\section*{Projects}
\hrule
\medskip
\noindent\textbf{PDFKit Lite} -- open-source PDF toolkit \hfill \href{https://github.com/aarav/pdfkit-lite}{github.com/aarav/pdfkit-lite} \\
Merge, split and compress PDFs from the command line; 1.2k stars, 30 contributors.

\noindent\textbf{Campus Ride} -- carpool app for students \hfill 2020 \\
Flutter + Firebase app with 5,000 monthly users at three universities.

\section*{Education}
\hrule
\medskip
\noindent\textbf{B.Tech. in Computer Science and Engineering} \hfill \textbf{2017 -- 2021} \\
\textit{Indian Institute of Technology, Delhi} \hfill CGPA: 8.7 / 10

\section*{Skills}
\hrule
\medskip
\begin{description}
  \item[Languages] Go, Java, Python, Dart, SQL, TypeScript
  \item[Systems] PostgreSQL, Kafka, Redis, Docker, Kubernetes, AWS
  \item[Practices] System design, testing, observability, incident response
\end{description}

\section*{Achievements}
\hrule
\medskip
\begin{itemize}
  \item Winner, Smart India Hackathon 2020 (team of 6).
  \item AWS Certified Solutions Architect -- Associate (2023).
\end{itemize}

\end{document}
''';

const resumeAcademicTex = r'''\documentclass[11pt,a4paper]{article}
% Academic CV: education, research, publications, teaching, service.

\begin{document}

\begin{center}
{\LARGE \textbf{Dr. Tejashvi Kumawat}} \\[3pt]
Assistant Professor, Department of Civil Engineering \\
Indian Institute of Technology Delhi, Hauz Khas, New Delhi 110016 \\
\href{mailto:tejashvi.kumawat@example.edu}{tejashvi.kumawat@example.edu} \quad|\quad \href{https://example.edu/~tejashvi}{example.edu/\textasciitilde{}tejashvi} \quad|\quad ORCID 0000-0002-1234-5678
\end{center}

\section*{Research Interests}
Structural health monitoring, earthquake engineering, data-driven models for ageing
infrastructure, low-cost sensing for bridges.

\section*{Education}
\noindent\textbf{Ph.D., Structural Engineering}, Stanford University \hfill 2016 -- 2021 \\
Thesis: \textit{Learning damage signatures from ambient vibration data}. Advisor: Prof. J. Smith.

\noindent\textbf{M.Tech., Structural Engineering}, IIT Bombay \hfill 2014 -- 2016

\noindent\textbf{B.Tech., Civil Engineering}, NIT Trichy \hfill 2010 -- 2014

\section*{Appointments}
\noindent\textbf{Assistant Professor}, IIT Delhi \hfill 2022 -- present \\
\noindent\textbf{Postdoctoral Scholar}, University of California, Berkeley \hfill 2021 -- 2022

\section*{Publications}
\subsection*{Journal articles}
\begin{enumerate}
  \item M. Iyer, J. Smith. ``Bayesian damage detection for steel bridges.'' \textit{Journal of Structural Engineering}, 149(3), 2023.
  \item M. Iyer, R. Gupta, J. Smith. ``Transfer learning for vibration-based monitoring.'' \textit{Structural Control and Health Monitoring}, 29(8), 2022.
\end{enumerate}
\subsection*{Conference papers}
\begin{enumerate}
  \item M. Iyer, J. Smith. ``Low-cost MEMS arrays for modal identification.'' \textit{Proc. IMAC}, 2020.
\end{enumerate}

\section*{Grants}
\begin{itemize}
  \item SERB Start-up Research Grant, \textit{Smart sensing for rural bridges}, INR 30 lakh, 2023 -- 2026 (PI).
\end{itemize}

\section*{Teaching}
\begin{itemize}
  \item CVL 321 -- Structural Analysis (undergraduate, 120 students), 2022 -- present.
  \item CVL 741 -- Structural Dynamics (graduate), 2023 -- present.
\end{itemize}

\section*{Awards}
\begin{itemize}
  \item Best Paper Award, International Workshop on SHM, 2021.
  \item Stanford Graduate Fellowship, 2016 -- 2019.
\end{itemize}

\section*{Service}
Reviewer for \textit{Engineering Structures} and \textit{Journal of Bridge Engineering};
organiser, IIT Delhi Structures Seminar (2023 -- ).

\section*{References}
Available on request.

\end{document}
''';

const resumeModernMd = r'''# Tejashvi Kumawat
**Product Designer** · Delhi, India · +91 98765 43210 · tejashvi.kumawat@example.com · [tejashvi.kumawat.in](https://tejashvi.kumawat.in) · [Dribbble](https://dribbble.com/tejashvi)

---

## Profile
Product designer with 5 years of experience shaping mobile and web products from
research to launch. I turn messy problems into calm, measurable experiences and
work closely with engineering to ship them.

## Experience

### Lead Product Designer — ShopLane
*Mumbai · March 2023 – Present*
- Redesigned checkout across Android, iOS and web; **conversion +14%**, drop-offs −27%.
- Built the *Lane* design system (180 components) now used by 9 squads.
- Run monthly usability studies with 40+ customers; findings feed the quarterly roadmap.

### Product Designer — HealthFirst
*Bengaluru · June 2020 – February 2023*
- Designed teleconsultation flows for 2M patients; appointment booking time halved.
- Introduced accessibility reviews; app reached WCAG 2.1 AA.

## Education
**Bachelor of Design (Interaction Design)** — National Institute of Design, Ahmedabad · 2016 – 2020

## Skills
| Area | Tools and methods |
|------|-------------------|
| Design | Figma, prototyping, design systems, motion |
| Research | Interviews, usability testing, surveys, analytics |
| Collaboration | Workshops, roadmapping, design critique |

## Selected work
- **ShopLane checkout** — case study: [riyadesigns.in/checkout](https://riyadesigns.in/checkout)
- **HealthFirst consult** — case study: [riyadesigns.in/consult](https://riyadesigns.in/consult)

## Languages
English (fluent) · Hindi (native) · Marathi (conversational)
''';

const resumeExecutiveHtml = r'''<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Tejashvi Kumawat — Résumé</title>
  <style>@page { size: A4; }</style>
</head>
<body>
  <h1 style="text-align:center; color:#1a237e">TEJASHVI KUMAWAT</h1>
  <p style="text-align:center"><b>Operations Director</b> · Delhi · +91 98765 43210 · tejashvi.kumawat@example.com</p>
  <hr>

  <h3 style="color:#1a237e">PROFESSIONAL SUMMARY</h3>
  <p>Operations leader with 15 years in manufacturing and supply chain. Turned around two
  plants to profitability, built teams of 400+, and delivered ₹120 crore in savings through
  lean programmes and supplier consolidation.</p>

  <h3 style="color:#1a237e">CORE COMPETENCIES</h3>
  <table>
    <tr><td>Plant operations</td><td>Lean &amp; Six Sigma</td><td>Supply-chain strategy</td></tr>
    <tr><td>P&amp;L ownership</td><td>Vendor negotiation</td><td>Change management</td></tr>
  </table>

  <h3 style="color:#1a237e">PROFESSIONAL EXPERIENCE</h3>
  <p><b>Director, Operations</b> — Deccan Auto Components Ltd. <span style="color:#757575">(2018 – present)</span></p>
  <ul>
    <li>Lead 3 plants and 1,100 people; on-time delivery from 82% to 97%.</li>
    <li>Cut scrap by 41% with a plant-wide Six Sigma programme.</li>
    <li>Negotiated long-term steel contracts saving ₹38 crore over 3 years.</li>
  </ul>
  <p><b>Plant Head</b> — Sunrise Packaging Pvt. Ltd. <span style="color:#757575">(2012 – 2018)</span></p>
  <ul>
    <li>Turned a loss-making plant profitable within 18 months.</li>
    <li>Commissioned a ₹60 crore line on time and under budget.</li>
  </ul>

  <h3 style="color:#1a237e">EDUCATION</h3>
  <p><b>MBA, Operations</b> — Indian School of Business (2011)<br>
  <b>B.E., Mechanical Engineering</b> — Osmania University (2007)</p>

  <h3 style="color:#1a237e">CERTIFICATIONS</h3>
  <p>Six Sigma Black Belt (ASQ) · PMP (PMI) · ISO 9001 Lead Auditor</p>
</body>
</html>
''';

const coverLetterTex = r'''\documentclass[11pt,a4paper]{article}
% Cover letter. Keep it to one page: why this role, what you bring, a close.

\begin{document}

\noindent\textbf{Tejashvi Kumawat} \hfill \today \\
Delhi, India \\
+91 98765 43210 \quad|\quad \href{mailto:tejashvi@example.com}{tejashvi@example.com}

\bigskip
\noindent Hiring Manager \\
Platform Engineering \\
Northwind Systems \\
Hyderabad, India

\bigskip
\noindent\textbf{Re: Senior Backend Engineer (Ref. NW-2026-114)}

\bigskip
\noindent Dear Hiring Manager,

I am writing to apply for the Senior Backend Engineer role on your Platform team. Your
work on making payments infrastructure observable by default matches what I have spent
the last four years doing, and I would love to bring that experience to Northwind.

At Finvista Payments I designed an idempotent payment-intent service that now handles
2.1 million requests a day at 99.98\% availability, and I replaced a nightly
reconciliation batch with streaming jobs so that mismatches surface within minutes.
Both projects needed careful trade-offs between consistency, cost and simplicity ---
the same balance your job description emphasises.

Beyond the code, I enjoy making teams faster: I introduced lightweight design reviews
and an on-call handbook that six teams adopted. I would bring the same habits to your
growing platform group.

Thank you for considering my application. I would welcome the chance to discuss how I
can help Northwind scale its platform.

\bigskip
\noindent Sincerely, \\[2em]
\noindent Aarav Sharma

\end{document}
''';

const coverLetterMd = r'''**Riya Kapoor**
Delhi, India · tejashvi.kumawat@example.com · +91 98765 43210

6 October 2026

Hiring Team
Lumen Health
Bengaluru

**Application: Senior Product Designer**

Dear Hiring Team,

I was excited to see the Senior Product Designer opening at Lumen Health. Making
healthcare feel calm and trustworthy is the work I care about most, and I believe my
experience at HealthFirst and ShopLane fits what you are building.

At HealthFirst I redesigned teleconsultation flows used by two million patients and
halved the time it takes to book an appointment. At ShopLane I lead a design system
used by nine squads and drove a checkout redesign that raised conversion by 14%.

I would bring a research-led process, close partnership with engineering and a habit
of measuring outcomes. My portfolio is at [riyadesigns.in](https://riyadesigns.in).

Thank you for your time — I would be glad to talk.

Warm regards,
**Riya Kapoor**
''';
