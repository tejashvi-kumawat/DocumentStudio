import 'dart:math' as math;

import 'package:document_studio/infrastructure/pdf/signing/pdf_incremental_signer.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_signature_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

enum SignPlaceableKind { signature, initials, stamp, image }

/// A library item (signature, initials, stamp, image) that can be placed.
@immutable
class SignPlaceable {
  const SignPlaceable({
    required this.id,
    required this.kind,
    required this.png,
    required this.sizePt,
    required this.label,
    this.refresh,
  });

  final String id;
  final SignPlaceableKind kind;
  final Uint8List png;

  /// Default size on the page, in PDF points.
  final Size sizePt;
  final String label;

  /// Re-renders dynamic content (e.g. a stamp's date/time) at drop time.
  final Future<SignPlaceable> Function()? refresh;

  double get aspect => sizePt.height > 0 ? sizePt.width / sizePt.height : 1.0;
}

/// An item placed on a page. [committed] items are already in the working
/// copy and stay on screen as an overlay so the viewer does not reopen the PDF.
@immutable
class SignPlacedItem {
  const SignPlacedItem({
    required this.id,
    required this.source,
    required this.png,
    required this.page1Based,
    required this.rectNorm,
    this.rotationDegrees = 0,
    this.committed = false,
  });

  final int id;
  final SignPlaceable source;
  final Uint8List png;
  final int page1Based;

  /// Unrotated box in normalized top-left displayed-page coordinates.
  final Rect rectNorm;

  /// Clockwise rotation about the box center.
  final double rotationDegrees;

  /// Written into the session working copy. Still drawn here so Apply does
  /// not have to reload [PdfViewer].
  final bool committed;

  SignPlacedItem copyWith({
    Uint8List? png,
    int? page1Based,
    Rect? rectNorm,
    double? rotationDegrees,
    bool? committed,
  }) {
    return SignPlacedItem(
      id: id,
      source: source,
      png: png ?? this.png,
      page1Based: page1Based ?? this.page1Based,
      rectNorm: rectNorm ?? this.rectNorm,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      committed: committed ?? this.committed,
    );
  }
}

/// Revisions written by Sign / stamp Apply. The page overlay already shows
/// those images, so the viewer must not soft-reload (that reopens the PDF).
abstract final class SignOwnRevisions {
  static final Map<String, int> _byPath = {};

  static void mark(String path, int revision) => _byPath[path] = revision;

  static bool isOwn(String path, int revision) => _byPath[path] == revision;
}

/// Short-lived highlight after "Show field".
@immutable
class SignFieldFlash {
  const SignFieldFlash(this.page1Based, this.rectNorm, this.generation);
  final int page1Based;
  final Rect rectNorm;
  final int generation;
}

/// Shared state between the sign panel and the per-page sign layers:
/// placed items, the armed library item, signature fields and their status.
class SignPlacementController extends ChangeNotifier {
  final List<SignPlacedItem> _items = [];
  int? _selectedId;

  /// Source path these items belong to. Other open viewers must not paint them.
  String? _ownerPath;
  SignPlaceable? _armed;
  int _seq = 0;
  bool _dragHover = false;
  bool _libraryDrag = false;
  bool _drawFieldMode = false;
  List<PdfSignatureFieldInfo> _fields = const [];
  List<PdfSignatureStatus> _statuses = const [];
  SignFieldFlash? _flash;
  final Map<int, Size> _pageSizesPt = {};
  PdfViewerController? _viewer;

  /// Bumped on pointer-move edits so only page layers repaint while dragging.
  final ValueNotifier<int> draftRevision = ValueNotifier<int>(0);
  late final Listenable pageListenable = Listenable.merge([
    this,
    draftRevision,
  ]);

  /// Set by the panel: write placed items into the PDF.
  VoidCallback? onApply;

  /// Set by the panel: an unsigned signature field was clicked.
  void Function(PdfSignatureFieldInfo field)? onFieldTap;

  /// Set by the panel: a signed field was clicked.
  void Function(PdfSignatureStatus status)? onSignedFieldTap;

  /// Set by the panel: the user drew a new signature field.
  void Function(int page1Based, Rect rectNorm)? onFieldDrawn;

  /// Images not yet written into the working copy.
  List<SignPlacedItem> get pendingItems => [
    for (final i in _items)
      if (!i.committed) i,
  ];

  bool get hasItems => pendingItems.isNotEmpty;
  int get pendingCount => pendingItems.length;

