import 'package:flutter/material.dart';

enum ToolAvailability { available, comingSoon, blocked, desktopOnly }

class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.label,
    required this.availability,
    this.route,
  });

  final String id;
  final String label;
  final ToolAvailability availability;
  final String? route;
}

/// Central registry for tools — UI queries availability here (ADR: single registry).
class ToolRegistry {
  ToolRegistry._();

  static final instance = ToolRegistry._();

  final List<ToolDefinition> tools = const [
    ToolDefinition(
      id: 'open_pdf',
      label: 'Open PDF',
      availability: ToolAvailability.available,
      route: '/',
    ),
    ToolDefinition(
      id: 'viewer',
      label: 'PDF viewer',
      availability: ToolAvailability.available,
      route: '/viewer',
    ),
    ToolDefinition(
      id: 'merge',
      label: 'Merge PDF',
      availability: ToolAvailability.blocked,
    ),
    ToolDefinition(
      id: 'compress',
      label: 'Compress',
      availability: ToolAvailability.comingSoon,
    ),
  ];

  ToolAvailability availabilityFor(String id) {
    return tools
            .firstWhere(
              (t) => t.id == id,
              orElse: () => const ToolDefinition(
                id: 'unknown',
                label: 'Unknown',
                availability: ToolAvailability.comingSoon,
              ),
            )
            .availability;
  }

  void showUnavailableSnackBar(BuildContext context, String toolId) {
    final a = availabilityFor(toolId);
    final msg = switch (a) {
      ToolAvailability.blocked =>
        '$toolId is blocked until the qpdf engine plugin is integrated.',
      ToolAvailability.desktopOnly =>
        '$toolId is available on desktop only.',
      _ => '$toolId is not available yet.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
