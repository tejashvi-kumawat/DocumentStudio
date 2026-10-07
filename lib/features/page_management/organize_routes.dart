import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/organize_tool_launch.dart';

import 'package:document_studio/features/page_management/organize_hub_screen.dart';
import 'package:document_studio/features/page_management/organize_screen.dart';
import 'package:document_studio/features/page_management/organize_tool_catalog.dart';
import 'package:document_studio/features/page_management/tools/delete_pages_tool_screen.dart';
import 'package:document_studio/features/page_management/tools/duplicate_tool_screen.dart';
import 'package:document_studio/features/page_management/tools/extract_tool_screen.dart';
import 'package:document_studio/features/page_management/tools/merge_tool_screen.dart';
import 'package:document_studio/features/page_management/tools/page_workspace_tool_screen.dart';
import 'package:document_studio/features/page_management/tools/reorder_tool_screen.dart';

import 'package:document_studio/features/page_management/tools/split_tool_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

List<RouteBase> buildOrganizeRoutes({
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return [
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: OrganizeToolCatalog.hubPath,
      builder: (context, state) {
        final launch = OrganizeToolLaunch.fromExtra(state.extra);
        if (launch != null) {
          return OrganizeScreen(initialFile: launch.file);
        }
        return const OrganizeHubScreen();
      },
      routes: [
        GoRoute(
          path: 'merge',
          builder: (_, state) {
            final launch = OrganizeToolLaunch.fromExtra(state.extra);
            if (launch != null) {
              return MergeToolScreen(initialFiles: [launch.file]);
            }
            final extra = state.extra;
            final initialFiles = extra is List<LocalFileRef>
                ? extra
                : const <LocalFileRef>[];
            return MergeToolScreen(initialFiles: initialFiles);
          },
        ),
        GoRoute(
          path: 'split',
          builder: (_, state) {
            final launch = OrganizeToolLaunch.fromExtra(state.extra);
            return SplitToolScreen(
              initialFile: launch?.file,
              initialPassword: launch?.password,
            );
          },
        ),
        GoRoute(
          path: 'extract',
          builder: (_, state) {
            final launch = OrganizeToolLaunch.fromExtra(state.extra);
            return ExtractToolScreen(
              initialFile: launch?.file,
              initialPassword: launch?.password,
            );
          },
        ),
        GoRoute(
          path: 'reorder',
          builder: (_, state) {
            final launch = OrganizeToolLaunch.fromExtra(state.extra);
            return ReorderToolScreen(
              initialFile: launch?.file,
              initialPassword: launch?.password,
            );
          },
        ),
        GoRoute(
          path: 'delete',
          builder: (_, state) {
            final launch = OrganizeToolLaunch.fromExtra(state.extra);
            return DeletePagesToolScreen(
              initialFile: launch?.file,
              initialPassword: launch?.password,
            );
          },
        ),
        GoRoute(
          path: 'duplicate',
          builder: (_, state) {
            final launch = OrganizeToolLaunch.fromExtra(state.extra);
            return DuplicateToolScreen(
              initialFile: launch?.file,
              initialPassword: launch?.password,
            );
          },
        ),
        for (final id in [
          'rotate',
          'reverse',
          'odd-pages',
          'even-pages',
          'insert',
        ])
          GoRoute(
            path: id,
            builder: (_, state) {
              final launch = OrganizeToolLaunch.fromExtra(state.extra);
              return PageWorkspaceToolScreen(
                toolId: id,
                initialFile: launch?.file,
                initialPassword: launch?.password,
              );
            },
          ),
      ],
    ),
  ];
}