  /// Every image drawn on the page, including ones already burned.
  List<SignPlacedItem> get items => List.unmodifiable(_items);

  /// Source path that owns [items]. Null until the foreground viewer claims it.
  String? get ownerPath => _ownerPath;

  /// Foreground viewer claims this session. Does not notify.
  void attachDocument(String sourcePath) {
    _ownerPath = sourcePath;
  }

  /// Drop placement when the foreground document changes.
  void adoptDocument(String sourcePath) {
    if (_ownerPath == sourcePath) return;
    _ownerPath = sourcePath;
    if (_items.isEmpty &&
        _armed == null &&
        !_drawFieldMode &&
        _selectedId == null) {
      return;
    }
    _items.clear();
    _armed = null;
    _drawFieldMode = false;
    _selectedId = null;
    _dragHover = false;
    _libraryDrag = false;
    notifyListeners();
  }

  int? get selectedId => _selectedId;
  SignPlacedItem? get selected {
    for (final i in _items) {
      if (i.id == _selectedId) return i;
    }
    return null;
  }

  SignPlaceable? get armed => _armed;
  bool get dragHover => _dragHover;

  /// True from library-card drag start until the drag ends, so the page can
  /// claim the pointer and the viewer scroller does not pan under the ghost.
  bool get libraryDrag => _libraryDrag;
  bool get drawFieldMode => _drawFieldMode;
  List<PdfSignatureFieldInfo> get fields => _fields;
  List<PdfSignatureStatus> get statuses => _statuses;
  SignFieldFlash? get flash => _flash;
  PdfViewerController? get viewer => _viewer;

  /// True while placing or editing a signature/stamp on the page (armed,
  /// drawing a field, or with uncommitted placed items). Viewer chrome swaps
  /// to Cancel / Done and hides tool menus so drag is not stolen.
  bool get isPageInteractionActive =>
      _armed != null || _drawFieldMode || hasItems;

  Iterable<SignPlacedItem> itemsOnPage(int page) =>
      _items.where((i) => i.page1Based == page);

  Size? pageSizePt(int page) => _pageSizesPt[page];

  void notePage(int page, Size sizePt) => _pageSizesPt[page] = sizePt;

  void attachViewer(PdfViewerController? controller) {
    if (controller != null) _viewer = controller;
  }

  PdfSignatureStatus? statusForField(String name) {
    for (final s in _statuses) {
      if (s.fieldName == name) return s;
    }
    return null;
  }

  void arm(SignPlaceable? item) {
    _armed = item;
    if (item != null) {
      _drawFieldMode = false;
      _selectedId = null;
    }
    notifyListeners();
  }

  void setDragHover(bool value) {
    if (_dragHover == value) return;
    _dragHover = value;
    notifyListeners();
  }

  void setLibraryDrag(bool value) {
    if (_libraryDrag == value) return;
    _libraryDrag = value;
    notifyListeners();
  }

  void setDrawFieldMode(bool value) {
    if (_drawFieldMode == value) return;
    _drawFieldMode = value;
    if (value) {
      _armed = null;
      _selectedId = null;
    }
    notifyListeners();
  }

  void setFields(
    List<PdfSignatureFieldInfo> fields,
    List<PdfSignatureStatus> statuses,
  ) {
    _fields = fields;
    _statuses = statuses;
    notifyListeners();
  }

  /// Default normalized size for [item] on [page] (capped to the page).
  Size _normSizeFor(SignPlaceable item, Size pagePt, {Rect? fitInto}) {
    var w = item.sizePt.width;
    var h = item.sizePt.height;
    if (fitInto != null) {
      final fw = fitInto.width * pagePt.width * 0.94;
      final fh = fitInto.height * pagePt.height * 0.86;
      final s = math.min(fw / w, fh / h);
      w *= s;
      h *= s;
    }
    final maxW = pagePt.width * 0.8;
    final maxH = pagePt.height * 0.5;
    final s = math.min(1.0, math.min(maxW / w, maxH / h));
    return Size(w * s / pagePt.width, h * s / pagePt.height);
  }

  /// Box [place] would use; also drives the drag / hover ghost.
  Rect defaultRect(
    SignPlaceable item, {
    required Size pageSizePt,
    required Offset centerNorm,
    Rect? fitInto,
  }) {
    final size = _normSizeFor(item, pageSizePt, fitInto: fitInto);
    return _clampRect(
      Rect.fromCenter(
        center: fitInto?.center ?? centerNorm,
        width: size.width,
        height: size.height,
      ),
    );
  }

