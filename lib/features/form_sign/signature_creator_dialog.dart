import 'dart:typed_data';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/form_sign/sign_sheet.dart';
import 'package:document_studio/features/form_sign/signature_appearance_raster.dart';
import 'package:document_studio/features/form_sign/signature_pad.dart';
import 'package:document_studio/features/form_sign/stamp_renderer.dart';
import 'package:document_studio/infrastructure/pdf/saved_visual_signature_store.dart';
import 'package:flutter/material.dart';

enum _CreateMode { draw, type, image }

/// Initials derived from a full name ("Ada M. Lovelace" → "AML").
String initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'[\s\-_.]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  return parts.take(3).map((p) => p.characters.first.toUpperCase()).join();
}

/// Opens the signature / initials creator. Saves to [store] and returns the
/// new entry (null when cancelled).
Future<SavedSignature?> showSignatureCreator(
  BuildContext context, {
  required SavedVisualSignatureStore store,
  required FileStoragePort storage,
  SavedSignatureKind kind = SavedSignatureKind.signature,
  String defaultName = '',
}) {
  return showSignSheet<SavedSignature>(
    context,
    maxWidth: 620,
    builder: (ctx) => _SignatureCreator(
      store: store,
      storage: storage,
      initialKind: kind,
      defaultName: defaultName,
    ),
  );
}

class _SignatureCreator extends StatefulWidget {
  const _SignatureCreator({
    required this.store,
    required this.storage,
    required this.initialKind,
    required this.defaultName,
  });

  final SavedVisualSignatureStore store;
  final FileStoragePort storage;
  final SavedSignatureKind initialKind;
  final String defaultName;

  @override
  State<_SignatureCreator> createState() => _SignatureCreatorState();
}

class _SignatureCreatorState extends State<_SignatureCreator> {
  late SavedSignatureKind _kind = widget.initialKind;
  _CreateMode _mode = _CreateMode.draw;
  final _pad = SignaturePadController(color: const Color(0xFF1A1A1A));
  late final TextEditingController _text = TextEditingController(
    text: _defaultText(widget.initialKind),
  );
  SignatureTypeface _typeface = kSignatureTypefaces.first;
  Color _typeColor = kSignatureInkColors.first.color;
  Uint8List? _imageSource;
  PreparedSignatureImage? _image;
  bool _removeBackground = true;
  bool _busy = false;
  String? _error;

  bool get _initials => _kind == SavedSignatureKind.initials;

  String _defaultText(SavedSignatureKind k) => k == SavedSignatureKind.initials
      ? initialsFor(widget.defaultName)
      : widget.defaultName;

  @override
  void initState() {
    super.initState();
    _pad.addListener(_changed);
    _text.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pad.dispose();
    _text.dispose();
    super.dispose();
  }

  void _setKind(SavedSignatureKind k) {
    if (k == _kind) return;
    final wasDefault = _text.text == _defaultText(_kind);
    setState(() => _kind = k);
    if (wasDefault) _text.text = _defaultText(k);
    _pad.clear();
  }

  bool get _canSave => switch (_mode) {
        _CreateMode.draw => !_pad.isEmpty,
        _CreateMode.type => _text.text.trim().isNotEmpty,
        _CreateMode.image => _image != null,
      };

  Future<void> _pickImage() async {
    final ref = await widget.storage.pickOpenFile(
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
    );
    if (ref == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _imageSource = await widget.storage.readBytes(ref);
      await _prepareImage();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Couldn’t save that signature. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareImage() async {
    final src = _imageSource;
    if (src == null) return;
    final prepared = await prepareSignatureImage(
      src,
      removeWhiteBackground: _removeBackground,
    );
    if (mounted) setState(() => _image = prepared);
  }

  Future<void> _save() async {
    if (!_canSave || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final png = switch (_mode) {
        _CreateMode.draw => await rasterizeDrawnSignature(ink: _pad.toInk()),
        _CreateMode.type => await rasterizeTypedSignature(
            text: _text.text,
            color: _typeColor,
            typeface: _typeface,
          ),
        _CreateMode.image => _image!.png,
      };
      final saved = await widget.store.add(png, kind: _kind);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ArgumentError && '${e.message}'.trim().isNotEmpty
              ? '${e.message}'
              : 'Couldn’t save that signature. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SignSheetScaffold(
      title: _initials ? 'Create initials' : 'Create signature',
      subtitle: 'Saved on this device and reusable in any document.',
      icon: Icons.draw_rounded,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SignSegmented<SavedSignatureKind>(
            value: _kind,
            onChanged: _setKind,
            segments: const [
              (SavedSignatureKind.signature, 'Signature', Icons.gesture_rounded),
              (SavedSignatureKind.initials, 'Initials', Icons.text_fields_rounded),
            ],
          ),
          const SizedBox(height: DsSpacing.sm),
          SignSegmented<_CreateMode>(
            value: _mode,
            onChanged: (m) => setState(() {
              _mode = m;
              _error = null;
            }),
            segments: const [
              (_CreateMode.draw, 'Draw', Icons.edit_rounded),
              (_CreateMode.type, 'Type', Icons.keyboard_rounded),
              (_CreateMode.image, 'Image', Icons.image_outlined),
            ],
          ),
          const SizedBox(height: DsSpacing.md),
          AnimatedSwitcher(
            duration: DsMotion.switchDuration,
            switchInCurve: DsMotion.switchCurve,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SizeTransition(
                sizeFactor: a,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_mode),
              child: switch (_mode) {
                _CreateMode.draw => _buildDraw(theme),
                _CreateMode.type => _buildType(theme),
                _CreateMode.image => _buildImage(theme),
              },
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: DsSpacing.sm),
            Text(
              _error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: DsColors.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _canSave && !_busy ? _save : null,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_initials ? 'Save initials' : 'Save signature'),
        ),
      ],
    );
  }

