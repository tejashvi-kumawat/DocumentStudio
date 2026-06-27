import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/pdf_stamp/stamp_library_models.dart';
import 'package:document_studio/features/form_sign/sign_placement_bridge.dart';
import 'package:document_studio/features/form_sign/sign_sheet.dart';
import 'package:document_studio/features/form_sign/signature_appearance_raster.dart';
import 'package:document_studio/features/form_sign/stamp_renderer.dart';
import 'package:document_studio/infrastructure/pdf/saved_stamp_store.dart';
import 'package:flutter/material.dart';

const _dateStampId = 'date_stamp';

/// Stamp design for the Date stamp tool.
StampDesign dateStampDesign(DateStampPrefs prefs, DateTime now) => StampDesign(
      id: _dateStampId,
      title: formatStampDate(now, prefs.format),
      colorArgb: prefs.color,
      category: StampCategory.date,
      border: StampBorder.none,
      shape: StampShape.rectangle,
      filled: false,
    );

/// Built-in, dynamic, date, custom and image stamps; drag or click to place.
class StampLibraryView extends StatefulWidget {
  const StampLibraryView({
    super.key,
    required this.controller,
    required this.storage,
    required this.userName,
    required this.onUserNameChanged,
    required this.onMessage,
  });

  final SignPlacementController controller;
  final FileStoragePort storage;
  final String userName;
  final ValueChanged<String> onUserNameChanged;
  final ValueChanged<String> onMessage;

  @override
  State<StampLibraryView> createState() => _StampLibraryViewState();
}

class _StampLibraryViewState extends State<StampLibraryView> {
  final _store = SavedStampStore();
  late final TextEditingController _name =
      TextEditingController(text: widget.userName);
  List<StampDesign> _custom = const [];
  List<SavedImageStamp> _images = const [];
  DateStampPrefs _datePrefs = DateStampPrefs(
    format: kStampDateFormats.first,
    color: StampColors.blue,
  );
  final Map<String, RenderedStamp> _rendered = {};
  final Map<String, Size> _imageSizes = {};
  Timer? _minuteTick;
  Timer? _nameDebounce;
  DateTime _now = DateTime.now();
  int _renderGen = 0;

  StampContext get _ctx =>
      StampContext(userName: _name.text.trim(), now: _now);