  /// Places [item] centred at [centerNorm] (or inside [fitInto]) on [page].
  Future<void> place(
    SignPlaceable item, {
    required int page1Based,
    required Offset centerNorm,
    Size? pageSizePt,
    Rect? fitInto,
  }) async {
    final pagePt =
        pageSizePt ?? _pageSizesPt[page1Based] ?? const Size(612, 792);
    final rect = defaultRect(
      item,
      pageSizePt: pagePt,
      centerNorm: centerNorm,
      fitInto: fitInto,
    );
    final placed = SignPlacedItem(
      id: ++_seq,
      source: item,
      png: item.png,
      page1Based: page1Based,
      rectNorm: rect,
    );
    _items.add(placed);
    _selectedId = placed.id;
    _armed = null;
    notifyListeners();
    final refresh = item.refresh;
    if (refresh != null) {
      try {
        final fresh = await refresh();
        final i = _items.indexWhere((e) => e.id == placed.id);
        if (i >= 0) {
          final cur = _items[i];
          // Keep the box width, follow the refreshed content's aspect.
          final hNorm =
              cur.rectNorm.width * pagePt.width / fresh.aspect / pagePt.height;
          _items[i] = cur.copyWith(
            png: fresh.png,
            rectNorm: _clampRect(
              Rect.fromCenter(
                center: cur.rectNorm.center,
                width: cur.rectNorm.width,
                height: hNorm,
              ),
            ),
          );
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  static Rect _clampRect(Rect r) {
    final w = r.width.clamp(0.004, 1.0);
    final h = r.height.clamp(0.004, 1.0);
    final l = r.left.clamp(0.0, 1.0 - w);
    final t = r.top.clamp(0.0, 1.0 - h);
    return Rect.fromLTWH(l, t, w, h);
  }

  void select(int? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  void update(
    int id, {
    Rect? rectNorm,
    double? rotationDegrees,
    bool draft = false,
  }) {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(
      rectNorm: rectNorm == null ? null : _clampRect(rectNorm),
      rotationDegrees: rotationDegrees,
    );
    if (draft) {
      draftRevision.value++;
    } else {
      notifyListeners();
    }
  }

  void commitDraft() => notifyListeners();

  void remove(int id) {
    _items.removeWhere((e) => e.id == id);
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }

  void removeSelected() {
    final id = _selectedId;
    if (id != null) remove(id);
  }

  void duplicate(int id) {
    final src = _items.where((e) => e.id == id).firstOrNull;
    if (src == null) return;
    final copy = SignPlacedItem(
      id: ++_seq,
      source: src.source,
      png: src.png,
      page1Based: src.page1Based,
      rectNorm: _clampRect(src.rectNorm.shift(const Offset(0.02, 0.02))),
      rotationDegrees: src.rotationDegrees,
    );
    _items.add(copy);
    _selectedId = copy.id;
    notifyListeners();
  }

  void rotateBy(int id, double degrees) {
    final src = _items.where((e) => e.id == id).firstOrNull;
    if (src == null) return;
    var d = (src.rotationDegrees + degrees) % 360;
    if (d > 180) d -= 360;
    update(id, rotationDegrees: d);
  }

  void clearItems() {
    final before = _items.length;
    _items.removeWhere((i) => !i.committed);
    if (_selectedId != null && !_items.any((i) => i.id == _selectedId)) {
      _selectedId = null;
    }
    if (_items.length != before) notifyListeners();
  }

  /// Overlay images are now in the working copy. Keep drawing them.
  void markBurned() {
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].committed) continue;
      _items[i] = _items[i].copyWith(committed: true);
      changed = true;
    }
    _armed = null;
    _selectedId = null;
    if (changed) notifyListeners();
  }

  /// A real document reload is showing the burned bytes. Drop the overlay.
  void dropBurnedItems() {
    final before = _items.length;
    _items.removeWhere((i) => i.committed);
    if (_selectedId != null && !_items.any((i) => i.id == _selectedId)) {
      _selectedId = null;
    }
    if (_items.length != before) notifyListeners();
  }

  /// Digital Sign appearance, already written to the working copy.
  void rememberBurnedAppearance({
    required Uint8List png,
    required int page1Based,
    required Rect rectNorm,
  }) {
    if (rectNorm.width < 0.002 || rectNorm.height < 0.002) return;
    final id = ++_seq;
    _items.add(
      SignPlacedItem(
        id: id,
        source: SignPlaceable(
          id: 'burned:$id',
          kind: SignPlaceableKind.signature,
          png: png,
          sizePt: const Size(160, 48),
          label: 'Signature',
        ),
        png: png,
        page1Based: page1Based,
        rectNorm: _clampRect(rectNorm),
        committed: true,
      ),
    );
    notifyListeners();
  }

  void requestApply() => onApply?.call();

  /// Discards the current placement session (armed item, draft field, items).
  void cancelPageInteraction() {
    final pending = _items.any((i) => !i.committed);
    final changed =
        _armed != null || _drawFieldMode || pending || _selectedId != null;
    _armed = null;
    _drawFieldMode = false;
    _dragHover = false;
    _libraryDrag = false;
    _items.removeWhere((i) => !i.committed);
    _selectedId = null;
    if (changed) notifyListeners();
  }

  /// Scrolls the viewer to [rectNorm] on [page1Based] and flashes it.
  Future<void> showField(int page1Based, Rect rectNorm) async {
    _flash = SignFieldFlash(
      page1Based,
      rectNorm,
      (_flash?.generation ?? 0) + 1,
    );
    notifyListeners();
    final v = _viewer;
    if (v == null || !v.isReady) return;
    try {
      final layouts = v.layout.pageLayouts;
      if (page1Based < 1 || page1Based > layouts.length) return;
      final pr = layouts[page1Based - 1];
      final r = Rect.fromLTRB(
        pr.left + rectNorm.left * pr.width,
        pr.top + rectNorm.top * pr.height,
        pr.left + rectNorm.right * pr.width,
        pr.top + rectNorm.bottom * pr.height,
      );
      await v.ensureVisible(
        r.inflate(math.max(r.width, r.height) * 0.6 + 24),
        duration: const Duration(milliseconds: 320),
      );
    } catch (_) {
      try {
        await v.goToPage(pageNumber: page1Based);
      } catch (_) {}
    }
  }

  /// Drops everything tied to the current panel session.
  void reset() {
    // Keep burned images. Closing the panel must not wipe a signature that
    // is already in the working copy and still drawn on the page.
    _items.removeWhere((i) => !i.committed);
    _selectedId = null;
    _armed = null;
    _dragHover = false;
    _libraryDrag = false;
    _drawFieldMode = false;
    _fields = const [];
    _statuses = const [];
    _flash = null;
    onApply = null;
    onFieldTap = null;
    onSignedFieldTap = null;
    onFieldDrawn = null;
    notifyListeners();
  }

  @override
  void dispose() {
    draftRevision.dispose();
    super.dispose();
  }
}

final signPlacementControllerProvider = Provider<SignPlacementController>((
  ref,
) {
  final c = SignPlacementController();
  ref.onDispose(c.dispose);
  return c;
});

bool get _touchFirst =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Drag source for library cards. Mouse: drag immediately. Touch: long-press
/// (so the list still scrolls). The on-page ghost takes over from the
/// floating feedback while the pointer is over a page.
class SignLibraryDraggable extends StatelessWidget {
  const SignLibraryDraggable({
    super.key,
    required this.item,
    required this.controller,
    required this.child,
    this.enabled = true,
  });

  final SignPlaceable item;
  final SignPlacementController controller;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final feedbackW = math.min(180.0, math.max(60.0, item.aspect * 56));
    final feedback = ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AnimatedOpacity(
        opacity: controller.dragHover ? 0 : 0.9,
        duration: const Duration(milliseconds: 90),
        child: Transform.translate(
          offset: Offset(-feedbackW / 2, -feedbackW / item.aspect / 2),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: feedbackW,
              height: feedbackW / item.aspect,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Image.memory(item.png, fit: BoxFit.fill),
            ),
          ),
        ),
      ),
    );
    void start() => controller.setLibraryDrag(true);
    void end() {
      controller.setLibraryDrag(false);
      controller.setDragHover(false);
    }

    final dimmed = Opacity(opacity: 0.45, child: child);
    if (_touchFirst) {
      // Short delay so a deliberate drag starts quickly; long enough that
      // the library list can still scroll on a flick.
      return LongPressDraggable<SignPlaceable>(
        data: item,
        delay: const Duration(milliseconds: 160),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        childWhenDragging: dimmed,
        onDragStarted: start,
        onDragEnd: (_) => end(),
        onDraggableCanceled: (_, _) => end(),
        child: child,
      );
    }
    return Draggable<SignPlaceable>(
      data: item,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: dimmed,
      onDragStarted: start,
      onDragEnd: (_) => end(),
      onDraggableCanceled: (_, _) => end(),
      child: child,
    );
  }
}
