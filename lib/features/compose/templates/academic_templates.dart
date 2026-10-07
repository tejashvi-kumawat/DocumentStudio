// Academic templates: assignment, lab report, research paper, project
// report, lecture notes.

const assignmentTex = r'''\documentclass[11pt,a4paper]{article}
\usepackage{amsmath}

\title{CVL 321 -- Structural Analysis \\ Assignment 3}
\author{Name: Tejashvi Kumawat \quad Entry No.: 2023CE10237}
\date{Due: 20 October 2026}

\begin{document}
\maketitle

\section*{Instructions}
\begin{itemize}
  \item Show all steps. State assumptions clearly.
  \item Box your final answers and give units.
\end{itemize}

\section*{Problem 1 \quad (10 marks)}
A simply supported beam of span $L = 6\,\text{m}$ carries a uniformly distributed load
$w = 12\,\text{kN/m}$. Find the maximum bending moment and the mid-span deflection.
Take $EI = 2.4 \times 10^{4}\,\text{kN m}^2$.

\paragraph{Solution.}
The reactions are equal by symmetry: $R_A = R_B = \dfrac{wL}{2} = 36\,\text{kN}$.
The maximum moment occurs at mid-span:
\begin{equation}
  M_{\max} = \frac{wL^2}{8} = \frac{12 \times 6^2}{8} = 54\,\text{kN m}.
\end{equation}
The mid-span deflection is
\begin{equation}
  \delta_{\max} = \frac{5wL^4}{384\,EI}
  = \frac{5 \times 12 \times 6^4}{384 \times 2.4\times10^{4}}
  \approx 8.44\,\text{mm}.
\end{equation}
\[
  \boxed{M_{\max} = 54\ \text{kN m}, \qquad \delta_{\max} \approx 8.44\ \text{mm}}
\]

\section*{Problem 2 \quad (10 marks)}
Determine the degree of static indeterminacy of the frames shown.
\begin{enumerate}
  \item Portal frame fixed at both bases.
  \item Two-bay frame with a pinned and a fixed support.
\end{enumerate}

\paragraph{Solution.}
\begin{enumerate}
  \item $D_s = 3m + r - 3j = 3(3) + 6 - 3(4) = 3$.
  \item \dots
\end{enumerate}

\section*{References}
\begin{enumerate}
  \item R.C. Hibbeler, \textit{Structural Analysis}, 10th ed., Pearson, 2017.
\end{enumerate}

\end{document}
''';

const labReportTex = r'''\documentclass[11pt,a4paper]{article}
\usepackage{amsmath}
\usepackage{graphicx}

\title{Experiment 4: Determination of the Young's Modulus of Steel}
\author{Group B2 -- Sumeet K Sinha, R. Gupta, T. Kumawat}
\date{Performed: 2 October 2026 \quad Submitted: 9 October 2026}

\begin{document}
\maketitle

\begin{abstract}
The Young's modulus of a mild-steel wire was measured with Searle's apparatus. Loads
from 0 to 5 kg were applied in 0.5 kg steps and the extension read with a micrometer.
The slope of the stress--strain line gives $E = 204 \pm 6$ GPa, within 2\% of the
accepted value of 200 GPa.
\end{abstract}

\section{Aim}
To determine the Young's modulus of a steel wire by Searle's method.

\section{Apparatus}
\begin{itemize}
  \item Searle's apparatus with spirit level and micrometer (least count 0.01 mm)
  \item Two identical steel wires, about 2 m long
  \item Slotted weights (0.5 kg each), metre scale, screw gauge
\end{itemize}

\section{Theory}
For a wire of length $L$ and radius $r$ stretched by a load $Mg$ with extension $\ell$,
\begin{equation}
  E = \frac{\text{stress}}{\text{strain}} = \frac{Mg/\pi r^2}{\ell / L} = \frac{gL}{\pi r^2}\cdot\frac{M}{\ell}.
\end{equation}
The ratio $M/\ell$ is taken from the slope of the load--extension graph.

\section{Procedure}
\begin{enumerate}
  \item Measure the wire length with the metre scale and its diameter at five places with the screw gauge.
  \item Add a dead load to straighten the wire; set the spirit level and read the micrometer.
  \item Add 0.5 kg at a time up to 5 kg, wait one minute, re-level and record the reading.
  \item Unload in the same steps and record again; average loading and unloading readings.
\end{enumerate}

\section{Observations}
Length $L = 2.000$ m; mean diameter $d = 0.52$ mm, so $r = 0.26$ mm.

\begin{table}[h]
\centering
\begin{tabular}{|c|c|c|c|}
\hline
Load (kg) & Loading (mm) & Unloading (mm) & Mean extension (mm) \\
\hline
0.5 & 0.11 & 0.12 & 0.115 \\
1.0 & 0.23 & 0.24 & 0.235 \\
1.5 & 0.35 & 0.35 & 0.350 \\
2.0 & 0.47 & 0.46 & 0.465 \\
2.5 & 0.58 & 0.59 & 0.585 \\
\hline
\end{tabular}
\caption{Extension of the wire under load}
\end{table}

\section{Calculations}
From the graph, $M/\ell = 4.27$ kg/mm. Then
\[
  E = \frac{9.81 \times 2.000}{\pi (0.26\times10^{-3})^2} \times \frac{4.27}{10^{-3}}
  \approx 2.04 \times 10^{11}\ \text{Pa}.
\]

\section{Results}
The Young's modulus of the steel wire is $E = 204 \pm 6$ GPa.

\section{Sources of Error and Precautions}
\begin{itemize}
  \item Kinks in the wire were removed with a dead load before readings.
  \item Readings were taken after waiting for the wire to settle (creep).
  \item The diameter was measured at several places to average out non-uniformity.
\end{itemize}

\section{Conclusion}
The measured value agrees with the accepted value of 200 GPa within experimental error.

\end{document}
''';

