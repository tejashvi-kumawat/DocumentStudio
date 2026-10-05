import 'package:document_studio/features/settings/update_dialog.dart';
import 'package:document_studio/core/fonts/font_library.dart';
import 'package:document_studio/features/settings/storage_settings_panel.dart';
import 'package:document_studio/app/app_info.dart';
import 'package:document_studio/app/app_version.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/brand/ds_built_by.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/features/command_palette/ds_command_palette.dart';
import 'package:document_studio/features/home/home_shell_action_bar.dart';
import 'package:document_studio/features/settings/local_qpdf_engine_panel.dart';
import 'package:document_studio/features/settings/shortcuts_dialog.dart';
import 'package:document_studio/features/setup/desktop_document_tools_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:document_studio/core/settings/app_prefs.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings: only what matters — appearance, how documents open, privacy,
/// on-device tools, updates, and About.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final viewer = ref.watch(viewerPrefsProvider);
    final settingsAsync = ref.watch(settingsRepositoryProvider);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final contentInset = dsShellContentHorizontalPadding(width);
    final compact = width < DsSpacing.breakpointCompact;
    final muted = DsColors.textSecondary(theme.brightness);

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
                      child: _WideFrame(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DsShellPageHeader(
                              title: 'Settings',
                              compactTitle: compact,
                            ),
                            _Masonry(children: [
                            _Group(
                              title: 'Appearance',
                              children: [
                                _Row(
                                  label: 'Theme',
                                  trailing: SegmentedButton<ThemeMode>(
                                    showSelectedIcon: false,
                                    segments: const [
                                      ButtonSegment(
                                        value: ThemeMode.light,
                                        label: Text('Light'),
                                        icon: Icon(Icons.light_mode, size: 16),
                                      ),
                                      ButtonSegment(
                                        value: ThemeMode.dark,
                                        label: Text('Dark'),
                                        icon: Icon(Icons.dark_mode, size: 16),
                                      ),
                                      ButtonSegment(
                                        value: ThemeMode.system,
                                        label: Text('Auto'),
                                        icon: Icon(
                                          Icons.brightness_auto,
                                          size: 16,
                                        ),
                                      ),
                                    ],
                                    selected: {themeMode},
                                    onSelectionChanged: (s) => ref
                                        .read(themeModeProvider.notifier)
                                        .setMode(s.first),
                                    style: const ButtonStyle(
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            _Group(
                              title: 'Opening documents',
                              children: [
                                _Row(
                                  label: 'Zoom',
                                  hint: 'How a PDF fits when it opens',
                                  trailing: _Dropdown<String>(
                                    value: viewer.zoom,
                                    items: const {
                                      'fitWidth': 'Fit width',
                                      'fitPage': 'Fit page',
                                      'actual': 'Actual size (100%)',
                                    },
                                    onChanged: (v) => ref
                                        .read(viewerPrefsProvider.notifier)
                                        .setZoom(v),
                                  ),
                                ),
                                _Row(
                                  label: 'Page display',
                                  hint: 'Applies to newly opened documents',
                                  trailing: _Dropdown<String>(
                                    value: viewer.display,
                                    items: const {
                                      'continuous': 'Continuous scrolling',
                                      'singlePage': 'Single page',
                                      'twoPage': 'Two pages',
                                    },
                                    onChanged: (v) => ref
                                        .read(viewerPrefsProvider.notifier)
                                        .setDisplay(v),
                                  ),
                                ),
                              ],
                            ),
                            _Group(
                              title: 'Performance',
                              children: [
                                _Row(
                                  label: 'Page render quality',
                                  hint: 'Auto picks by your device. High is sharper, Fast is lighter.',
                                  trailing: _Dropdown<String>(
                                    value: viewer.quality,
                                    items: const {
                                      'auto': 'Auto',
                                      'high': 'High (sharper)',
                                      'fast': 'Fast (lighter)',
                                    },
                                    onChanged: (v) => ref
                                        .read(viewerPrefsProvider.notifier)
                                        .setQuality(v),
                                  ),
                                ),
                                _Row(
                                  label: 'Make scanned pages searchable',
                                  hint: 'Runs OCR quietly in the background '
                                      'when a scanned PDF opens, so text in '
                                      'images can be found and copied. Off by '
                                      'default; you can still scan on demand '
                                      'from Find.',
                                  trailing: _AppPrefSwitch(
                                    read: () => AppPrefs.autoOcr,
                                    write: AppPrefs.setAutoOcr,
                                  ),
                                ),
                              ],
                            ),
                            _Group(
                              title: 'Editing',
                              children: [
                                _Row(
                                  label: 'Font for new text',
                                  trailing: _Dropdown<String>(
                                    value: viewer.textFamily,
                                    items: const {
                                      'sans': 'Sans (Helvetica)',
                                      'serif': 'Serif (Times)',
                                      'mono': 'Mono (Courier)',
                                    },
                                    onChanged: (v) => ref
                                        .read(viewerPrefsProvider.notifier)
                                        .setTextFamily(v),
                                  ),
                                ),
                                _Row(
                                  label: 'Size for new text',
                                  trailing: _Dropdown<int>(
                                    value: const [10, 12, 14, 16, 18, 24]
                                        .reduce((a, b) =>
                                            (a - viewer.textSize).abs() <=
                                                    (b - viewer.textSize).abs()
                                                ? a
                                                : b),
                                    items: const {
                                      10: '10 pt',
                                      12: '12 pt',
                                      14: '14 pt',
                                      16: '16 pt',
                                      18: '18 pt',
                                      24: '24 pt',
                                    },
                                    onChanged: (v) => ref
                                        .read(viewerPrefsProvider.notifier)
                                        .setTextSize(v.toDouble()),
                                  ),
                                ),
                              ],
                            ),
                            const _FontsCard(),
                            _Group(
                              title: 'Documents & comments',
                              children: [
                                _Row(
                                  label: 'Embed fonts in edited text',
                                  hint: 'New and edited text looks identical '
                                      'everywhere (only the letters used '
                                      'are stored, a few KB).',
                                  trailing: _AppPrefSwitch(
                                    read: () => AppPrefs.embedFontsByDefault,
                                    write: AppPrefs.setEmbedFontsByDefault,
                                  ),
                                ),
                                _Row(
                                  label: 'Undo steps per document',
                                  hint: 'Large steps are kept on disk, '
                                      'not in memory',
                                  trailing: _AppPrefChoice(
                                    read: () => AppPrefs.undoLevels,
                                    write: AppPrefs.setUndoLevels,
                                    values: const [5, 10, 20, 50, 100],
                                  ),
                                ),
                                _Row(
                                  label: 'Recent files on Home',
                                  trailing: _AppPrefChoice(
                                    read: () => AppPrefs.recentCount,
                                    write: AppPrefs.setRecentCount,
                                    values: const [6, 12, 24, 50],
                                  ),
                                ),
                                const _Row(
                                  label: 'Comment author',
                                  hint: 'Name saved on your comments '
                                      '(empty = computer user name)',
                                  trailing: _AuthorField(),
                                ),
                                _Row(
                                  label: 'Start-up animation',
                                  hint: 'Skipped automatically when a file '
                                      'is opened from the desktop',
                                  trailing: _AppPrefSwitch(
                                    read: () => AppPrefs.showSplash,
                                    write: AppPrefs.setShowSplash,
                                  ),
                                ),
                              ],
                            ),
                            _Group(
                              title: 'Keyboard',
                              children: [
                                _Row(
                                  label: 'Keyboard shortcuts',
                                  hint: 'Every shortcut, Acrobat-style',
                                  trailing: OutlinedButton(
                                    onPressed: () =>
                                        showShortcutsDialog(context),
                                    child: const Text('View'),
                                  ),
                                ),
                                _Row(
                                  label: 'Command palette',
                                  hint: 'Ctrl/⌘ K from anywhere',
                                  trailing: OutlinedButton(
                                    onPressed: () =>
                                        showDocumentStudioCommandPalette(
                                          context,
                                        ),
                                    child: const Text('Open'),
                                  ),
                                ),
                              ],
                            ),
                            _Group(
                              title: 'Privacy',
                              children: [
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text('Work fully offline'),
                                  subtitle: Text(
                                    'Your files never leave this device. This blocks '
                                    'the app from using the network.',
                                    style: TextStyle(color: muted, fontSize: 12),
                                  ),
                                  value: settings.strictOffline,
                                  onChanged: settings.setStrictOffline,
                                ),
                              ],
                            ),
                            const DesktopDocumentToolsPanel(),
                            const LocalQpdfEnginePanel(),
                            const StorageSettingsPanel(),
                            _Group(
                              title: 'Updates',
                              children: [
                                _Row(
                                  label: 'Document Studio',
                                  hint: ref
                                      .watch(appVersionLabelProvider)
                                      .maybeWhen(
                                        data: (v) => 'Installed: $v',
                                        orElse: () => 'Installed: $kAppVersion',
                                      ),
                                  trailing: OutlinedButton.icon(
                                    onPressed: () =>
                                        checkForUpdatesInteractive(context),
                                    icon: const Icon(Icons.system_update_alt, size: 16),
                                    label: const Text('Check for updates'),
                                  ),
                                ),
                                _Row(
                                  label: 'Check automatically',
                                  hint: 'Looks for a new release at start-up '
                                      'and offers a one-click update. On '
                                      'Windows you can also run "winget '
                                      'upgrade DocumentStudio.DocumentStudio".',
                                  trailing: _AppPrefSwitch(
                                    read: () => AppPrefs.autoUpdateCheck,
                                    write: AppPrefs.setAutoUpdateCheck,
                                  ),
                                ),
                              ],
                            ),
                            const _AboutCard(),
                            ]),
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

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: DsColors.textSecondary(theme.brightness),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: dark ? DsColors.groupedCellDark : DsColors.groupedCellLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DsColors.border(theme.brightness)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.hint, required this.trailing});

  final String label;
  final String? hint;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        if (hint != null)
          Text(
            hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: DsColors.textSecondary(theme.brightness),
              fontSize: 12,
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, c) {
          // Narrow cards: control goes under the label instead of overflowing.
          if (c.maxWidth < 430) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: trailing),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 12),
              trailing,
            ],
          );
        },
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        borderRadius: BorderRadius.circular(8),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final version = ref.watch(appVersionLabelProvider).maybeWhen(
          data: (v) => v,
          orElse: () => kAppVersion,
        );
    Widget link(IconData icon, String label, String url) => TextButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          ),
          icon: Icon(icon, size: 16),
          label: Text(label),
        );
    return _Group(
      title: 'About',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$kAppName  ·  v$version',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                'Offline-first PDF workspace. Free to use and open to contributions.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DsColors.textSecondary(theme.brightness),
                ),
              ),
              const SizedBox(height: 8),
              const DsBuiltBy(fontSize: 13, center: false),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: [
                  link(Icons.code, 'GitHub', kRepoUrl),
                  link(Icons.volunteer_activism_outlined, 'Contribute', kContributeUrl),
                  link(Icons.bug_report_outlined, 'Report an issue', kIssuesUrl),
                  link(Icons.person_outline, kAuthorName, kAuthorGithubUrl),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}