  @override
  void initState() {
    super.initState();
    _load();
    _minuteTick = Timer.periodic(const Duration(seconds: 20), (_) {
      final n = DateTime.now();
      if (n.minute != _now.minute || n.day != _now.day) {
        _now = n;
        _renderAll(onlyDynamic: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant StampLibraryView old) {
    super.didUpdateWidget(old);
    if (old.userName != widget.userName && widget.userName != _name.text) {
      _name.text = widget.userName;
      _renderAll(onlyDynamic: true);
    }
  }

  @override
  void dispose() {
    _minuteTick?.cancel();
    _nameDebounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final custom = await _store.loadDesigns();
    final images = await _store.loadImageStamps();
    final prefs = await _store.loadDateStampPrefs();
    if (!mounted) return;
    setState(() {
      _custom = custom;
      _images = images;
      _datePrefs = prefs;
    });
    for (final i in images) {
      _imageSizes[i.id] = await _decodeSize(i.bytes);
    }
    await _renderAll();
  }

  Future<Size> _decodeSize(Uint8List bytes) async {
    if (bytes.length > 24 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      int be(int o) =>
          (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];
      return Size(be(16).toDouble(), be(20).toDouble());
    }
    return const Size(300, 100);
  }

  List<StampDesign> get _allDesigns => [
        ...kBuiltInStamps,
        dateStampDesign(_datePrefs, _now),
        ..._custom,
      ];

  Future<void> _renderAll({bool onlyDynamic = false}) async {
    final gen = ++_renderGen;
    final ctx = _ctx;
    for (final d in _allDesigns) {
      if (onlyDynamic && !d.isDynamic && d.category != StampCategory.date) {
        continue;
      }
      final r = await rasterizeStamp(d, ctx);
      if (!mounted || gen != _renderGen) return;
      setState(() => _rendered[d.id] = r);
    }
  }

  Future<void> _renderOne(StampDesign d) async {
    final r = await rasterizeStamp(d, _ctx);
    if (mounted) setState(() => _rendered[d.id] = r);
  }

  void _onNameChanged(String v) {
    setState(() {});
    _nameDebounce?.cancel();
    _nameDebounce = Timer(const Duration(milliseconds: 350), () {
      widget.onUserNameChanged(v.trim());
      _renderAll(onlyDynamic: true);
    });
  }

  SignPlaceable? _placeableFor(StampDesign d) {
    final r = _rendered[d.id];
    if (r == null) return null;
    Future<SignPlaceable> refresh() async {
      final ctx = StampContext(userName: _name.text.trim(), now: DateTime.now());
      final design = d.category == StampCategory.date
          ? dateStampDesign(_datePrefs, ctx.now)
          : d;
      final fresh = await rasterizeStamp(design, ctx);
      return SignPlaceable(
        id: 'stamp:${d.id}',
        kind: SignPlaceableKind.stamp,
        png: fresh.png,
        sizePt: fresh.sizePt,
        label: d.category == StampCategory.date ? 'Date' : _titleCase(d.title),
      );
    }

    final dynamic_ = d.isDynamic || d.category == StampCategory.date;
    return SignPlaceable(
      id: 'stamp:${d.id}',
      kind: SignPlaceableKind.stamp,
      png: r.png,
      sizePt: r.sizePt,
      label: d.category == StampCategory.date ? 'Date' : _titleCase(d.title),
      refresh: dynamic_ ? refresh : null,
    );
  }

  SignPlaceable _placeableForImage(SavedImageStamp s) {
    final px = _imageSizes[s.id] ?? const Size(300, 100);
    final aspect = px.width / math.max(1, px.height);
    var w = 150.0;
    var h = w / aspect;
    if (h > 110) {
      h = 110;
      w = h * aspect;
    }
    return SignPlaceable(
      id: 'imgstamp:${s.id}',
      kind: SignPlaceableKind.image,
      png: s.bytes,
      sizePt: Size(w, h),
      label: s.name,
    );
  }

  void _toggle(SignPlaceable? p) {
    if (p == null) return;
    final c = widget.controller;
    c.arm(c.armed?.id == p.id ? null : p);
  }

  Future<void> _editDesign([StampDesign? existing]) async {
    final design = await showStampDesigner(
      context,
      initial: existing,
      stampContext: _ctx,
    );
    if (design == null) return;
    await _store.saveDesign(design);
    final custom = await _store.loadDesigns();
    if (!mounted) return;
    setState(() => _custom = custom);
    // saveDesign appends new designs and keeps the id of edited ones.
    final saved = custom.firstWhere(
      (d) => design.id.isNotEmpty && d.id == design.id,
      orElse: () => custom.last,
    );
    await _renderOne(saved);
    final p = _placeableFor(saved);
    if (p != null) widget.controller.arm(p);
    widget.onMessage('Stamp saved — drag on the page to place it.');
  }

  Future<void> _deleteDesign(StampDesign d) async {
    final ok = await showDsAdaptiveConfirm(
      context,
      title: 'Delete “${d.title}”?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await _store.removeDesign(d.id);
    final custom = await _store.loadDesigns();
    if (mounted) setState(() => _custom = custom);
  }

  Future<void> _importImage() async {
    final ref = await widget.storage.pickOpenFile(
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
    );
    if (ref == null) return;
    try {
      final raw = await widget.storage.readBytes(ref);
      final prepared = await prepareSignatureImage(raw);
      final name = ref.displayName.replaceAll(RegExp(r'\.[^.]+$'), '');
      await _store.addImageStamp(prepared.png, name.isEmpty ? 'Image' : name);
      final images = await _store.loadImageStamps();
      if (!mounted) return;
      for (final i in images) {
        _imageSizes[i.id] ??= await _decodeSize(i.bytes);
      }
      setState(() => _images = images);
      if (images.isNotEmpty) widget.controller.arm(_placeableForImage(images.first));
      widget.onMessage(
        prepared.hasOpaqueLightBackground
            ? 'Image stamp added (white background removed).'
            : 'Image stamp added.',
      );
    } catch (e) {
      widget.onMessage('Could not import image: $e');
    }
  }

  Future<void> _deleteImage(SavedImageStamp s) async {
    await _store.removeImageStamp(s.id);
    final images = await _store.loadImageStamps();
    if (mounted) setState(() => _images = images);
  }

  Future<void> _setDatePrefs({String? format, int? color}) async {
    await _store.saveDateStampPrefs(format: format, color: color);
    final prefs = await _store.loadDateStampPrefs();
    if (!mounted) return;
    setState(() => _datePrefs = prefs);
    await _renderOne(dateStampDesign(prefs, _now));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byCat = <StampCategory, List<StampDesign>>{};
    for (final d in kBuiltInStamps) {
      byCat.putIfAbsent(d.category, () => []).add(d);
    }
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: DsSpacing.sm),
          TextField(
            controller: _name,
            onChanged: _onNameChanged,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Name on dynamic stamps',
              prefixIcon: const Icon(Icons.badge_outlined, size: 18),
              border: const OutlineInputBorder(),
              helperText: 'Dynamic stamps add your name and the date / time '
                  'when you place them.',
              helperMaxLines: 2,
              helperStyle: theme.textTheme.bodySmall?.copyWith(
                color: DsColors.textSecondary(theme.brightness),
              ),
            ),
          ),
          const SignSectionLabel('Dynamic'),
          _grid(byCat[StampCategory.dynamic] ?? const []),
          const SignSectionLabel('Standard business'),
          _grid(byCat[StampCategory.standard] ?? const []),
          const SignSectionLabel('Sign here'),
          _grid(byCat[StampCategory.signHere] ?? const []),
          const SignSectionLabel('Date stamp'),
          _dateCard(theme),
          SignSectionLabel(
            'Custom stamps',
            trailing: TextButton.icon(
              onPressed: () => _editDesign(),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Create'),
            ),
          ),
          if (_custom.isEmpty)
            _EmptyHint(
              icon: Icons.approval_outlined,
              text: 'Design your own stamp with text, colors, shape and date.',
              action: 'Create stamp',
              onTap: () => _editDesign(),
            )
          else
            _grid(_custom, editable: true),
          SignSectionLabel(
            'Image stamps',
            trailing: TextButton.icon(
              onPressed: _importImage,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: const Text('Import'),
            ),
          ),
          if (_images.isEmpty)
            _EmptyHint(
              icon: Icons.image_outlined,
              text: 'Use a company seal or logo. White backgrounds are '
                  'removed automatically.',
              action: 'Import image',
              onTap: _importImage,
            )
          else
            _imageGrid(),
          const SizedBox(height: DsSpacing.lg),
        ],
      ),
    );
  }