const researchPaperTex = r'''\documentclass[10pt,a4paper]{article}
\usepackage{amsmath}
\usepackage{graphicx}

\title{Low-Cost Vibration Monitoring of Footbridges Using Smartphone Sensors}
\author{Tejashvi Kumawat$^{1}$, Sumeet K Sinha$^{1}$ \\ $^{1}$Department of Civil Engineering, IIT Delhi}
\date{}

\begin{document}
\maketitle

\begin{abstract}
We show that consumer smartphones mounted on a footbridge deck can identify its first
three natural frequencies within 2\% of a reference accelerometer array. Using 12 phones
and a simple synchronisation scheme, we record ambient vibration for 30 minutes and apply
frequency-domain decomposition. The approach costs under 5\% of a conventional system and
can support routine condition assessment of pedestrian bridges.
\end{abstract}

\noindent\textbf{Keywords:} structural health monitoring, modal identification, smartphones, footbridges

\section{Introduction}
Pedestrian bridges are numerous but rarely instrumented because monitoring systems are
expensive [1]. Smartphones contain accelerometers whose noise floor has improved steadily
[2]. This paper asks whether a group of phones can replace a reference array for routine
modal identification.

\section{Related Work}
Crowd-sourced sensing has been used for road roughness [3] and building vibration [4].
For bridges, previous studies used a single phone and identified only the fundamental
mode [5].

\section{Method}
\subsection{Instrumentation}
Twelve phones were fixed at quarter points on both kerbs. Clocks were aligned with an
NTP exchange before and after each record.
\subsection{Identification}
Frequency-domain decomposition takes the singular value decomposition of the
cross-spectral density matrix $G(\omega)$:
\begin{equation}
  G(j\omega_i) = U_i\, S_i\, U_i^{H},
\end{equation}
where peaks of the first singular value $s_1(\omega)$ indicate natural frequencies.

\section{Results}
\begin{table}[h]
\centering
\begin{tabular}{lccc}
\toprule
Mode & Reference (Hz) & Phones (Hz) & Error (\%) \\
\midrule
1 (vertical bending) & 2.31 & 2.29 & 0.9 \\
2 (lateral) & 3.84 & 3.79 & 1.3 \\
3 (torsion) & 6.02 & 5.92 & 1.7 \\
\bottomrule
\end{tabular}
\caption{Identified natural frequencies}
\end{table}

\section{Discussion}
Errors grow with mode number because higher modes have lower amplitude under ambient
excitation. Longer records or a person walking on the deck improve the third mode.

\section{Conclusion}
Smartphone arrays identify the main modes of a footbridge accurately and cheaply, which
makes periodic monitoring practical for local authorities.

\section*{Acknowledgements}
We thank the municipal corporation for access to the bridge.

\section*{References}
\begin{enumerate}
  \item C. Farrar, K. Worden, \textit{Structural Health Monitoring}, Wiley, 2013.
  \item A. Author, ``Smartphone accelerometers for vibration,'' \textit{Sensors}, 2019.
  \item B. Author, ``Crowd-sourced road roughness,'' \textit{Transp. Res. C}, 2018.
  \item C. Author, ``Building vibration with phones,'' \textit{Earthquake Spectra}, 2020.
  \item D. Author, ``Phone-based bridge frequency,'' \textit{J. Bridge Eng.}, 2021.
\end{enumerate}

\end{document}
''';

