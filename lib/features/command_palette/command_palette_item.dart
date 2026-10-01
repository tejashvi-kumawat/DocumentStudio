import 'package:flutter/material.dart';

class CommandPaletteItem {
  const CommandPaletteItem({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.onInvoke,
    this.keywords = const [],
  });

  final String id;
  final String label;
  final String subtitle;
  final VoidCallback onInvoke;
  final List<String> keywords;
}
