import 'package:flutter/material.dart';

enum OrganizeToolAvailability { available, comingSoon }

enum OrganizeToolGroup { composition, extraction, arrangement, format }

/// iLovePDF-style hub sections (group several [OrganizeToolGroup] rows).
enum OrganizeHubCategory { mergeSplit, organizePdf, pageFormat }

class OrganizeToolDefinition {
  const OrganizeToolDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.routePath,
    required this.group,
    this.availability = OrganizeToolAvailability.available,
    this.inventoryIds = const [],
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final String routePath;
  final OrganizeToolGroup group;
  final OrganizeToolAvailability availability;
  final List<String> inventoryIds;
}

/// Authoritative tool-first entries for `/organize` (see FEATURE-INVENTORY DS-ORG-*).
class OrganizeToolCatalog {
  OrganizeToolCatalog._();

  static const hubPath = '/organize';

  static const tools = <OrganizeToolDefinition>[
    OrganizeToolDefinition(
      id: 'merge',
      label: 'Merge PDFs',
      description: 'Combine multiple PDFs in order into one file',
      icon: Icons.merge_type,
      routePath: '/organize/merge',
      group: OrganizeToolGroup.composition,
      inventoryIds: ['DS-ORG-001'],
    ),
    OrganizeToolDefinition(
      id: 'insert',
      label: 'Insert pages',
      description: 'Add pages from another PDF at chosen positions',
      icon: Icons.playlist_add,
      routePath: '/organize/insert',
      group: OrganizeToolGroup.composition,
      inventoryIds: ['DS-ORG-006'],
    ),
    OrganizeToolDefinition(
      id: 'replace',
      label: 'Replace pages',
      description: 'Swap selected pages with pages from another file',
      icon: Icons.swap_horiz,
      routePath: '/organize/replace',
      group: OrganizeToolGroup.composition,
      inventoryIds: ['DS-ORG-006'],
    ),
    OrganizeToolDefinition(
      id: 'move_between',
      label: 'Move between documents',
      description: 'Move pages from one PDF into another',
      icon: Icons.drive_file_move_outline,
      routePath: '/organize/move-between',
      group: OrganizeToolGroup.composition,
      inventoryIds: ['DS-ORG-006-A'],
    ),
    OrganizeToolDefinition(
      id: 'extract',
      label: 'Extract pages',
      description: 'Save selected pages as a new PDF',
      icon: Icons.content_cut,
      routePath: '/organize/extract',
      group: OrganizeToolGroup.extraction,
      inventoryIds: ['DS-ORG-003'],
    ),
    OrganizeToolDefinition(
      id: 'split',
      label: 'Split PDF',
      description: 'Divide a PDF into multiple files by range or every N pages',
      icon: Icons.call_split,
      routePath: '/organize/split',
      group: OrganizeToolGroup.extraction,
      inventoryIds: ['DS-ORG-002', 'DS-ORG-002-A'],
    ),
    OrganizeToolDefinition(
      id: 'odd',
      label: 'Extract odd pages',
      description: 'Export pages 1, 3, 5… as a new PDF',
      icon: Icons.filter_1_outlined,
      routePath: '/organize/odd-pages',
      group: OrganizeToolGroup.extraction,
      inventoryIds: ['DS-ORG-010'],
    ),
    OrganizeToolDefinition(
      id: 'even',
      label: 'Extract even pages',
      description: 'Export pages 2, 4, 6… as a new PDF',
      icon: Icons.filter_2_outlined,
      routePath: '/organize/even-pages',
      group: OrganizeToolGroup.extraction,
      inventoryIds: ['DS-ORG-010'],
    ),
    OrganizeToolDefinition(
      id: 'reorder',
      label: 'Reorder pages',
      description: 'Drag thumbnails to change page order, then export',
      icon: Icons.view_module_outlined,
      routePath: '/organize/reorder',
      group: OrganizeToolGroup.arrangement,
      inventoryIds: ['DS-ORG-005'],
    ),
    OrganizeToolDefinition(
      id: 'reverse',
      label: 'Reverse order',
      description: 'Flip the page sequence end-to-end',
      icon: Icons.swap_vert,
      routePath: '/organize/reverse',
      group: OrganizeToolGroup.arrangement,
      inventoryIds: ['DS-ORG-008'],
    ),
    OrganizeToolDefinition(
      id: 'duplicate',
      label: 'Duplicate pages',
      description: 'Copy selected pages within the document',
      icon: Icons.copy_all_outlined,
      routePath: '/organize/duplicate',
      group: OrganizeToolGroup.arrangement,
      inventoryIds: ['DS-ORG-006'],
    ),
    OrganizeToolDefinition(
      id: 'delete',
      label: 'Delete pages',
      description: 'Remove unwanted pages and save the rest',
      icon: Icons.delete_outline,
      routePath: '/organize/delete',
      group: OrganizeToolGroup.arrangement,
      inventoryIds: ['DS-ORG-004'],
    ),
    OrganizeToolDefinition(
      id: 'rotate',
      label: 'Rotate pages',
      description: 'Rotate selected pages 90° and save',
      icon: Icons.rotate_right,
      routePath: '/organize/rotate',
      group: OrganizeToolGroup.arrangement,
      inventoryIds: ['DS-ORG-007'],
    ),
    OrganizeToolDefinition(
      id: 'blank',
      label: 'Add blank page',
      description: 'Insert empty pages at chosen positions',
      icon: Icons.note_add_outlined,
      routePath: '/organize/blank-page',
      group: OrganizeToolGroup.format,
      inventoryIds: ['DS-ORG-006-B'],
    ),
    OrganizeToolDefinition(
      id: 'crop',
      label: 'Crop pages',
      description: 'Trim page margins and boxes',
      icon: Icons.crop,
      routePath: '/organize/crop',
      group: OrganizeToolGroup.format,
      inventoryIds: ['DS-ORG-012'],
    ),
    OrganizeToolDefinition(
      id: 'resize',
      label: 'Resize page',
      description: 'Change media box and orientation',
      icon: Icons.aspect_ratio,
      routePath: '/organize/resize',
      group: OrganizeToolGroup.format,
      inventoryIds: ['DS-ORG-013'],
    ),
  ];

