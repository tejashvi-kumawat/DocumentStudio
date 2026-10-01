import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/storage/persisted_document_access.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recent PDFs and (on Android) PDFs from folders the user granted once via SAF.
///
/// Remembers paths / tree URIs — does not copy every PDF into app storage.
class OrganizeAccessibleFilesList extends ConsumerWidget {
  const OrganizeAccessibleFilesList({
    super.key,
    required this.onOpen,
    this.maxRecents = 8,
  });

  final void Function(LocalFileRef file) onOpen;
  final int maxRecents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final recents = ref.watch(recentsProvider).asData?.value ?? const [];
    final pdfs = maxRecents <= 0
        ? const <LocalFileRef>[]
        : recents.where((f) => f.isPdf).take(maxRecents).toList();
    final grantsAsync = ref.watch(persistedDocumentGrantsProvider);

    if (pdfs.isEmpty && !Platform.isAndroid) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pdfs.isNotEmpty) ...[
          Text(
            'Recent PDFs',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
          const SizedBox(height: DsSpacing.xs),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < pdfs.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: border),
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.picture_as_pdf_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      pdfs[i].displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onOpen(pdfs[i]),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: DsSpacing.md),
        ],
        if (Platform.isAndroid)
          grantsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (grants) => _AndroidGrantedFolders(
              grants: grants,
              border: border,
              secondary: secondary,
              onOpen: onOpen,
              onAddFolder: () async {
                final grant = await PersistedDocumentAccess.pickPersistableFolder();
                if (grant == null) return;
                await ref
                    .read(persistedDocumentGrantsProvider.notifier)
                    .addGrant(grant);
              },
              onRemove: (uri) => ref
                  .read(persistedDocumentGrantsProvider.notifier)
                  .removeGrant(uri),
            ),
          ),
      ],
    );
  }
}

class _AndroidGrantedFolders extends StatefulWidget {
  const _AndroidGrantedFolders({
    required this.grants,
    required this.border,
    required this.secondary,
    required this.onOpen,
    required this.onAddFolder,
    required this.onRemove,
  });

  final List<PersistedFolderGrant> grants;
  final Color border;
  final Color secondary;
  final void Function(LocalFileRef file) onOpen;
  final Future<void> Function() onAddFolder;
  final Future<void> Function(String treeUri) onRemove;

  @override
  State<_AndroidGrantedFolders> createState() => _AndroidGrantedFoldersState();
}

class _AndroidGrantedFoldersState extends State<_AndroidGrantedFolders> {
  String? _expandedUri;
  List<LocalFileRef>? _listing;
  bool _listingBusy = false;

  Future<void> _toggle(PersistedFolderGrant grant) async {
    if (_expandedUri == grant.treeUri) {
      setState(() {
        _expandedUri = null;
        _listing = null;
      });
      return;
    }
    setState(() {
      _expandedUri = grant.treeUri;
      _listingBusy = true;
      _listing = null;
    });
    final files = await PersistedDocumentAccess.listPdfsInFolder(grant.treeUri);
    if (!mounted) return;
    setState(() {
      _listing = files;
      _listingBusy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Folders you granted',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: widget.secondary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: widget.onAddFolder,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Add folder'),
            ),
          ],
        ),
        const SizedBox(height: DsSpacing.xs),
        if (widget.grants.isEmpty)
          Text(
            'Grant a folder once (Storage Access Framework). PDFs stay in place; '
            'the app remembers the URI.',
            style: theme.textTheme.bodySmall?.copyWith(color: widget.secondary),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: widget.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < widget.grants.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: widget.border),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      widget.grants[i].displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Forget folder',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () =>
                          widget.onRemove(widget.grants[i].treeUri),
                    ),
                    onTap: () => _toggle(widget.grants[i]),
                  ),
                  if (_expandedUri == widget.grants[i].treeUri)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _listingBusy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          : (_listing == null || _listing!.isEmpty)
                              ? Text(
                                  'No PDFs found in this folder.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: widget.secondary,
                                  ),
                                )
                              : Column(
                                  children: [
                                    for (final f in _listing!)
                                      ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.only(
                                          left: 24,
                                        ),
                                        leading: Icon(
                                          Icons.picture_as_pdf_outlined,
                                          color: theme.colorScheme.primary,
                                          size: 20,
                                        ),
                                        title: Text(
                                          f.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () => widget.onOpen(f),
                                      ),
                                  ],
                                ),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
