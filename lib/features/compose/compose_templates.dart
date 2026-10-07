import 'package:document_studio/features/compose/compose_model.dart';
import 'package:document_studio/features/compose/compose_starters.dart';
import 'package:document_studio/features/compose/templates/academic_templates.dart';
import 'package:document_studio/features/compose/templates/business_templates.dart';
import 'package:document_studio/features/compose/templates/personal_templates.dart';
import 'package:document_studio/features/compose/templates/resume_templates.dart';
import 'package:flutter/material.dart';

/// Template groups shown in the gallery.
enum TemplateCategory {
  resume('Résumé & CV', Icons.badge_outlined),
  letters('Letters', Icons.mail_outline),
  academic('Academic', Icons.school_outlined),
  business('Business', Icons.business_center_outlined),
  personal('Personal', Icons.favorite_border),
  blank('Blank & starters', Icons.note_add_outlined);

  const TemplateCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// A ready-made document to start from.
class ComposeTemplate {
  const ComposeTemplate(
    this.name,
    this.description,
    this.source, {
    this.id = '',
    this.category = TemplateCategory.blank,
    this.language = ComposeLanguage.markdown,
  });

  final String id;
  final String name;
  final String description;
  final String source;
  final TemplateCategory category;
  final ComposeLanguage language;
}

/// Every template, grouped by [TemplateCategory].
final List<ComposeTemplate> kComposeTemplates = [
  // Résumé & CV
  const ComposeTemplate(
    'Classic résumé',
    'One page, clean rules, dates on the right — the most common format',
    resumeClassicTex,
    id: 'resume-classic',
    category: TemplateCategory.resume,
    language: ComposeLanguage.latex,
  ),
  const ComposeTemplate(
    'Modern résumé',
    'Bold headings, skills table, links — easy to edit in Markdown',
    resumeModernMd,
    id: 'resume-modern',
    category: TemplateCategory.resume,
    language: ComposeLanguage.markdown,
  ),
  const ComposeTemplate(
    'Executive résumé',
    'Coloured headings and competency grid for senior roles',
    resumeExecutiveHtml,
    id: 'resume-exec',
    category: TemplateCategory.resume,
    language: ComposeLanguage.html,
  ),
  const ComposeTemplate(
    'Academic CV',
    'Research, publications, grants, teaching, service',
    resumeAcademicTex,
    id: 'cv-academic',
    category: TemplateCategory.resume,
    language: ComposeLanguage.latex,
  ),
  const ComposeTemplate(
    'Cover letter (formal)',
    'Job application letter that pairs with the classic résumé',
    coverLetterTex,
    id: 'cover-tex',
    category: TemplateCategory.resume,
    language: ComposeLanguage.latex,
  ),
  const ComposeTemplate(
    'Cover letter (simple)',
    'Short, friendly application letter',
    coverLetterMd,
    id: 'cover-md',
    category: TemplateCategory.resume,
    language: ComposeLanguage.markdown,
  ),
  // Letters
  const ComposeTemplate(
    'Formal letter',
    'Request / application to an office or institution',
    formalLetterTex,
    id: 'letter-formal',
    category: TemplateCategory.letters,
    language: ComposeLanguage.latex,
  ),
  const ComposeTemplate(
    'Business letter',
    'Company letter with sender block, subject and enclosure',
    businessLetterHtml,
    id: 'letter-business',
    category: TemplateCategory.letters,
    language: ComposeLanguage.html,
  ),
  const ComposeTemplate(
    'Recommendation letter',
    'Reference letter for admissions or jobs',
    recommendationMd,
    id: 'letter-reco',
    category: TemplateCategory.letters,
    language: ComposeLanguage.markdown,
  ),
  // Academic
  const ComposeTemplate(
    'Assignment / homework',
    'Problems with worked solutions and boxed answers',
    assignmentTex,
    id: 'assignment',
    category: TemplateCategory.academic,
    language: ComposeLanguage.latex,
  ),
  const ComposeTemplate(
    'Lab report',
    'Aim, apparatus, theory, observations table, results',
    labReportTex,
    id: 'lab-report',
    category: TemplateCategory.academic,
    language: ComposeLanguage.latex,
  ),
  const ComposeTemplate(
    'Research paper',
    'Abstract, sections, equations, results table, references',
    researchPaperTex,
    id: 'paper',
    category: TemplateCategory.academic,
    language: ComposeLanguage.latex,
  ),
  const ComposeTemplate(
    'Project report / thesis',
    'Title page, certificate, abstract, contents, chapters',
    projectReportTex,
    id: 'project-report',
    category: TemplateCategory.academic,
    language: ComposeLanguage.latex,
  ),
  const ComposeTemplate(
    'Lecture notes',
    'Definitions, examples, maths and a summary checklist',
    lectureNotesMd,
    id: 'lecture-notes',
    category: TemplateCategory.academic,
    language: ComposeLanguage.markdown,
  ),
  // Business
  const ComposeTemplate(
    'Invoice (GST)',
    'Items, taxes, totals, bank details and terms',
    invoiceHtml,
    id: 'invoice',
    category: TemplateCategory.business,
    language: ComposeLanguage.html,
  ),
  const ComposeTemplate(
    'Quotation / estimate',
    'Priced items, validity and payment terms',
    quotationHtml,
    id: 'quotation',
    category: TemplateCategory.business,
    language: ComposeLanguage.html,
  ),
  const ComposeTemplate(
    'Project proposal',
    'Summary, scope, phases, budget, risks',
    proposalMd,
    id: 'proposal',
    category: TemplateCategory.business,
    language: ComposeLanguage.markdown,
  ),
  const ComposeTemplate(
    'Meeting minutes',
    'Attendees, decisions and an action-item table',
    meetingMinutesMd,
    id: 'minutes',
    category: TemplateCategory.business,
    language: ComposeLanguage.markdown,
  ),
  const ComposeTemplate(
    'Memo',
    'Internal announcement with To / From / Subject block',
    memoHtml,
    id: 'memo',
    category: TemplateCategory.business,
    language: ComposeLanguage.html,
  ),
  // Personal
  const ComposeTemplate(
    'Weekly planner',
    'Goals, day-by-day schedule and to-dos',
    weeklyPlannerMd,
    id: 'planner',
    category: TemplateCategory.personal,
    language: ComposeLanguage.markdown,
  ),
  const ComposeTemplate(
    'Travel itinerary',
    'Day plan, bookings, packing list and budget',
    travelItineraryMd,
    id: 'itinerary',
    category: TemplateCategory.personal,
    language: ComposeLanguage.markdown,
  ),
  const ComposeTemplate(
    'Recipe card',
    'Ingredients, method, tips and nutrition',
    recipeMd,
    id: 'recipe',
    category: TemplateCategory.personal,
    language: ComposeLanguage.markdown,
  ),
  const ComposeTemplate(
    'Event invitation',
    'Centred invitation with date, venue and RSVP',
    invitationHtml,
    id: 'invitation',
    category: TemplateCategory.personal,
    language: ComposeLanguage.html,
  ),
  // Blank & starters
  ComposeTemplate(
    'LaTeX article',
    'Everything the LaTeX engine supports, in one document',
    composeStarter(ComposeLanguage.latex),
    id: 'start-tex',
    category: TemplateCategory.blank,
    language: ComposeLanguage.latex,
  ),
  ComposeTemplate(
    'Markdown overview',
    'Headings, lists, tables, code and maths',
    composeStarter(ComposeLanguage.markdown),
    id: 'start-md',
    category: TemplateCategory.blank,
    language: ComposeLanguage.markdown,
  ),
  ComposeTemplate(
    'HTML overview',
    'Styles, lists, tables and maths in HTML',
    composeStarter(ComposeLanguage.html),
    id: 'start-html',
    category: TemplateCategory.blank,
    language: ComposeLanguage.html,
  ),
  const ComposeTemplate(
    'Blank LaTeX',
    'Empty article skeleton',
    '\\documentclass[11pt,a4paper]{article}\n\\usepackage{amsmath}\n\n\\begin{document}\n\n\\end{document}\n',
    id: 'blank-tex',
    category: TemplateCategory.blank,
    language: ComposeLanguage.latex,
  ),
  const ComposeTemplate(
    'Blank Markdown',
    'Empty page',
    '# Title\n\n',
    id: 'blank-md',
    category: TemplateCategory.blank,
    language: ComposeLanguage.markdown,
  ),
];

ComposeTemplate? templateById(String id) {
  for (final t in kComposeTemplates) {
    if (t.id == id) return t;
  }
  return null;
}

/// Templates written in [l] (for the editor's Templates menu).
List<ComposeTemplate> templatesFor(ComposeLanguage l) => [
  for (final t in kComposeTemplates)
    if (t.language == l) t,
];