  Widget _grid(List<StampDesign> designs, {bool editable = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = math.max(2, (constraints.maxWidth / 150).floor());
        final w = (constraints.maxWidth - (cols - 1) * DsSpacing.sm) / cols;
        return Wrap(
          spacing: DsSpacing.sm,
          runSpacing: DsSpacing.sm,
          children: [
            for (final d in designs)
              SizedBox(
                width: w,
                height: 64,
                child: _StampCard(
                  preview: StampPreview(design: d, stampContext: _ctx),
                  placeable: _placeableFor(d),
                  controller: widget.controller,
                  tooltip: d.isDynamic
                      ? '${_titleCase(d.title)} · adds name, date & time'
                      : _titleCase(d.title),
                  onTap: () => _toggle(_placeableFor(d)),
                  onEdit: editable ? () => _editDesign(d) : null,
                  onDelete: editable ? () => _deleteDesign(d) : null,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _imageGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = math.max(2, (constraints.maxWidth / 150).floor());
        final w = (constraints.maxWidth - (cols - 1) * DsSpacing.sm) / cols;
        return Wrap(
          spacing: DsSpacing.sm,
          runSpacing: DsSpacing.sm,
          children: [
            for (final s in _images)
              SizedBox(
                width: w,
                height: 72,
                child: _StampCard(
                  preview: CustomPaint(
                    painter: const CheckerboardPainter(cell: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.memory(s.bytes, fit: BoxFit.contain),
                    ),
                  ),
                  placeable: _placeableForImage(s),
                  controller: widget.controller,
                  tooltip: s.name,
                  onTap: () => _toggle(_placeableForImage(s)),
                  onDelete: () => _deleteImage(s),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _dateCard(ThemeData theme) {
    final design = dateStampDesign(_datePrefs, _now);
    return Container(
      padding: const EdgeInsets.all(DsSpacing.sm),
      decoration: DsSpacing.groupedInsetDecoration(
        isDark: theme.brightness == Brightness.dark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: _StampCard(
              preview: StampPreview(design: design, stampContext: _ctx),
              placeable: _placeableFor(design),
              controller: widget.controller,
              tooltip: 'Today’s date',
              onTap: () => _toggle(_placeableFor(design)),
            ),
          ),
          const SizedBox(height: DsSpacing.sm),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: kStampDateFormats.contains(_datePrefs.format)
                      ? _datePrefs.format
                      : kStampDateFormats.first,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Format',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final f in kStampDateFormats)
                      DropdownMenuItem(
                        value: f,
                        child: Text(
                          formatStampDate(_now, f),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (f) => _setDatePrefs(format: f),
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpacing.sm),
          _ColorRow(
            value: _datePrefs.color,
            onChanged: (c) => _setDatePrefs(color: c),
          ),
        ],
      ),
    );
  }
}

String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.text,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = signIsPhoneWidth(context);
    final message = Text(
      text,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: DsColors.textSecondary(theme.brightness),
      ),
    );
    final actionButton = TextButton(onPressed: onTap, child: Text(action));
    return Container(
      padding: EdgeInsets.all(
        phone ? DsSpacing.pagePaddingCompact : DsSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: DsSpacing.sm),
                    Expanded(child: message),
                  ],
                ),
                Align(alignment: Alignment.centerLeft, child: actionButton),
              ],
            )
          : Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: DsSpacing.sm),
                Expanded(child: message),
                actionButton,
              ],
            ),
    );
  }
}

