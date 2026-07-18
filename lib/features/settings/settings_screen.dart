import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/features/command_palette/ds_command_palette.dart';
import 'package:document_studio/features/home/home_shell_action_bar.dart';
import 'package:document_studio/features/settings/local_qpdf_engine_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final settingsAsync = ref.watch(settingsRepositoryProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final contentInset = dsShellContentHorizontalPadding(width);
    final compact = width < DsSpacing.breakpointCompact;

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (settings) => ColoredBox(
        color: DsColors.groupedBackground(theme.brightness),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HomeShellActionBar(),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
            padding: EdgeInsets.fromLTRB(
              contentInset,
              compact ? DsSpacing.md : DsSpacing.lg,
              contentInset,
              DsSpacing.shellPageBottom,
            ),
            sliver: SliverToBoxAdapter(
              child: DsShellPageFrame(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DsShellPageHeader(
                      title: 'Settings',
                      subtitle: compact
                          ? null
                          : 'Appearance, privacy, and about this app.',
                      compactTitle: compact,
                    ),
                    DsToolFormLayout(
                      padding: EdgeInsets.zero,
                      primary: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DsToolPanel(
                            title: 'Appearance',
                            child: SegmentedButton<ThemeMode>(
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  label: Text('System'),
                                  icon: Icon(Icons.brightness_auto),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  label: Text('Light'),
                                  icon: Icon(Icons.light_mode),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  label: Text('Dark'),
                                  icon: Icon(Icons.dark_mode),
                                ),
                              ],
                              selected: {themeMode},
                              onSelectionChanged: (s) {
                                ref
                                    .read(themeModeProvider.notifier)
                                    .setMode(s.first);
                              },
                              style: ButtonStyle(
                                visualDensity: compact
                                    ? VisualDensity.compact
                                    : VisualDensity.standard,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: compact ? DsSpacing.md : DsSpacing.lg,
                          ),
                          DsToolPanel(
                            title: 'Privacy',
                            subtitle:
                                'Document Studio never uploads your files',
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                SwitchListTile.adaptive(
                                  dense: compact,
                                  visualDensity: compact
                                      ? VisualDensity.compact
                                      : VisualDensity.standard,
                                  title: const Text('Strict offline mode'),
                                  subtitle: const Text(
                                    'Block app-initiated network access (recommended).',
                                  ),
                                  value: settings.strictOffline,
                                  onChanged: settings.setStrictOffline,
                                ),
                                const Divider(height: 1),
                                _PrivacyRow(
                                  icon: Icons.cloud_off,
                                  label: 'Cloud document processing',
                                  value: 'Off',
                                  ok: true,
                                  dense: compact,
                                ),
                                _PrivacyRow(
                                  icon: Icons.analytics_outlined,
                                  label: 'Document content analytics',
                                  value: 'Off',
                                  ok: true,
                                  dense: compact,
                                ),
                                _PrivacyRow(
                                  icon: Icons.storage,
                                  label: 'Local processing',
                                  value: 'On',
                                  ok: true,
                                  dense: compact,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: compact ? DsSpacing.md : DsSpacing.lg,
                          ),
                          const LocalQpdfEnginePanel(),
                          DsToolPanel(
                            title: 'About',
                            child: ListTile(
                              dense: compact,
                              visualDensity: compact
                                  ? VisualDensity.compact
                                  : VisualDensity.standard,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.info_outline,
                                color: theme.colorScheme.primary,
                                size: compact ? 20 : 24,
                              ),
                              title: const Text('Document Studio'),
                              subtitle: const Text(
                                'Version 1.0.0 · Offline-first workspace',
                              ),
                            ),
                          ),
                          const SizedBox(height: DsSpacing.md),
                          Text(
                            'Engine notices: PDFium, and other libraries — see Legal in a future release.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? DsColors.textSecondaryDark
                                  : DsColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                      sidebar: DsToolPanel(
                        title: 'Quick actions',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  showDocumentStudioCommandPalette(context),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size(
                                  0,
                                  compact
                                      ? DsSpacing.compactTouchTarget
                                      : 40,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.manage_search, size: 18),
                              label: const Text('Command palette'),
                            ),
                            const SizedBox(height: DsSpacing.sm),
                            Text(
                              'Ctrl/⌘ K from any shell tab',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? DsColors.textSecondaryDark
                                    : DsColors.textSecondaryLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ok,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: dense,
      visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
      leading: Icon(icon, size: dense ? 20 : 24),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              value,
              style: Theme.of(context).textTheme.labelLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: DsSpacing.sm),
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            color: ok ? DsColors.success : DsColors.error,
            size: 20,
          ),
        ],
      ),
    );
  }
}
