import 'dart:async';

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/infrastructure/pdf/signing/pkcs11/pkcs11_modules.dart';
import 'package:document_studio/infrastructure/pdf/signing/signing_credential.dart';
import 'package:document_studio/infrastructure/pdf/signing/signing_credential_service.dart';
import 'package:flutter/material.dart';

/// Card for one discovered / imported signing credential.
class SigningCredentialCard extends StatelessWidget {
  const SigningCredentialCard({
    super.key,
    required this.credential,
    this.selected = false,
    this.compact = false,
    this.onTap,
    this.trailing,
  });

  final SigningCredential credential;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = credential;
    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 10,
            vertical: compact ? 6 : 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _iconFor(c.source),
                size: compact ? 18 : 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: DsSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.displayName,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      c.isSelfSigned
                          ? 'Self-signed'
                          : (c.issuerCommonName.isEmpty
                                ? c.source.groupTitle
                                : 'Issuer: ${c.issuerCommonName}'),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (c.isExpired)
                            const _Badge('Expired', DsColors.error)
                          else if (c.isNotYetValid)
                            const _Badge('Not yet valid', Color(0xFFB7791F))
                          else if (c.isExpiringSoon)
                            const _Badge(
                              'Expires in 30 days',
                              Color(0xFFB7791F),
                            ),
                          if (!c.canSignDocuments)
                            const _Badge('Not for signing', Color(0xFFB7791F)),
                          if (c.keyDescription.isNotEmpty)
                            _Badge(
                              c.keyDescription,
                              DsColors.textSecondaryLight,
                            ),
                          if (c.hardwareBacked)
                            const _Badge('Hardware key', DsColors.primary),
                          if (c.protectedAuthPath)
                            const _Badge('PIN pad', DsColors.primary),
                          for (final u in c.keyUsage.take(2))
                            _Badge(u, DsColors.textSecondaryLight),
                        ],
                      ),
                      if (c.statusNote != null) ...[
                        const SizedBox(height: 4),
                        Text(c.statusNote!, style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(SigningCredentialSource s) => switch (s) {
    SigningCredentialSource.smartCard => Icons.credit_card,
    SigningCredentialSource.keychain => Icons.key,
    SigningCredentialSource.windowsStore => Icons.desktop_windows_outlined,
    SigningCredentialSource.nss => Icons.language,
    SigningCredentialSource.imported => Icons.badge_outlined,
    SigningCredentialSource.selfSigned => Icons.verified_user_outlined,
  };
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// Grouped digital ID list with refresh and drivers dialog.
class DigitalIdList extends StatefulWidget {
  const DigitalIdList({
    super.key,
    required this.service,
    this.selectedId,
    this.onSelected,
    this.compact = false,
    this.enabled = true,
    this.pickDriverPath,
    this.itemTrailing,
    this.pollHotPlug = true,
  });

  final SigningCredentialService service;
  final String? selectedId;
  final ValueChanged<SigningCredential>? onSelected;
  final bool compact;
  final bool enabled;
  final Future<String?> Function()? pickDriverPath;
  final Widget Function(SigningCredential c)? itemTrailing;
  final bool pollHotPlug;

  @override
  State<DigitalIdList> createState() => DigitalIdListState();
}

class DigitalIdListState extends State<DigitalIdList> {
  List<SigningCredential> _items = const [];
  bool _loading = true;
  String? _error;
  Timer? _poll;
  bool _refreshing = false;
  final Set<SigningCredentialSource> _openGroups = {
    if (SigningCredentialService.supportsSystemStores)
      SigningCredentialSource.smartCard,
  };

  List<SigningCredential> get items => _items;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
    if (widget.pollHotPlug) {
      _poll = Timer.periodic(const Duration(seconds: 20), (_) {
        unawaited(refresh(silent: true));
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await widget.service.listAll();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        for (final c in list) {
          final n = list.where((o) => o.source == c.source).length;
          if (n <= 6) _openGroups.add(c.source);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _openDrivers() async {
    await showPkcs11DriversDialog(
      context,
      pickDriverPath: widget.pickDriverPath,
    );
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading && _items.isEmpty) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (_error != null && _items.isEmpty) {
      return Text(_error!, style: theme.textTheme.bodySmall);
    }

    final grouped = <SigningCredentialSource, List<SigningCredential>>{};
    for (final c in _items) {
      grouped.putIfAbsent(c.source, () => []).add(c);
    }
    final showUsbSection = SigningCredentialService.supportsSystemStores;
    final sources = SigningCredentialSource.values.where((s) {
      if (s == SigningCredentialSource.smartCard && showUsbSection) {
        return true;
      }
      return grouped[s]?.isNotEmpty == true;
    }).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final nonUsbEmpty = _items
        .where((c) => c.source != SigningCredentialSource.smartCard)
        .isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Digital IDs', style: theme.textTheme.labelLarge),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: widget.enabled ? () => refresh() : null,
              icon: const Icon(Icons.refresh),
            ),
            if (showUsbSection)
              TextButton(
                onPressed: widget.enabled ? _openDrivers : null,
                child: const Text('Drivers…'),
              ),
          ],
        ),
        for (final source in sources) ...[
          _GroupHeader(
            title: '${source.groupTitle} · ${grouped[source]?.length ?? 0}',
            open: _openGroups.contains(source),
            onToggle: () => setState(() {
              if (!_openGroups.add(source)) _openGroups.remove(source);
            }),
          ),
          if (_openGroups.contains(source))
            if (source == SigningCredentialSource.smartCard &&
                (grouped[source]?.isEmpty ?? true))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No token connected. Plug in a token or smart card.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final c in grouped[source]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SigningCredentialCard(
                    credential: c,
                    selected: widget.selectedId == c.id,
                    compact: widget.compact,
                    onTap: widget.enabled && widget.onSelected != null
                        ? () => widget.onSelected!(c)
                        : null,
                    trailing: widget.itemTrailing?.call(c),
                  ),
                ),
        ],
        if (nonUsbEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              showUsbSection
                  ? 'No other digital IDs yet. Import a .p12 / .pfx or create '
                        'a self-signed ID (install a PKCS#11 driver under '
                        'Drivers… if your token is not detected).'
                  : 'No digital IDs yet. Import a .p12 / .pfx file or create a '
                        'self-signed ID. USB tokens and smart cards are supported '
                        'on the desktop app only.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.open,
    required this.onToggle,
  });

  final String title;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(top: DsSpacing.sm, bottom: 4),
        child: Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.labelMedium)),
            Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18,
              color: DsColors.textSecondary(theme.brightness),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showPkcs11DriversDialog(
  BuildContext context, {
  Future<String?> Function()? pickDriverPath,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _DriversDialog(pickDriverPath: pickDriverPath),
  );
}