class _StampCard extends StatefulWidget {
  const _StampCard({
    required this.preview,
    required this.placeable,
    required this.controller,
    required this.tooltip,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final Widget preview;
  final SignPlaceable? placeable;
  final SignPlacementController controller;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  State<_StampCard> createState() => _StampCardState();
}

class _StampCardState extends State<_StampCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final p = widget.placeable;
    final armed = p != null && widget.controller.armed?.id == p.id;
    final hasMenu = widget.onEdit != null || widget.onDelete != null;
    final card = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: p == null ? SystemMouseCursors.basic : SystemMouseCursors.grab,
      child: AnimatedContainer(
        duration: DsMotion.hoverDuration,
        transform: Matrix4.translationValues(0, _hover && !armed ? -1.5 : 0, 0),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFFF3F4F6)
              : DsColors.groupedCell(theme.brightness),
          borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
          border: Border.all(
            color: armed
                ? accent
                : _hover
                    ? accent.withValues(alpha: 0.45)
                    : DsColors.border(theme.brightness),
            width: armed ? 1.8 : 1,
          ),
          boxShadow: DsSpacing.cardShadowLight(opacity: _hover || armed ? 0.10 : 0.03),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
            onTap: p == null ? null : widget.onTap,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Center(child: widget.preview),
                  ),
                ),
                if (hasMenu)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: AnimatedOpacity(
                      opacity: _hover || signIsPhoneWidth(context) ? 1 : 0,
                      duration: DsMotion.hoverDuration,
                      child: PopupMenuButton<String>(
                        tooltip: 'More',
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: DsColors.textSecondaryLight,
                        ),
                        onSelected: (v) => v == 'edit'
                            ? widget.onEdit?.call()
                            : widget.onDelete?.call(),
                        itemBuilder: (_) => [
                          if (widget.onEdit != null)
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          if (widget.onDelete != null)
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final tip = Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: card,
    );
    if (p == null) return tip;
    return SignLibraryDraggable(
      item: p,
      controller: widget.controller,
      child: tip,
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in StampColors.palette)
          Semantics(
            button: true,
            selected: c == value,
            child: InkResponse(
              onTap: () => onChanged(c),
              radius: 16,
              child: AnimatedContainer(
                duration: DsMotion.hoverDuration,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c == value ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: c == value
                      ? [BoxShadow(color: Color(c).withValues(alpha: 0.6), blurRadius: 0, spreadRadius: 2)]
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Custom stamp designer with live preview. Returns the edited design.
Future<StampDesign?> showStampDesigner(
  BuildContext context, {
  StampDesign? initial,
  required StampContext stampContext,
}) {
  return showSignSheet<StampDesign>(
    context,
    maxWidth: 560,
    builder: (_) => _StampDesigner(initial: initial, stampContext: stampContext),
  );
}

class _StampDesigner extends StatefulWidget {
  const _StampDesigner({this.initial, required this.stampContext});

  final StampDesign? initial;
  final StampContext stampContext;

  @override
  State<_StampDesigner> createState() => _StampDesignerState();
}

class _StampDesignerState extends State<_StampDesigner> {
  late StampDesign _d = widget.initial ??
      const StampDesign(
        id: '',
        title: 'APPROVED',
        colorArgb: StampColors.blue,
        category: StampCategory.custom,
      );
  late final _title = TextEditingController(text: _d.title);
  late final _sub = TextEditingController(text: _d.subtitle ?? '');

  @override
  void dispose() {
    _title.dispose();
    _sub.dispose();
    super.dispose();
  }

  void _set(StampDesign d) => setState(() => _d = d);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctx = StampContext(
      userName: widget.stampContext.userName,
      now: DateTime.now(),
    );
    return SignSheetScaffold(
      title: widget.initial == null ? 'Create stamp' : 'Edit stamp',
      subtitle: 'What you see is exactly what is added to the page.',
      icon: Icons.approval_outlined,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 120,
            padding: const EdgeInsets.all(DsSpacing.lg),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
              border: Border.all(color: DsColors.border(theme.brightness)),
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: DsMotion.hoverDuration,
                child: StampPreview(
                  key: ValueKey(Object.hash(
                    _d.title, _d.subtitle, _d.colorArgb, _d.shape, _d.border,
                    _d.filled, _d.icon, _d.includeDate, _d.includeTime,
                    _d.includeUser, _d.dateFormat,
                  )),
                  design: _d,
                  stampContext: ctx,
                ),
              ),
            ),
          ),
          const SizedBox(height: DsSpacing.md),
          TextField(
            controller: _title,
            autofocus: widget.initial == null,
            textCapitalization: TextCapitalization.characters,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Stamp text',
              isDense: true,
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onChanged: (v) => _set(_d.copyWith(title: v.toUpperCase())),
          ),
          const SizedBox(height: DsSpacing.sm),
          TextField(
            controller: _sub,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Second line (optional)',
              isDense: true,
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onChanged: (v) => _set(v.trim().isEmpty
                ? _d.copyWith(clearSubtitle: true)
                : _d.copyWith(subtitle: v)),
          ),
          const SignSectionLabel('Color'),
          _ColorRow(
            value: _d.colorArgb,
            onChanged: (c) => _set(_d.copyWith(colorArgb: c)),
          ),
          const SignSectionLabel('Shape'),
          SignSegmented<StampShape>(
            value: _d.shape,
            onChanged: (s) => _set(_d.copyWith(shape: s)),
            segments: [for (final s in StampShape.values) (s, s.label, null)],
          ),
          const SignSectionLabel('Border'),
          SignSegmented<StampBorder>(
            value: _d.border,
            onChanged: (b) => _set(_d.copyWith(border: b)),
            segments: [for (final b in StampBorder.values) (b, b.label, null)],
          ),
          const SignSectionLabel('Icon'),
          SignSegmented<StampIcon>(
            value: _d.icon,
            onChanged: (i) => _set(_d.copyWith(icon: i)),
            segments: [for (final i in StampIcon.values) (i, i.label, null)],
          ),
          const SizedBox(height: DsSpacing.sm),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Tinted fill'),
            value: _d.filled,
            onChanged: (v) => _set(_d.copyWith(filled: v)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Include my name'),
            value: _d.includeUser,
            onChanged: (v) => _set(_d.copyWith(includeUser: v)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Include date'),
            value: _d.includeDate,
            onChanged: (v) => _set(_d.copyWith(includeDate: v)),
          ),
          AnimatedSize(
            duration: DsMotion.switchDuration,
            curve: DsMotion.switchCurve,
            child: _d.includeDate
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: kStampDateFormats.contains(_d.dateFormat)
                            ? _d.dateFormat
                            : kStampDateFormats.first,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Date format',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final f in kStampDateFormats)
                            DropdownMenuItem(
                              value: f,
                              child: Text(formatStampDate(ctx.now, f)),
                            ),
                        ],
                        onChanged: (f) =>
                            f == null ? null : _set(_d.copyWith(dateFormat: f)),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Include time'),
                        value: _d.includeTime,
                        onChanged: (v) => _set(_d.copyWith(includeTime: v)),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _d.title.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _d.copyWith(
                      title: _d.title.trim(),
                      category: StampCategory.custom,
                    ),
                  ),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Save stamp'),
        ),
      ],
    );
  }
}