  Widget _buildDraw(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SignaturePad(
          controller: _pad,
          height: _initials ? 150 : 190,
          hintText: _initials ? 'Draw your initials' : 'Sign here',
        ),
        const SizedBox(height: DsSpacing.xs),
        Text(
          'Use a mouse, trackpad, pen or finger. Strokes are smoothed and '
          'saved at high resolution.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: DsColors.textSecondary(theme.brightness),
          ),
        ),
      ],
    );
  }

  Widget _buildType(ThemeData theme) {
    final text = _text.text.trim().isEmpty
        ? (_initials ? 'AB' : 'Your Name')
        : _text.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: _initials ? 6 : 60,
          decoration: InputDecoration(
            labelText: _initials ? 'Initials' : 'Full name',
            border: const OutlineInputBorder(),
            isDense: true,
            counterText: '',
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: DsSpacing.sm),
        Row(
          children: [
            for (final c in kSignatureInkColors)
              SignatureColorDot(
                color: c.color,
                label: c.label,
                selected: _typeColor == c.color,
                onTap: () => setState(() => _typeColor = c.color),
              ),
          ],
        ),
        const SizedBox(height: DsSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth > 420 ? 2 : 1;
            final w = (constraints.maxWidth - (cols - 1) * DsSpacing.sm) / cols;
            return Wrap(
              spacing: DsSpacing.sm,
              runSpacing: DsSpacing.sm,
              children: [
                for (final t in kSignatureTypefaces)
                  SizedBox(
                    width: w,
                    child: _FontTile(
                      typeface: t,
                      text: text,
                      color: _typeColor,
                      selected: t.id == _typeface.id,
                      onTap: () => setState(() => _typeface = t),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildImage(ThemeData theme) {
    final img = _image;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _busy ? null : _pickImage,
          borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
              border: Border.all(color: DsColors.border(theme.brightness)),
            ),
            clipBehavior: Clip.antiAlias,
            child: img == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 34,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: DsSpacing.sm),
                        Text(
                          'Choose a photo or scan of your signature',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          'PNG or JPG · dark ink on light paper works best',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: DsColors.textSecondary(theme.brightness),
                          ),
                        ),
                      ],
                    ),
                  )
                : CustomPaint(
                    painter: const CheckerboardPainter(cell: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(DsSpacing.md),
                      child: Center(
                        child: Image.memory(img.png, fit: BoxFit.contain),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: DsSpacing.sm),
        Row(
          children: [
            Expanded(
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _removeBackground,
                title: const Text('Remove background'),
                subtitle: Text(
                  img == null || img.hasOpaqueLightBackground
                      ? 'Makes white paper transparent'
                      : 'Image already has transparency',
                ),
                onChanged: _busy
                    ? null
                    : (v) {
                        setState(() => _removeBackground = v);
                        _prepareImage();
                      },
              ),
            ),
            if (img != null)
              TextButton.icon(
                onPressed: _busy ? null : _pickImage,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Replace'),
              ),
          ],
        ),
      ],
    );
  }
}

class _FontTile extends StatelessWidget {
  const _FontTile({
    required this.typeface,
    required this.text,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final SignatureTypeface typeface;
  final String text;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return AnimatedContainer(
      duration: DsMotion.hoverDuration,
      height: 66,
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.06)
            : DsColors.groupedCell(theme.brightness),
        borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
        border: Border.all(
          color: selected ? accent : DsColors.border(theme.brightness),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text,
                      maxLines: 1,
                      style: typeface.textStyle(fontSize: 34, color: color),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 4,
                child: Text(
                  typeface.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    color: DsColors.textSecondary(theme.brightness),
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Icon(Icons.check_circle_rounded, size: 16, color: accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
