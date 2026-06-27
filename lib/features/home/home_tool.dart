import 'package:flutter/material.dart';

enum HomeToolAvailability { available, comingSoon, blocked }

/// How a tool expects document input (home / tools catalog badges).
enum HomeToolDocumentEntry {
  requiresOpenPdf('Requires open PDF'),
  pickFile('Pick file'),
  standalone('Works standalone');

  const HomeToolDocumentEntry(this.badgeLabel);
  final String badgeLabel;
}

enum HomeToolCategory {
  createConvert('Create & convert'),
  organizePages('Organize pages'),
  optimizeProtect('Optimize & protect'),
  automation('Automation');

  const HomeToolCategory(this.title);
  final String title;
}

class HomeTool {
  const HomeTool({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.category,
    required this.availability,
    required this.documentEntry,
    this.onTap,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final HomeToolCategory category;
  final HomeToolAvailability availability;
  final HomeToolDocumentEntry documentEntry;
  final VoidCallback? onTap;
}