const projectReportTex = r'''\documentclass[12pt,a4paper]{article}
\usepackage{amsmath}
\usepackage{graphicx}

\title{\textbf{Design of a Rainwater Harvesting System for the Hostel Complex} \\[1em]
{\large B.Tech. Project Report}}
\author{Submitted by: Tejashvi Kumawat (2023CE10237) \\[0.5em]
Supervisor: Prof. Sumeet K Sinha \\[1em]
Department of Civil Engineering \\ Indian Institute of Technology Delhi}
\date{November 2026}

\begin{document}
\maketitle

\begin{center}
\textbf{Certificate}
\end{center}
This is to certify that the report titled \textit{Design of a Rainwater Harvesting System
for the Hostel Complex} is a record of work carried out by Tejashvi Kumawat under my
supervision.

\bigskip
\noindent Prof. Sumeet K Sinha \hfill Date: \underline{\hspace{3cm}}

\newpage
\begin{abstract}
The hostel complex consumes 420 kL of water a day, 30\% of it bought from tankers in
summer. This project sizes a rooftop harvesting and recharge system for 18,600 m$^2$ of
roof. The design captures 9.8 million litres a year and recharges the aquifer through
six wells, paying back its cost in 4.2 years.
\end{abstract}

\tableofcontents
\newpage

\section{Introduction}
\subsection{Background}
Groundwater levels on campus have fallen by 0.6 m per year since 2015.
\subsection{Objectives}
\begin{enumerate}
  \item Estimate the harvestable rainfall from hostel roofs.
  \item Size gutters, pipes, filters, storage and recharge wells.
  \item Estimate cost and payback.
\end{enumerate}

\section{Literature Review}
Summarise standards (CGWB manual, IS 15797) and earlier campus studies here.

\section{Methodology}
\subsection{Rainfall analysis}
Annual runoff volume:
\begin{equation}
  V = C \cdot P \cdot A,
\end{equation}
with runoff coefficient $C = 0.85$, annual rainfall $P = 0.62$ m and roof area $A$.
\subsection{Component design}
Describe gutters, first-flush diverters, filters and recharge wells.

\section{Results}
\begin{table}[h]
\centering
\begin{tabular}{|l|r|r|}
\hline
Block & Roof area (m$^2$) & Runoff (kL/yr) \\
\hline
Hostel A & 4,200 & 2,213 \\
Hostel B & 5,100 & 2,688 \\
Hostel C & 9,300 & 4,901 \\
\hline
\textbf{Total} & \textbf{18,600} & \textbf{9,802} \\
\hline
\end{tabular}
\caption{Harvestable runoff by block}
\end{table}

\section{Cost Estimate}
Total cost: INR 18.4 lakh; annual saving: INR 4.4 lakh; payback: 4.2 years.

\section{Conclusions and Future Work}
The system is feasible and economical. Future work: real-time level sensors and
greywater reuse.

\section*{References}
\begin{enumerate}
  \item Central Ground Water Board, \textit{Manual on Artificial Recharge of Ground Water}, 2007.
  \item BIS, \textit{IS 15797: Roof Top Rainwater Harvesting -- Guidelines}, 2008.
\end{enumerate}

\end{document}
''';

const lectureNotesMd = r'''# Lecture 7 — Eigenvalues and Eigenvectors
*Linear Algebra · 6 October 2026*

---

## 1. Definition
A non-zero vector $v$ is an **eigenvector** of a square matrix $A$ if

$$
A v = \lambda v
$$

for some scalar $\lambda$, called the **eigenvalue**.

## 2. Finding eigenvalues
Solve the **characteristic equation**:

$$
\det(A - \lambda I) = 0
$$

> **Example.** For $A = \begin{pmatrix} 2 & 1 \\ 1 & 2 \end{pmatrix}$,
> $\det(A-\lambda I) = (2-\lambda)^2 - 1 = 0$, so $\lambda = 1$ or $\lambda = 3$.

## 3. Properties
| Property | Statement |
|----------|-----------|
| Trace | $\sum \lambda_i = \operatorname{tr}(A)$ |
| Determinant | $\prod \lambda_i = \det A$ |
| Symmetric $A$ | eigenvalues are real, eigenvectors orthogonal |

## 4. Diagonalisation
If $A$ has $n$ independent eigenvectors, $A = P D P^{-1}$ where $D$ holds the eigenvalues.

## Key takeaways
- [x] Eigenvectors keep their direction under $A$.
- [x] Eigenvalues come from $\det(A-\lambda I)=0$.
- [ ] Practise: problems 7.1 – 7.6 from the textbook.
''';