/// Page frame wide enough for a multi-column settings grid.
class _WideFrame extends StatelessWidget {
  const _WideFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: child,
        ),
      );
}

/// Lays cards out in 1–3 columns (by width), filling the shortest column
/// first so heights stay balanced.
class _Masonry extends StatelessWidget {
  const _Masonry({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 760 ? 2 : 1);
        if (cols == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        }
        final buckets = List.generate(cols, (_) => <Widget>[]);
        // Round-robin keeps the order readable (row by row).
        for (var i = 0; i < children.length; i++) {
          buckets[i % cols].add(children[i]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cols; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: buckets[i],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}


/// Settings → Fonts: add / remove fonts used when editing text.
class _FontsCard extends ConsumerStatefulWidget {
  const _FontsCard();

  @override
  ConsumerState<_FontsCard> createState() => _FontsCardState();
}

class _FontsCardState extends ConsumerState<_FontsCard> {
  @override
  void initState() {
    super.initState();
    FontLibrary.instance.ensureLoaded();
  }

  Future<void> _add() async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: const ['ttf']);
    if (picked == null) return;
    final font = await FontLibrary.instance.install(picked.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          font == null
              ? 'That file is not a usable TrueType (.ttf) font.'
              : 'Added ${font.label}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: FontLibrary.instance,
      builder: (context, _) {
        final fonts = FontLibrary.instance.fonts;
        return _Group(
          title: 'Fonts',
          children: [
            _Row(
              label: 'Fonts for editing text',
              hint: 'Added fonts are embedded in the PDF so it looks the same everywhere.',
              trailing: Wrap(
                spacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add font'),
                  ),
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse('https://fonts.google.com'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Get fonts'),
                  ),
                ],
              ),
            ),
            if (fonts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No added fonts yet. Standard Sans, Serif and Mono are always available.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final f in fonts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.font_download_outlined, size: 20),
                  title: Text(f.label),
                  subtitle: Text(f.id, style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => FontLibrary.instance.remove(f),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// A switch bound to one [AppPrefs] value.
class _AppPrefSwitch extends StatefulWidget {
  const _AppPrefSwitch({required this.read, required this.write});

  final bool Function() read;
  final Future<void> Function(bool) write;

  @override
  State<_AppPrefSwitch> createState() => _AppPrefSwitchState();
}

class _AppPrefSwitchState extends State<_AppPrefSwitch> {
  @override
  Widget build(BuildContext context) => Switch.adaptive(
        value: widget.read(),
        onChanged: (v) async {
          await widget.write(v);
          if (mounted) setState(() {});
        },
      );
}

/// A number picker bound to one [AppPrefs] value.
class _AppPrefChoice extends StatefulWidget {
  const _AppPrefChoice({
    required this.read,
    required this.write,
    required this.values,
  });

  final int Function() read;
  final Future<void> Function(int) write;
  final List<int> values;

  @override
  State<_AppPrefChoice> createState() => _AppPrefChoiceState();
}

class _AppPrefChoiceState extends State<_AppPrefChoice> {
  @override
  Widget build(BuildContext context) {
    final cur = widget.read();
    final values = {...widget.values, cur}.toList()..sort();
    return DropdownButton<int>(
      value: cur,
      isDense: true,
      items: [
        for (final v in values) DropdownMenuItem(value: v, child: Text('$v')),
      ],
      onChanged: (v) async {
        if (v == null) return;
        await widget.write(v);
        if (mounted) setState(() {});
      },
    );
  }
}

class _AuthorField extends StatefulWidget {
  const _AuthorField();

  @override
  State<_AuthorField> createState() => _AuthorFieldState();
}

class _AuthorFieldState extends State<_AuthorField> {
  late final _ctrl = TextEditingController(text: AppPrefs.commentAuthor);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 200,
        child: TextField(
          controller: _ctrl,
          decoration: InputDecoration(
            isDense: true,
            hintText: AppPrefs.effectiveAuthor,
            border: const OutlineInputBorder(),
          ),
          onChanged: AppPrefs.setCommentAuthor,
        ),
      );
}