  static String groupTitle(OrganizeToolGroup g) => switch (g) {
    OrganizeToolGroup.composition => 'Page composition',
    OrganizeToolGroup.extraction => 'Extract & split',
    OrganizeToolGroup.arrangement => 'Arrange pages',
    OrganizeToolGroup.format => 'Page format',
  };

  static List<OrganizeToolDefinition> forGroup(OrganizeToolGroup g) =>
      tools.where((t) => t.group == g).toList();

  static OrganizeHubCategory hubCategoryFor(OrganizeToolDefinition tool) {
    switch (tool.id) {
      case 'merge':
      case 'split':
        return OrganizeHubCategory.mergeSplit;
      case 'blank':
      case 'crop':
      case 'resize':
        return OrganizeHubCategory.pageFormat;
      default:
        return OrganizeHubCategory.organizePdf;
    }
  }

  static String hubCategoryTitle(OrganizeHubCategory category) =>
      switch (category) {
        OrganizeHubCategory.mergeSplit => 'Merge & split',
        OrganizeHubCategory.organizePdf => 'Organize PDF',
        OrganizeHubCategory.pageFormat => 'Page format',
      };

  static List<OrganizeToolDefinition> forHubCategory(OrganizeHubCategory c) =>
      tools.where((t) => hubCategoryFor(t) == c).toList();

  static const hubCategoriesInOrder = [
    OrganizeHubCategory.mergeSplit,
    OrganizeHubCategory.organizePdf,
    OrganizeHubCategory.pageFormat,
  ];
}
