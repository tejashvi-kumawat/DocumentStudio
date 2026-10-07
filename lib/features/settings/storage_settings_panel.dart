import 'dart:async';

import 'package:document_studio/core/storage/storage_cache_manager.dart';
import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

String formatStorageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

/// Settings › Storage: usage per area of the app's storage box + Clear cache.
class StorageSettingsPanel extends StatefulWidget {
  const StorageSettingsPanel({super.key});

  @override
  State<StorageSettingsPanel> createState() => _StorageSettingsPanelState();
}

class _StorageSettingsPanelState extends State<StorageSettingsPanel> {
  StorageUsage? _usage;
  bool _loading = true;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    StorageUsage? usage;
    try {
      usage = await StorageCacheManager.instance.usage();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _loading = false;
    });
  }

  Future<void> _clearCache() async {
    final usage = _usage;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cache?'),
        content: Text(
          'Removes thumbnails, rendered pages, OCR and text-index caches'
          '${usage == null ? '' : ' (${formatStorageBytes(usage.cacheTotal)})'}. '
          'Your documents, signatures, stamps and digital IDs are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear cache'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _clearing = true);
    await StorageCacheManager.instance.clearCaches();
    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Cache cleared')));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final usage = _usage;
    return DsToolPanel(
      title: 'Storage',
      subtitle: 'Document Studio keeps its files in its own private folder',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading && usage == null)
            const Padding(
              padding: EdgeInsets.all(DsSpacing.md),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (usage == null)
            Text(
              'Storage usage is unavailable on this device.',
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total ${formatStorageBytes(usage.total)}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  'Cache ${formatStorageBytes(usage.cacheTotal)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DsSpacing.sm),
            for (final area in StorageArea.values)
              _UsageRow(
                area: area,
                bytes: usage.bytesByArea[area] ?? 0,
                total: usage.total,
                limit: StorageCacheManager.limits[area],
              ),
            const SizedBox(height: DsSpacing.sm),
            _BudgetRow(onChanged: _refresh),
            _LocationRow(path: usage.rootPath),
            if (usage.cacheRootPath != usage.rootPath)
              _LocationRow(path: usage.cacheRootPath, label: 'Cache folder'),
          ],
          const SizedBox(height: DsSpacing.md),
          Wrap(
            spacing: DsSpacing.sm,
            runSpacing: DsSpacing.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: _clearing || _loading ? null : _clearCache,
                icon: _clearing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('Clear cache'),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.area,
    required this.bytes,
    required this.total,
    this.limit,
  });

  final StorageArea area;
  final int bytes;
  final int total;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final cap = limit;
    final fraction = cap != null
        ? (bytes / cap).clamp(0.0, 1.0)
        : total == 0
        ? 0.0
        : (bytes / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  area.label,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                cap == null
                    ? formatStorageBytes(bytes)
                    : '${formatStorageBytes(bytes)} / ${formatStorageBytes(cap)}',
                style: theme.textTheme.labelMedium?.copyWith(color: secondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 3,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.path, this.label = 'Location'});

  final String path;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label: $path',
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: 'Copy path',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          onPressed: () => Clipboard.setData(ClipboardData(text: path)),
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    );
  }
}

/// Cache size limit picker: automatic or a fixed number of GB.
class _BudgetRow extends StatefulWidget {
  const _BudgetRow({required this.onChanged});

  final Future<void> Function() onChanged;

  @override
  State<_BudgetRow> createState() => _BudgetRowState();
}

class _BudgetRowState extends State<_BudgetRow> {
  static const _choices = [0, 1, 2, 4, 6, 8, 12, 16, 32];
  int _gb = 0;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() => _gb = p.getInt(StorageCacheManager.budgetPrefKey) ?? 0);
      }
    });
  }

  Future<void> _set(int gb) async {
    setState(() => _gb = gb);
    final p = await SharedPreferences.getInstance();
    await p.setInt(StorageCacheManager.budgetPrefKey, gb);
    StorageCacheManager.setUserGb(gb);
    await StorageCacheManager.instance.startupMaintenance();
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.sm),
      child: Row(
        children: [
          const Expanded(
            child: Text('Cache size limit (rendered pages, OCR, thumbnails)'),
          ),
          DropdownButton<int>(
            value: _choices.contains(_gb) ? _gb : 0,
            items: [
              for (final c in _choices)
                DropdownMenuItem(
                  value: c,
                  child: Text(c == 0 ? 'Automatic' : '$c GB'),
                ),
            ],
            onChanged: (v) {
              if (v != null) _set(v);
            },
          ),
        ],
      ),
    );
  }
}