class _DriversDialog extends StatefulWidget {
  const _DriversDialog({this.pickDriverPath});
  final Future<String?> Function()? pickDriverPath;

  @override
  State<_DriversDialog> createState() => _DriversDialogState();
}

class _DriversDialogState extends State<_DriversDialog> {
  List<String> _discovered = const [];
  List<String> _custom = const [];
  final _manual = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final discovered = await Pkcs11Modules.discoverModulePaths();
    final custom = await Pkcs11Modules.loadCustomPaths();
    if (!mounted) return;
    setState(() {
      _discovered = discovered;
      _custom = custom;
      _loading = false;
    });
  }

  Future<void> _add(String path) async {
    if (path.trim().isEmpty) return;
    await Pkcs11Modules.addCustomPath(path.trim());
    _manual.clear();
    await _load();
  }

  Future<void> _remove(String path) async {
    await Pkcs11Modules.removeCustomPath(path);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Smart card & token drivers'),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Detected modules',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    if (_discovered.isEmpty)
                      const Text('No PKCS#11 modules found on this system.')
                    else
                      for (final m in _discovered)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(m, style: const TextStyle(fontSize: 12)),
                          subtitle: Text(
                            _custom.contains(m) ? 'User-added' : 'System',
                          ),
                        ),
                    const SizedBox(height: DsSpacing.md),
                    Text(
                      'Add module path',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manual,
                            decoration: const InputDecoration(
                              hintText: '/usr/lib/…/opensc-pkcs11.so',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        if (widget.pickDriverPath != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Browse',
                            onPressed: () async {
                              final p = await widget.pickDriverPath!();
                              if (p != null) await _add(p);
                            },
                            icon: const Icon(Icons.folder_open),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    DsSecondaryButton(
                      label: 'Add path',
                      onPressed: () => _add(_manual.text),
                    ),
                    if (_custom.isNotEmpty) ...[
                      const SizedBox(height: DsSpacing.md),
                      Text(
                        'User-added',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      for (final m in _custom)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(m, style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _remove(m),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

Future<String?> showPinDialog(
  BuildContext context, {
  String title = 'Enter PIN',
  String fieldLabel = 'PIN',
  bool obscure = true,
}) {
  final controller = TextEditingController();
  var remember = false;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: fieldLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remember for this session'),
              value: remember,
              onChanged: (v) => setState(() => remember = v ?? false),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          DsPrimaryButton(
            label: 'Continue',
            onPressed: () {
              final pin = controller.text;
              Navigator.of(ctx).pop(remember ? 'remember:$pin' : pin);
            },
          ),
        ],
      ),
    ),
  );
}
