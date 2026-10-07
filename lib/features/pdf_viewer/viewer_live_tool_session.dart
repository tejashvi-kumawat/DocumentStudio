import 'dart:ui' as ui;

import 'package:document_studio/core/settings/app_prefs.dart';
import 'package:document_studio/core/fonts/font_library.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_editor.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:document_studio/features/pdf_markup/header_footer/hf_preview_painter.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_crop_quad_math.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_canvas.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_math.dart';
import 'package:document_studio/features/pdf_viewer/widgets/watermark_preview_painter.dart';
import 'package:document_studio/infrastructure/pdf/pdf_form_spot_detector.dart';
import 'package:document_studio/infrastructure/pdf/pdf_text_blank_detector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sub-tools for live-page draw mode ([ViewerToolId.ink]).
enum LiveDrawTool {
  pen,
  highlighter,
  line,
  arrow,
  rectangle,
  ellipse,
  callout,
  stamp,
}

/// Text-markup kinds drawn as filled bands ([ViewerToolId.markupBurn]).
enum LiveMarkupKind { highlight, underline, strikethrough, note }

/// Crop interaction mode on the live page.
enum LiveCropMode { rectangle, quad }

/// Vertical slot for live page-number / header / footer previews.
enum LiveMarginVertical { top, bottom }

/// Horizontal alignment for margin-band previews.
enum LiveMarginAlign { left, center, right }

/// Page-number label formats shown in the options strip.
enum LivePageNumberFormat { pageN, nOfM }

/// Default highlight / markup colors shared by preview and writer.
const Color kLiveHighlightColor = Color(0xFFFFE14D);
const double kLiveHighlightOpacity = 0.42;
const Color kLiveUnderlineColor = Color(0xFFE4002B);
const Color kLiveStrikeColor = Color(0xFF333333);
const Color kLiveNoteFill = Color(0xFFFFF3A6);
const Color kLiveNoteStroke = Color(0xFFBFA636);

/// One completed draw / markup object waiting to be burned into the PDF.
class LiveDrawCommit {
  const LiveDrawCommit({
    required this.tool,
    required this.pointsNorm,
    required this.color,
    required this.strokeWidthPt,
    this.labelText,
    this.opacity = 1,
    this.pageIndex1Based = 0,
    this.markupKind,
    this.rectsNorm = const [],
    this.closed = false,
  });

  final LiveDrawTool tool;
  final List<Offset> pointsNorm;
  final Color color;
  final double strokeWidthPt;
  final String? labelText;

  /// Stroke / fill opacity.
  final double opacity;

  /// Page this object belongs to (0 = legacy: session page at burn time).
  final int pageIndex1Based;

  /// Non-null for text-markup commits (filled bands in [rectsNorm]).
  final LiveMarkupKind? markupKind;

  /// Normalized top-left rects for markup bands / note boxes.
  final List<Rect> rectsNorm;

  /// Close the polyline (rectangles / ellipses / callouts).
  final bool closed;
}

/// Text box committed on the page, shown until the burned page re-renders.
class LivePendingText {
  const LivePendingText({
    required this.id,
    required this.pageIndex1Based,
    required this.boxNorm,
    required this.lines,
    required this.fontSizePt,
    required this.color,
    required this.bold,
    required this.align,
    this.coverNorm,
    this.coverRects = const [],
    this.coverColor,
    this.italic = false,
    this.family = 'sans',
    this.lineHeightEm = 1.2,
    this.customFamily,
  });

  final int id;
  final int pageIndex1Based;
  final Rect boxNorm;
  final List<String> lines;
  final double fontSizePt;
  final Color color;
  final bool bold;
  final LiveMarginAlign align;

  /// Cover drawn under replaced text runs.
  final Rect? coverNorm;
  final List<Rect> coverRects;
  final Color? coverColor;
  final bool italic;
  final String family;
  final double lineHeightEm;
  final String? customFamily;
}

enum ImageEditKind { move, delete, replace, recolor }

/// What Edit shows for an object change that is not written yet: the old
/// spot covered and (for a move) the object's picture at its new place.
class LiveObjectGhost {
  LiveObjectGhost({
    required this.page,
    required this.from,
    this.to,
    this.image,
  });

  final int page;
  final Rect from;
  final Rect? to;
  final ui.Image? image;
}

/// A change the user made to an image in Edit PDF mode.
class ImageEditRequest {
  const ImageEditRequest(this.kind, this.image, [this.rect, this.color]);

  final ImageEditKind kind;
  final EditableImage image;

  /// New rectangle (normalized) for [ImageEditKind.move].
  final Rect? rect;

  /// New colour for [ImageEditKind.recolor] (vector shapes).
  final Color? color;
}

/// Existing link annotation on the active page (normalized top-left rect).
class LiveLinkHit {
  const LiveLinkHit({required this.normRect, this.uri, this.destPage1Based});

  final Rect normRect;
  final String? uri;
  final int? destPage1Based;
}

/// Editable text run selected on the live page (normalized top-left box).
class LiveTextEditTarget {
  const LiveTextEditTarget({
    required this.normRect,
    required this.originalText,
    required this.fontSizePt,
    this.coverNorm,
    this.coverRects = const [],
    this.coverColor,
    this.textColor,
    this.lineCount = 1,
    this.fontMatch,
    this.leadingEm = 1.2,
  });

  /// Editor line box (top = line top, so the baseline lands on the original).
  final Rect normRect;
  final String originalText;
  final double fontSizePt;

  /// Glyph bounds of the original run — hit area and white-out cover.
  final Rect? coverNorm;

  /// Per-line glyph bounds of a grouped block (what gets painted over).
  final List<Rect> coverRects;

  /// Page background sampled around the block, so the cover matches it.
  final Color? coverColor;

  /// Ink colour sampled inside the block.
  final Color? textColor;

  /// Lines in the original block (paragraph grouping).
  final int lineCount;

  /// Recognized original font (null when unknown).
  final FontMatch? fontMatch;

  /// Original line spacing in em (1.2 = single-line default).
  final double leadingEm;

  Rect get hitRect => coverNorm ?? normRect;
}

/// Interaction modes that draw on the live [PdfViewer] page (not a sidebar preview).
bool viewerToolUsesLivePageOverlay(ViewerToolId? id) {
  return switch (id) {
    ViewerToolId.placeImage ||
    ViewerToolId.visualSign ||
    ViewerToolId.ink ||
    ViewerToolId.redact ||
    ViewerToolId.crop ||
    ViewerToolId.watermark ||
    ViewerToolId.pageNumbers ||
    ViewerToolId.fillForm ||
    ViewerToolId.markupBurn ||
    ViewerToolId.headersFooters ||
    ViewerToolId.editText ||
    ViewerToolId.addLink => true,
    _ => false,
  };
}

/// Tools that can act on any visible page (click a page to work on it).
bool viewerToolSpansPages(ViewerToolId? id) {
  return switch (id) {
    ViewerToolId.placeImage ||
    ViewerToolId.visualSign ||
    ViewerToolId.ink ||
    ViewerToolId.markupBurn ||
    ViewerToolId.editText ||
    ViewerToolId.addLink => true,
    _ => false,
  };
}

/// Chaikin-smoothed, lightly simplified freehand polyline (normalized space).
///
/// Used for both the live preview and the burned stroke so they match.
List<Offset> smoothInkPolyline(List<Offset> pts, {int iterations = 2}) {
  if (pts.length < 3) return List<Offset>.from(pts);
  var cur = pts;
  for (var it = 0; it < iterations; it++) {
    final next = <Offset>[cur.first];
    for (var i = 0; i < cur.length - 1; i++) {
      final a = cur[i];
      final b = cur[i + 1];
      next.add(Offset(a.dx * 0.75 + b.dx * 0.25, a.dy * 0.75 + b.dy * 0.25));
      next.add(Offset(a.dx * 0.25 + b.dx * 0.75, a.dy * 0.25 + b.dy * 0.75));
    }
    next.add(cur.last);
    cur = next;
  }
  return _simplifyPolyline(cur, 0.00035);
}

List<Offset> _simplifyPolyline(List<Offset> pts, double epsilon) {
  if (pts.length < 3) return pts;
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (s, e) = stack.removeLast();
    final a = pts[s];
    final b = pts[e];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    var maxD = 0.0;
    var idx = -1;
    for (var i = s + 1; i < e; i++) {
      final p = pts[i];
      final d = len < 1e-12
          ? (p - a).distance
          : ((p.dx - a.dx) * dy - (p.dy - a.dy) * dx).abs() / len;
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (idx > 0 && maxD > epsilon) {
      keep[idx] = true;
      stack.add((s, idx));
      stack.add((idx, e));
    }
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) pts[i],
  ];
}

/// Shared placement / ink / form state for tools that act on the visible PDF page.
class ViewerLiveToolSession extends ChangeNotifier {
  ViewerToolId? _toolId;
  int _pageIndex1Based = 1;
  PagePlacementNorm _placement = const PagePlacementNorm(
    left: 0.55,
    top: 0.7,
    width: 0.35,
    height: 0.2,
  );
  Uint8List? _imageBytes;
  String? _labelText;
  final List<List<Offset>> _inkStrokesNorm = [];
  List<Offset>? _currentInkStroke;
  Rect? _dragRectNorm;
  Offset? _dragOriginNorm;
  PageCropQuadNorm? _cropQuadNorm;
  LiveCropMode _cropMode = LiveCropMode.rectangle;

  /// Physical width/height ratio for rectangle crop (`null` = free).
  double? _cropAspectPhysical;
  LiveDrawTool _drawTool = LiveDrawTool.pen;
  double _strokeWidthPt = 2.5;
  LiveDrawCommit? _pendingDrawCommit;
  final List<LiveDrawCommit> _queuedDrawCommits = [];
  final List<LiveDrawCommit> _redoDrawCommits = [];
  final Set<LiveDrawCommit> _burningDrawCommits = {};
  int _drawCommitEpoch = 0;
  Color _markupColor = const Color(0xFFE4002B);
  double _opacity = 0.35;
  double _fontSizePt = 14;
  bool _keepAspectRatio = true;
  bool _awaitingClickPlacement = false;
  bool _inlineEditing = false;
  List<PdfFormSpot> _formSpots = const [];
  final Map<String, String> _formValues = {};
  String? _activeFormSpotId;
  bool _formSpotsLoaded = false;
  String? _formSpotsMessage;
  final Set<int> _formPagesScanned = {};
  final Set<int> _formScanAccepted = {};
  final List<int> _formScanQueue = [];
  bool _formScanNotifyQueued = false;
  bool _closed = false;

  /// Bumped on every [focusFormSpot] so the overlay can requestFocus even when
  /// the same id is selected again (panel jump-to).
  int _formFocusGeneration = 0;
  bool _textBold = false;
  bool _textItalic = false;
  double _textLineHeight = 1.2;
  InstalledFont? _userFont;
  bool _embedFonts = AppPrefs.embedFontsByDefault;
  String _textFamily = 'sans';
  String? _detectedFont;
  LiveMarginAlign _textAlign = LiveMarginAlign.left;
  bool _creatingTextBox = false;
  bool _textBoxDragMoved = false;
  Offset? _textBoxCreateOriginNorm;
  LiveTextEditTarget? _textEditTarget;
  LiveTextEditTarget? _selectedRun;
  final List<LiveTextEditTarget> _textRunHits = [];
  final Map<int, List<LiveTextEditTarget>> _textRunsByPage = {};

  // Edit PDF — images on the page that can be selected and changed.
  final Map<int, List<EditableImage>> _imagesByPage = {};
  EditableImage? _selectedImage;
  Rect? _imageDraft;

  /// Set by the Edit panel: applies move / delete / replace to the document.
  void Function(ImageEditRequest request)? imageEditHandler;

  /// Set by the viewer screen: scrolls the document to a page.
  void Function(int page1Based)? pageJumpHandler;
  final List<LivePendingText> _pendingTexts = [];
  int _pendingTextSeq = 0;
  final List<Rect> _redactRectsNorm = [];
  final List<Rect> _searchHighlightRectsNorm = [];
  int _activeRedactIndex = 0;
  double _pageWidthPt = 612;
  double _pageHeightPt = 792;
  final Map<int, Size> _pageSizesPt = {};
  bool _pageGeometryReady = false;
  int _textCommitRequestId = 0;
  int _textCancelRequestId = 0;
  double _rotationDegrees = -45;
  bool _watermarkTiled = false;

  /// Stamp previews painted on every in-scope page. Separate notifiers so
  /// option changes repaint the page layers without rebuilding the viewer.
  final ValueNotifier<WatermarkPreviewState?> watermarkPreviewNotifier =
      ValueNotifier<WatermarkPreviewState?>(null);
  final ValueNotifier<HeaderFooterPreviewState?> headerFooterPreviewNotifier =
      ValueNotifier<HeaderFooterPreviewState?>(null);
  late final Listenable stampPreviewListenable = Listenable.merge([
    watermarkPreviewNotifier,
    headerFooterPreviewNotifier,
  ]);
  String _headerText = '';
  String _footerText = '';
  LiveMarginAlign _bandAlign = LiveMarginAlign.center;
  LiveMarginVertical _pageNumberVertical = LiveMarginVertical.bottom;
  LiveMarginAlign _pageNumberAlign = LiveMarginAlign.center;
  LivePageNumberFormat _pageNumberFormat = LivePageNumberFormat.pageN;
  int _pageNumberVisible = 1;
  int _pageNumberTotal = 1;
  Offset? _lastPointerNorm;
  LiveMarkupKind _markupKind = LiveMarkupKind.highlight;
  final List<LiveLinkHit> _linkHits = [];
  int? _selectedLinkIndex;
  int _linkHitsPage = 0;
  int _applyRequestId = 0;
  int _deleteRequestId = 0;

  /// Bumped on high-frequency drag updates (pointer move) — only the page
  /// overlay listens, so side panels do not rebuild on every mouse move.
  final ValueNotifier<int> draftRevision = ValueNotifier<int>(0);
  late final Listenable overlayListenable = Listenable.merge([
    this,
    draftRevision,
  ]);

  ViewerToolId? get toolId => _toolId;
  int get pageIndex1Based => _pageIndex1Based;
  PagePlacementNorm get placement => _placement;
  Uint8List? get imageBytes => _imageBytes;
  String? get labelText => _labelText;
  List<List<Offset>> get inkStrokesNorm =>
      List<List<Offset>>.unmodifiable(_inkStrokesNorm);
  List<Offset>? get currentInkStroke => _currentInkStroke;
  Rect? get dragRectNorm => _dragRectNorm;
  Offset? get dragOriginNorm => _dragOriginNorm;
  PageCropQuadNorm? get cropQuadNorm => _cropQuadNorm;
  LiveCropMode get cropMode => _cropMode;
  double? get cropAspectPhysical => _cropAspectPhysical;

  /// Normalized width/height for resize math (accounts for page pt aspect).
  double? get cropAspectNorm {
    final physical = _cropAspectPhysical;
    if (physical == null) return null;
    final pw = math.max(pageWidthPt, 1.0);
    final ph = math.max(pageHeightPt, 1.0);
    return physical * ph / pw;
  }

  LiveDrawTool get drawTool => _drawTool;
  double get strokeWidthPt => _strokeWidthPt;
  LiveDrawCommit? get pendingDrawCommit => _pendingDrawCommit;
  List<LiveDrawCommit> get queuedDrawCommits =>
      List<LiveDrawCommit>.unmodifiable(_queuedDrawCommits);

  /// Commits not yet sent to the writer (excludes an in-flight burn).
  List<LiveDrawCommit> get unburnedDrawCommits => [
    for (final c in _queuedDrawCommits)
      if (!_burningDrawCommits.contains(c)) c,
  ];
  bool get canUndoPendingDraw => unburnedDrawCommits.isNotEmpty;
  bool get canRedoPendingDraw => _redoDrawCommits.isNotEmpty;
  int get drawCommitEpoch => _drawCommitEpoch;
  Color get markupColor => _markupColor;
  double get opacity => _opacity;
  double get fontSizePt => _fontSizePt;
  bool get keepAspectRatio => _keepAspectRatio;
  bool get awaitingClickPlacement => _awaitingClickPlacement;
  bool get inlineEditing => _inlineEditing;
  List<PdfFormSpot> get formSpots => List.unmodifiable(_formSpots);
  Map<String, String> get formValues => Map.unmodifiable(_formValues);
  String? get activeFormSpotId => _activeFormSpotId;
  bool get formSpotsLoaded => _formSpotsLoaded;
  String? get formSpotsMessage => _formSpotsMessage;

  /// True once this page's text layer has been checked for underline blanks.
  bool formPageScanned(int page1Based) =>
      _formPagesScanned.contains(page1Based);

  /// Message for a scanned page that has nothing to type into. Null while
  /// the page is still unchecked, or when it has fillable spots.
  String? formPageEmptyMessage(int page1Based) {
    if (!_formPagesScanned.contains(page1Based)) return null;
    final any = _formSpots.any(
      (s) =>
          s.pageIndex1Based == page1Based &&
          s.kind != PdfFormSpotKind.signature,
    );
    if (any) return null;
    return _formSpotsMessage ?? noFillInBlanksOnPageMessage;
  }

  bool get hasPendingFormScans => _formScanQueue.isNotEmpty;
  int get formFocusGeneration => _formFocusGeneration;
  bool get textBold => _textBold;
  bool get textItalic => _textItalic;

  /// An installed font chosen for the text (null → standard family).
  InstalledFont? get textUserFont => _userFont;

  /// Embed the font in the PDF (standard families use the bundled Liberation
  /// equivalents; installed fonts are always embedded).
  bool get embedFonts => _embedFonts;

  void setTextUserFont(InstalledFont? font) {
    if (identical(_userFont, font)) return;
    _userFont = font;
    notifyListeners();
  }

  void setEmbedFonts(bool value) {
    if (_embedFonts == value) return;
    _embedFonts = value;
    notifyListeners();
  }

  /// Text width for wrapping with the chosen font (null → Helvetica metrics).
  double Function(String)? textMeasure(double sizePt) {
    final u = _userFont;
    return u == null ? null : (s) => u.ttf.textWidthPt(s, sizePt);
  }

  /// Line height (em) of the block being edited — the original's leading.
  double get textLineHeightEm => _textLineHeight;

  /// `sans`, `serif` or `mono`.
  String get textFamily => _textFamily;

  /// Original font of the text being edited, e.g. "Calibri-Bold".
  String? get detectedFont => _detectedFont;

  /// Standard-14 BaseFont for the current style.
  String get textFontBase {
    switch (_textFamily) {
      case 'serif':
        if (_textBold && _textItalic) return 'Times-BoldItalic';
        if (_textBold) return 'Times-Bold';
        if (_textItalic) return 'Times-Italic';
        return 'Times-Roman';
      case 'mono':
        if (_textBold && _textItalic) return 'Courier-BoldOblique';
        if (_textBold) return 'Courier-Bold';
        if (_textItalic) return 'Courier-Oblique';
        return 'Courier';
      default:
        if (_textBold && _textItalic) return 'Helvetica-BoldOblique';
        if (_textBold) return 'Helvetica-Bold';
        if (_textItalic) return 'Helvetica-Oblique';
        return 'Helvetica';
    }
  }

  void setTextItalic(bool value) {
    if (_textItalic == value) return;
    _textItalic = value;
    notifyListeners();
  }

  void setTextFamily(String value) {
    if (_textFamily == value) return;
    _textFamily = value;
    notifyListeners();
  }

  LiveMarginAlign get textAlign => _textAlign;
  bool get creatingTextBox => _creatingTextBox;
  Offset? get textBoxCreateOriginNorm => _textBoxCreateOriginNorm;
  LiveTextEditTarget? get textEditTarget => _textEditTarget;
  List<LiveTextEditTarget> get textRunHits => List.unmodifiable(_textRunHits);

  /// Text block selected (framed) but not yet being typed into.
  LiveTextEditTarget? get selectedRun => _selectedRun;

  void selectTextRun(LiveTextEditTarget? run) {
    if (identical(_selectedRun, run)) return;
    _selectedRun = run;
    if (run != null) {
      _selectedImage = null;
      _imageDraft = null;
    }
    notifyListeners();
  }

  List<EditableImage> imagesForPage(int page1Based) =>
      _imagesByPage[page1Based] ?? const [];
  EditableImage? get selectedImage => _selectedImage;

  /// Renders a page region (normalized rect) [widthPx] wide; set by Edit.
  Future<ui.Image?> Function(int page, Rect norm, double widthPx)?
  objectSnapshot;

  final List<LiveObjectGhost> _ghosts = [];
  List<LiveObjectGhost> ghostsForPage(int page) => [
    for (final g in _ghosts)
      if (g.page == page) g,
  ];

  void addGhost(LiveObjectGhost g) {
    // A later change of an object already moved continues its ghost, so the
    // original spot stays covered.
    var next = g;
    for (final o in _ghosts) {
      if (o.page == g.page && o.to == g.from) {
        next = LiveObjectGhost(
          page: g.page,
          from: o.from,
          to: g.to,
          image: g.image ?? o.image,
        );
        _ghosts.remove(o);
        break;
      }
    }
    _ghosts.add(next);
    notifyListeners();
  }

  void clearGhosts(int page) {
    final before = _ghosts.length;
    _ghosts.removeWhere((g) => g.page == page);
    if (_ghosts.length != before) notifyListeners();
  }

  /// Live rectangle while the selected image is being moved / resized.
  Rect? get imageDraft => _imageDraft;

  void setImagesForPage(int page1Based, List<EditableImage> images) {
    _imagesByPage[page1Based] = List.of(images);
    final sel = _selectedImage;
    if (sel != null && sel.page == page1Based) {
      // Re-select the same picture after a reload (offsets change on save).
      EditableImage? match;
      for (final i in images) {
        if ((i.normRect.center - sel.normRect.center).distance < 0.02) {
          match = i;
          break;
        }
      }
      _selectedImage = match;
    }
    notifyListeners();
  }

  void selectImage(EditableImage? image) {
    _selectedImage = image;
    if (image != null) _selectedRun = null;
    _imageDraft = null;
    notifyListeners();
  }

  /// Live rect while dragging: only the active page repaints (draft
  /// channel); releasing ([rect] null) tells everyone.
  void setImageDraft(Rect? rect) {
    _imageDraft = rect;
    if (rect == null) {
      notifyListeners();
    } else {
      _notifyDraft();
    }
  }

  List<LivePendingText> get pendingTexts => List.unmodifiable(_pendingTexts);
  List<Rect> get redactRectsNorm => List.unmodifiable(_redactRectsNorm);
  List<Rect> get searchHighlightRectsNorm =>
      List.unmodifiable(_searchHighlightRectsNorm);
  int get activeRedactIndex => _activeRedactIndex;

  /// Displayed (rotated, cropped) size of the active page in PDF points.
  double get pageWidthPt =>
      _pageSizesPt[_pageIndex1Based]?.width ?? _pageWidthPt;
  double get pageHeightPt =>
      _pageSizesPt[_pageIndex1Based]?.height ?? _pageHeightPt;
  bool get pageGeometryReady =>
      _pageGeometryReady || _pageSizesPt.containsKey(_pageIndex1Based);

  /// Displayed size of any page seen by the overlay (null if not laid out yet).
  Size? pageSizePtFor(int page1Based) => _pageSizesPt[page1Based];
  int get textCommitRequestId => _textCommitRequestId;
  int get textCancelRequestId => _textCancelRequestId;
  double get rotationDegrees => _rotationDegrees;
  bool get watermarkTiled => _watermarkTiled;
  WatermarkPreviewState? get watermarkPreview => watermarkPreviewNotifier.value;
  HeaderFooterPreviewState? get headerFooterPreview =>
      headerFooterPreviewNotifier.value;
  String get headerText => _headerText;
  String get footerText => _footerText;
  LiveMarginAlign get bandAlign => _bandAlign;
  LiveMarginVertical get pageNumberVertical => _pageNumberVertical;
  LiveMarginAlign get pageNumberAlign => _pageNumberAlign;
  LivePageNumberFormat get pageNumberFormat => _pageNumberFormat;
  int get pageNumberVisible => _pageNumberVisible;
  int get pageNumberTotal => _pageNumberTotal;
  Offset? get lastPointerNorm => _lastPointerNorm;
  LiveMarkupKind get markupKind => _markupKind;
  List<LiveLinkHit> get linkHits => List.unmodifiable(_linkHits);
  int get linkHitsPage => _linkHitsPage;
  int? get selectedLinkIndex => _selectedLinkIndex;
  LiveLinkHit? get selectedLink {
    final i = _selectedLinkIndex;
    if (i == null || i < 0 || i >= _linkHits.length) return null;
    return _linkHits[i];
  }

  /// Bumped when the user asks the active panel to apply (e.g. Enter on page).
  int get applyRequestId => _applyRequestId;

  /// Bumped when the user presses Delete on the page for panel-owned objects.
  int get deleteRequestId => _deleteRequestId;

  bool get isActive =>
      _toolId != null && viewerToolUsesLivePageOverlay(_toolId);

  bool get spansPages => viewerToolSpansPages(_toolId);

  bool get effectiveKeepAspect {
    if (HardwareKeyboard.instance.isShiftPressed) return !_keepAspectRatio;
    return _keepAspectRatio;
  }

  void _notifyDraft() {
    draftRevision.value++;
  }

  /// Publishes accumulated draft (pointer-move) changes to all listeners.
  void commitDraft() {
    notifyListeners();
  }

  void activate(
    ViewerToolId tool, {
    required int pageIndex1Based,
    PagePlacementNorm? placement,
    Uint8List? imageBytes,
    String? labelText,
    bool awaitingClickPlacement = false,
    LiveDrawTool? drawTool,
  }) {
    final sameTool = _toolId == tool;
    _toolId = tool;
    _pageIndex1Based = pageIndex1Based;
    if (placement != null) {
      _placement = clampPagePlacement(placement);
    }
    _imageBytes = imageBytes;
    _labelText = labelText;
    _inkStrokesNorm.clear();
    _currentInkStroke = null;
    _pendingDrawCommit = null;
    // Re-activating the same draw tool (sub-tool switch) keeps unburned marks.
    if (!(sameTool &&
        (tool == ViewerToolId.ink || tool == ViewerToolId.markupBurn))) {
      _queuedDrawCommits.clear();
      _redoDrawCommits.clear();
      _burningDrawCommits.clear();
    }
    if (drawTool != null) _drawTool = drawTool;
    if (tool == ViewerToolId.ink) {
      _strokeWidthPt = _drawTool == LiveDrawTool.highlighter ? 14.0 : 2.5;
      if (_drawTool == LiveDrawTool.highlighter) {
        _markupColor = kLiveHighlightColor;
      }
    }
    // Crop / redact start empty: the user drags the area themselves.
    _dragRectNorm = null;
    _dragOriginNorm = null;
    _cropQuadNorm = tool == ViewerToolId.crop
        ? PageCropQuadNorm.fromRect(
            _dragRectNorm ?? const Rect.fromLTRB(0.08, 0.08, 0.92, 0.92),
          )
        : null;
    _cropMode = LiveCropMode.rectangle;
    _cropAspectPhysical = null;
    _awaitingClickPlacement =
        awaitingClickPlacement ||
        tool == ViewerToolId.visualSign ||
        tool == ViewerToolId.editText;
    _inlineEditing = false;
    _creatingTextBox = false;
    _textBoxDragMoved = false;
    _textBoxCreateOriginNorm = null;
    _textEditTarget = null;
    _textRunHits.clear();
    _textRunsByPage.clear();
    _imagesByPage.clear();
    _selectedImage = null;
    _imageDraft = null;
    _textAlign = LiveMarginAlign.left;
    _redactRectsNorm.clear();
    _searchHighlightRectsNorm.clear();
    _activeRedactIndex = 0;
    _linkHits.clear();
    _selectedLinkIndex = null;
    _linkHitsPage = 0;
    if (!sameTool) _textCharRectsByPage.clear();
    if (tool != ViewerToolId.watermark) watermarkPreviewNotifier.value = null;
    if (tool != ViewerToolId.headersFooters &&
        tool != ViewerToolId.pageNumbers) {
      headerFooterPreviewNotifier.value = null;
    }
    if (tool == ViewerToolId.watermark) {
      _awaitingClickPlacement = false;
      _inlineEditing = false;
      _rotationDegrees = -45;
      _opacity = 0.2;
      _fontSizePt = 48;
      _watermarkTiled = false;
      _markupColor = const Color(0xFF666666);
      _labelText ??= 'CONFIDENTIAL';
    }
    if (tool == ViewerToolId.headersFooters) {
      _awaitingClickPlacement = false;
      _inlineEditing = false;
      _bandAlign = LiveMarginAlign.center;
    }
    if (tool == ViewerToolId.pageNumbers) {
      _awaitingClickPlacement = false;
      _inlineEditing = false;
      _pageNumberVertical = LiveMarginVertical.bottom;
      _pageNumberAlign = LiveMarginAlign.center;
      _pageNumberFormat = LivePageNumberFormat.pageN;
      _pageNumberVisible = pageIndex1Based;
      _pageNumberTotal = math.max(pageIndex1Based, 1);
    }
    if (tool == ViewerToolId.redact) {
      _redactRectsNorm.add(const Rect.fromLTRB(0.08, 0.08, 0.92, 0.92));
      _dragRectNorm = _redactRectsNorm.first;
    }
    if (tool != ViewerToolId.fillForm && tool != ViewerToolId.visualSign) {
      _resetFormDetection();
    }
    if (tool == ViewerToolId.placeImage) {
      _keepAspectRatio = true;
      _awaitingClickPlacement = imageBytes == null;
      _opacity = 1.0;
      _rotationDegrees = 0;
      _lastPointerNorm = null;
    }
    if (tool == ViewerToolId.visualSign) {
      _keepAspectRatio = true;
      _rotationDegrees = 0;
    }
    if (tool == ViewerToolId.ink && _drawTool == LiveDrawTool.stamp) {
      _labelText ??= 'APPROVED';
    }
    notifyListeners();
  }

  void deactivate() {
    if (_toolId == null &&
        _imageBytes == null &&
        _inkStrokesNorm.isEmpty &&
        _queuedDrawCommits.isEmpty &&
        _dragRectNorm == null &&
        _cropQuadNorm == null &&
        _formSpots.isEmpty) {
      return;
    }
    _toolId = null;
    watermarkPreviewNotifier.value = null;
    headerFooterPreviewNotifier.value = null;
    _imageBytes = null;
    _labelText = null;
    _inkStrokesNorm.clear();
    _currentInkStroke = null;
    _pendingDrawCommit = null;
    _queuedDrawCommits.clear();
    _redoDrawCommits.clear();
    _burningDrawCommits.clear();
    _dragRectNorm = null;
    _dragOriginNorm = null;
    _cropQuadNorm = null;
    _awaitingClickPlacement = false;
    _inlineEditing = false;
    _creatingTextBox = false;
    _textBoxDragMoved = false;
    _textBoxCreateOriginNorm = null;
    _textEditTarget = null;
    _textRunHits.clear();
    _textRunsByPage.clear();
    _imagesByPage.clear();
    _selectedImage = null;
    _imageDraft = null;
    _redactRectsNorm.clear();
    _searchHighlightRectsNorm.clear();
    _activeRedactIndex = 0;
    _resetFormDetection();
    _linkHits.clear();
    _selectedLinkIndex = null;
    _linkHitsPage = 0;
    notifyListeners();
  }

  void setPage(int pageIndex1Based) {
    if (_pageIndex1Based == pageIndex1Based) return;
    _pageIndex1Based = pageIndex1Based;
    notifyListeners();
  }

  /// Makes [page1Based] the working page after the user clicks on it.
  ///
  /// Per-page transient state (text runs, link hits, drag rect) is reset; queued
  /// draw commits keep their own page.
  void focusPage(int page1Based) {
    if (_pageIndex1Based == page1Based) return;
    _pageIndex1Based = page1Based;
    _currentInkStroke = null;
    switch (_toolId) {
      case ViewerToolId.addLink:
      case ViewerToolId.markupBurn:
        _dragRectNorm = null;
        _dragOriginNorm = null;
        _linkHits.clear();
        _selectedLinkIndex = null;
      case ViewerToolId.editText:
        _textEditTarget = null;
        _textRunHits
          ..clear()
          ..addAll(_textRunsByPage[page1Based] ?? const []);
        _creatingTextBox = false;
        _textBoxDragMoved = false;
        _textBoxCreateOriginNorm = null;
        _inlineEditing = false;
        _awaitingClickPlacement = true;
        _labelText = '';
      default:
        break;
    }
    notifyListeners();
  }

  /// Records the displayed page size reported by the viewer (no notify —
  /// called while the overlay builds).
  void notePageGeometry(int page1Based, double widthPt, double heightPt) {
    if (!(widthPt.isFinite &&
        widthPt > 1 &&
        heightPt.isFinite &&
        heightPt > 1)) {
      return;
    }
    _pageSizesPt[page1Based] = Size(widthPt, heightPt);
  }

  void setPlacement(PagePlacementNorm placement, {bool draft = false}) {
    _placement = clampPagePlacement(placement, minFraction: 0.005);
    if (draft) {
      _notifyDraft();
    } else {
      notifyListeners();
    }
  }

  /// Places a default-sized box centered on a normalized page tap.
  void placeAtNorm(
    Offset normCenter, {
    double width = 0.32,
    double height = 0.1,
    bool startEditing = true,
  }) {
    final w = width.clamp(0.005, 1.0);
    final h = height.clamp(0.005, 1.0);
    _placement = clampPagePlacement(
      PagePlacementNorm(
        left: normCenter.dx - w / 2,
        top: normCenter.dy - h / 2,
        width: w,
        height: h,
      ),
      minFraction: 0.005,
    );
    _awaitingClickPlacement = false;
    _inlineEditing = startEditing;
    notifyListeners();
  }

  /// Places a text box with its top-left at the tap (caret under the click).
  void placeTextTopLeftAtNorm(
    Offset topLeft, {
    double width = 0.28,
    double height = 0.06,
  }) {
    final w = width.clamp(0.01, 1.0);
    final h = height.clamp(0.005, 1.0);
    _textEditTarget = null;
    _creatingTextBox = false;
    _textBoxDragMoved = false;
    _textBoxCreateOriginNorm = null;
    _labelText = '';
    _placement = clampPagePlacement(
      PagePlacementNorm(left: topLeft.dx, top: topLeft.dy, width: w, height: h),
      minFraction: 0.005,
    );
    _awaitingClickPlacement = false;
    _inlineEditing = true;
    notifyListeners();
  }

  /// Starts Acrobat-style new-text drag: width comes from the drag, then type.
  void beginCreateTextBoxAtNorm(
    Offset originNorm, {
    required double heightNorm,
  }) {
    _textLineHeight = 1.2;
    _textEditTarget = null;
    _labelText = '';
    _creatingTextBox = true;
    _textBoxDragMoved = false;
    _textBoxCreateOriginNorm = originNorm;
    _awaitingClickPlacement = false;
    _inlineEditing = false;
    final h = heightNorm.clamp(0.005, 0.8);
    _placement = clampPagePlacement(
      PagePlacementNorm(
        left: originNorm.dx,
        top: originNorm.dy,
        width: 0.005,
        height: h,
      ),
      minFraction: 0.005,
    );
    notifyListeners();
  }

  /// Updates the in-progress width drag (pointer-down origin + current tip).
  void updateCreateTextBoxAtNorm(
    Offset currentNorm, {
    required double heightNorm,
  }) {
    final origin = _textBoxCreateOriginNorm;
    if (!_creatingTextBox || origin == null) return;
    if ((currentNorm.dx - origin.dx).abs() >= 0.012) {
      _textBoxDragMoved = true;
    }
    final left = math.min(origin.dx, currentNorm.dx).clamp(0.0, 1.0);
    final right = math.max(origin.dx, currentNorm.dx).clamp(0.0, 1.0);
    final width = math.max(0.005, right - left);
    _placement = clampPagePlacement(
      PagePlacementNorm(
        left: left,
        top: origin.dy.clamp(0.0, 1.0),
        width: width,
        height: heightNorm.clamp(0.005, 0.8),
      ),
      minFraction: 0.005,
    );
    _notifyDraft();
  }

  /// Ends the create gesture and opens the inline caret inside the box.
  ///
  /// A plain click (no horizontal drag) creates a default-width box at the
  /// click, like Acrobat's Add Text.
  void finishCreateTextBox({
    bool commit = true,
    double defaultWidthNorm = 0.3,
  }) {
    if (!_creatingTextBox) return;
    _creatingTextBox = false;
    final moved = _textBoxDragMoved;
    final origin = _textBoxCreateOriginNorm;
    _textBoxCreateOriginNorm = null;
    _textBoxDragMoved = false;
    if (!commit) {
      _awaitingClickPlacement = true;
      _inlineEditing = false;
      _labelText = '';
      notifyListeners();
      return;
    }
    if (!moved || _placement.width < 0.02) {
      final left = (origin?.dx ?? _placement.left).clamp(0.0, 0.98);
      final width = math.min(defaultWidthNorm, 1.0 - left).clamp(0.02, 1.0);
      _placement = clampPagePlacement(
        _placement.copyWith(left: left, width: width),
        minFraction: 0.005,
      );
    }
    _awaitingClickPlacement = false;
    _inlineEditing = true;
    notifyListeners();
  }

  void cancelCreateTextBox() {
    if (!_creatingTextBox && _textBoxCreateOriginNorm == null) return;
    _creatingTextBox = false;
    _textBoxDragMoved = false;
    _textBoxCreateOriginNorm = null;
    _awaitingClickPlacement = true;
    _inlineEditing = false;
    _labelText = '';
    notifyListeners();
  }

  void setPageGeometryPt({required double widthPt, required double heightPt}) {
    final w = (widthPt.isFinite && widthPt > 0 ? widthPt : 612).toDouble();
    final h = (heightPt.isFinite && heightPt > 0 ? heightPt : 792).toDouble();
    if (_pageGeometryReady &&
        (_pageWidthPt - w).abs() < 0.01 &&
        (_pageHeightPt - h).abs() < 0.01) {
      return;
    }
    _pageWidthPt = w;
    _pageHeightPt = h;
    _pageGeometryReady = true;
    notifyListeners();
  }

  void requestTextCommit() {
    _textCommitRequestId++;
    notifyListeners();
  }

  void requestTextCancel() {
    _textCancelRequestId++;
    _labelText = '';
    _textEditTarget = null;
    _creatingTextBox = false;
    _textBoxDragMoved = false;
    _textBoxCreateOriginNorm = null;
    _awaitingClickPlacement = true;
    _inlineEditing = false;
    notifyListeners();
  }

  /// Clears the edited text box after its contents were handed to the writer.
  void finishTextEditAfterCommit() {
    _labelText = '';
    _textEditTarget = null;
    _creatingTextBox = false;
    _inlineEditing = false;
    _awaitingClickPlacement = true;
    notifyListeners();
  }

  int addPendingText({
    required int pageIndex1Based,
    required Rect boxNorm,
    required List<String> lines,
    required double fontSizePt,
    required Color color,
    required bool bold,
    required LiveMarginAlign align,
    Rect? coverNorm,
    List<Rect> coverRects = const [],
    Color? coverColor,
    bool italic = false,
    String family = 'sans',
    double lineHeightEm = 1.2,
    String? customFamily,
  }) {
    final id = ++_pendingTextSeq;
    _pendingTexts.add(
      LivePendingText(
        id: id,
        pageIndex1Based: pageIndex1Based,
        boxNorm: boxNorm,
        lines: lines,
        fontSizePt: fontSizePt,
        color: color,
        bold: bold,
        align: align,
        coverNorm: coverNorm,
        coverRects: coverRects,
        coverColor: coverColor,
        italic: italic,
        family: family,
        lineHeightEm: lineHeightEm,
        customFamily: customFamily,
      ),
    );
    notifyListeners();
    return id;
  }

  void removePendingText(int id) {
    final before = _pendingTexts.length;
    _pendingTexts.removeWhere((t) => t.id == id);
    if (_pendingTexts.length != before) notifyListeners();
  }

  void requestApply() {
    _applyRequestId++;
    notifyListeners();
  }

  void requestDelete() {
    _deleteRequestId++;
    notifyListeners();
  }

  void setAwaitingClickPlacement(bool value) {
    if (_awaitingClickPlacement == value) return;
    _awaitingClickPlacement = value;
    notifyListeners();
  }

  void setInlineEditing(bool value) {
    if (_inlineEditing == value) return;
    _inlineEditing = value;
    notifyListeners();
  }

  void setKeepAspectRatio(bool value) {
    if (_keepAspectRatio == value) return;
    _keepAspectRatio = value;
    notifyListeners();
  }

  void setFontSizePt(double value) {
    final next = value.clamp(6.0, 96.0);
    if (_fontSizePt == next) return;
    _fontSizePt = next;
    notifyListeners();
  }

  void setTextBold(bool value) {
    if (_textBold == value) return;
    _textBold = value;
    notifyListeners();
  }

  void setTextAlign(LiveMarginAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    notifyListeners();
  }

  void setTextEditTarget(LiveTextEditTarget? target) {
    _textEditTarget = target;
    _selectedRun = null;
    if (target == null) _textLineHeight = 1.2;
    if (target != null) {
      _placement = clampPagePlacement(
        normRectToPlacement(target.normRect),
        minFraction: 0.005,
      );
      _labelText = target.originalText;
      _fontSizePt = target.fontSizePt.clamp(6.0, 96.0);
      _textLineHeight = target.leadingEm.clamp(1.0, 2.6);
      if (target.textColor != null) _markupColor = target.textColor!;
      final m = target.fontMatch;
      if (m != null) {
        // Font recognition: start from the font the text already uses.
        _textFamily = m.family;
        _textBold = m.bold;
        _textItalic = m.italic;
        _detectedFont = m.how == null || m.libraryFamily == null
            ? m.original
            : '${m.original} (${switch (m.how) {
                'metrics' => 'by glyph widths',
                'embedded' => 'from the embedded font',
                'class' => 'closest style',
                _ => 'by name',
              }})';
        _userFont =
            (m.libraryFamily == null
                ? null
                : FontLibrary.instance.loadedLibrary(
                    m.libraryFamily!,
                    bold: m.bold,
                    italic: m.italic,
                  )) ??
            FontLibrary.instance.matchOriginal(m.original);
      } else {
        _detectedFont = null;
        _userFont = null;
      }
      _awaitingClickPlacement = false;
      _inlineEditing = true;
    }
    _editBaseline = target == null ? null : textEditSignature;
    notifyListeners();
  }

  String? _editBaseline;

  /// Everything a commit would write for the open block, as one string.
  String get textEditSignature => [
    _labelText ?? '',
    _placement.left.toStringAsFixed(4),
    _placement.top.toStringAsFixed(4),
    _placement.width.toStringAsFixed(4),
    _fontSizePt.toStringAsFixed(2),
    _markupColor.toARGB32(),
    _textBold,
    _textItalic,
    _textFamily,
    _textAlign.name,
    _textLineHeight.toStringAsFixed(2),
    _userFont?.id ?? '',
  ].join('|');

  /// True when the open block was moved, restyled or retyped.
  bool get textEditChanged =>
      _textEditTarget == null || _editBaseline != textEditSignature;

  void setTextRunHits(List<LiveTextEditTarget> hits) {
    _textRunHits
      ..clear()
      ..addAll(hits);
    _textRunsByPage[_pageIndex1Based] = List.of(hits);
    notifyListeners();
  }

  /// Editable text blocks of any loaded page (not only the focused one).
  List<LiveTextEditTarget> textRunsForPage(int page1Based) =>
      _textRunsByPage[page1Based] ?? const [];

  bool hasTextRunsForPage(int page1Based) =>
      _textRunsByPage.containsKey(page1Based);

  void setTextRunsForPage(int page1Based, List<LiveTextEditTarget> hits) {
    _textRunsByPage[page1Based] = List.of(hits);
    if (page1Based == _pageIndex1Based) {
      _textRunHits
        ..clear()
        ..addAll(hits);
    }
    notifyListeners();
  }

  void clearTextRuns() {
    _textRunsByPage.clear();
    _textRunHits.clear();
    notifyListeners();
  }

  void clearTextEditTarget() {
    if (_textEditTarget == null) return;
    _textEditTarget = null;
    notifyListeners();
  }

  void setSearchHighlightRects(List<Rect> rects) {
    _searchHighlightRectsNorm
      ..clear()
      ..addAll(rects.map(clampNormRect));
    notifyListeners();
  }

  void clearSearchHighlights() {
    if (_searchHighlightRectsNorm.isEmpty) return;
    _searchHighlightRectsNorm.clear();
    notifyListeners();
  }

  void setRedactRects(List<Rect> rects) {
    _redactRectsNorm
      ..clear()
      ..addAll(rects.map(clampNormRect));
    if (_redactRectsNorm.isEmpty) {
      _dragRectNorm = null;
      _activeRedactIndex = 0;
    } else {
      _activeRedactIndex = _activeRedactIndex.clamp(
        0,
        _redactRectsNorm.length - 1,
      );
      _dragRectNorm = _redactRectsNorm[_activeRedactIndex];
    }
    notifyListeners();
  }

  void addRedactRect(Rect rect) {
    _redactRectsNorm.add(clampNormRect(rect));
    _activeRedactIndex = _redactRectsNorm.length - 1;
    _dragRectNorm = _redactRectsNorm[_activeRedactIndex];
    notifyListeners();
  }

  void setActiveRedactIndex(int index) {
    if (_redactRectsNorm.isEmpty) return;
    _activeRedactIndex = index.clamp(0, _redactRectsNorm.length - 1);
    _dragRectNorm = _redactRectsNorm[_activeRedactIndex];
    notifyListeners();
  }

  void removeActiveRedactRect() {
    if (_redactRectsNorm.isEmpty) return;
    _redactRectsNorm.removeAt(_activeRedactIndex);
    if (_redactRectsNorm.isEmpty) {
      _dragRectNorm = null;
      _activeRedactIndex = 0;
    } else {
      _activeRedactIndex = _activeRedactIndex.clamp(
        0,
        _redactRectsNorm.length - 1,
      );
      _dragRectNorm = _redactRectsNorm[_activeRedactIndex];
    }
    notifyListeners();
  }

  void setImageBytes(Uint8List? bytes, {String? name}) {
    _imageBytes = bytes;
    if (name != null) _labelText = name;
    if (bytes != null) _awaitingClickPlacement = false;
    notifyListeners();
  }

  /// [draft]: a keystroke in the on-page editor — only that page repaints
  /// (panels and other pages do not rebuild per key).
  void setLabelText(String? text, {bool draft = false}) {
    if (_labelText == text) return;
    _labelText = text;
    if (draft) {
      _notifyDraft();
    } else {
      notifyListeners();
    }
  }

  void setMarkupColor(Color color) {
    _markupColor = color;
    notifyListeners();
  }

  void setOpacity(double opacity) {
    _opacity = opacity.clamp(0.05, 1.0);
    notifyListeners();
  }

  void setRotationDegrees(double degrees, {bool draft = false}) {
    var next = degrees % 360;
    if (next > 180) next -= 360;
    if (next <= -180) next += 360;
    if (_rotationDegrees == next) return;
    _rotationDegrees = next;
    if (draft) {
      _notifyDraft();
    } else {
      notifyListeners();
    }
  }

  /// Snap-rotate the placed image by 90° clockwise (screen / Acrobat style).
  void rotatePlacementBy90Clockwise() {
    setRotationDegrees(_rotationDegrees + 90);
  }

  void setLastPointerNorm(Offset? norm) {
    _lastPointerNorm = norm;
  }

  /// Watermark preview drawn on every in-scope page (not just [pageIndex1Based]).
  void setWatermarkPreview(WatermarkPreviewState? preview) {
    watermarkPreviewNotifier.value = preview;
  }

  /// Header/footer (and page-number) preview drawn on every in-scope page.
  void setHeaderFooterPagePreview(HeaderFooterPreviewState? preview) {
    headerFooterPreviewNotifier.value = preview;
  }

  void setWatermarkTiled(bool tiled) {
    if (_watermarkTiled == tiled) return;
    _watermarkTiled = tiled;
    notifyListeners();
  }

  void setHeaderFooterPreview({
    String? header,
    String? footer,
    LiveMarginAlign? align,
  }) {
    var changed = false;
    if (header != null && header != _headerText) {
      _headerText = header;
      changed = true;
    }
    if (footer != null && footer != _footerText) {
      _footerText = footer;
      changed = true;
    }
    if (align != null && align != _bandAlign) {
      _bandAlign = align;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void setPageNumberPreview({
    LiveMarginVertical? vertical,
    LiveMarginAlign? align,
    LivePageNumberFormat? format,
    int? visiblePage,
    int? totalPages,
  }) {
    var changed = false;
    if (vertical != null && vertical != _pageNumberVertical) {
      _pageNumberVertical = vertical;
      changed = true;
    }
    if (align != null && align != _pageNumberAlign) {
      _pageNumberAlign = align;
      changed = true;
    }
    if (format != null && format != _pageNumberFormat) {
      _pageNumberFormat = format;
      changed = true;
    }
    if (visiblePage != null && visiblePage != _pageNumberVisible) {
      _pageNumberVisible = math.max(1, visiblePage);
      changed = true;
    }
    if (totalPages != null && totalPages != _pageNumberTotal) {
      _pageNumberTotal = math.max(1, totalPages);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  String get pageNumberPreviewLabel {
    final n = _pageNumberVisible;
    final m = _pageNumberTotal;
    return switch (_pageNumberFormat) {
      LivePageNumberFormat.pageN => 'Page $n',
      LivePageNumberFormat.nOfM => '$n of $m',
    };
  }

  void setDrawTool(LiveDrawTool tool) {
    if (_drawTool == tool) return;
    _drawTool = tool;
    if (tool == LiveDrawTool.highlighter && _strokeWidthPt < 8) {
      _strokeWidthPt = 14;
    } else if (tool != LiveDrawTool.highlighter && _strokeWidthPt > 8) {
      _strokeWidthPt = 2.5;
    }
    notifyListeners();
  }

  void setStrokeWidthPt(double width) {
    final next = width.clamp(0.5, 36.0);
    if (_strokeWidthPt == next) return;
    _strokeWidthPt = next;
    notifyListeners();
  }

  void setMarkupKind(LiveMarkupKind kind) {
    if (_markupKind == kind) return;
    _markupKind = kind;
    notifyListeners();
  }

  void setCropMode(LiveCropMode mode) {
    if (_cropMode == mode) return;
    _cropMode = mode;
    if (mode == LiveCropMode.quad && _cropQuadNorm == null) {
      _cropQuadNorm = PageCropQuadNorm.fromRect(
        _dragRectNorm ?? const Rect.fromLTRB(0.08, 0.08, 0.92, 0.92),
      );
    }
    if (mode == LiveCropMode.rectangle && _dragRectNorm == null) {
      _dragRectNorm =
          _cropQuadNorm?.boundingRect ??
          const Rect.fromLTRB(0.08, 0.08, 0.92, 0.92);
    }
    notifyListeners();
  }

  /// Sets optional fixed physical aspect for rectangle crop (`null` = free).
  void setCropAspectPhysical(double? widthOverHeight) {
    if (_cropAspectPhysical == widthOverHeight) return;
    _cropAspectPhysical = widthOverHeight;
    final aspectNorm = cropAspectNorm;
    final rect = _dragRectNorm;
    if (aspectNorm != null &&
        rect != null &&
        _cropMode == LiveCropMode.rectangle) {
      final shaped = applyNormAspectRatio(
        rect,
        aspectWidthOverHeight: aspectNorm,
      );
      _dragRectNorm = shaped;
      _cropQuadNorm = PageCropQuadNorm.fromRect(shaped);
    }
    notifyListeners();
  }

  void setCropQuadNorm(PageCropQuadNorm quad) {
    final clamped = clampPageCropQuad(quad);
    _cropQuadNorm = clamped;
    _dragRectNorm = clamped.boundingRect;
    notifyListeners();
  }

  void beginInkStroke(Offset norm) {
    _currentInkStroke = [norm];
    notifyListeners();
  }

  void appendInkStroke(Offset norm) {
    final cur = _currentInkStroke;
    if (cur == null) return;
    cur.add(norm);
    _notifyDraft();
  }

  void endInkStroke({bool queueCommit = false}) {
    final cur = _currentInkStroke;
    if (cur != null && cur.isNotEmpty) {
      // A click without movement still leaves a dot.
      final raw = cur.length == 1 ? [cur.first, cur.first] : cur;
      final pts = smoothInkPolyline(raw);
      _inkStrokesNorm.add(pts);
      if (queueCommit) {
        _queueDrawCommit(pts);
      }
    }
    _currentInkStroke = null;
    notifyListeners();
  }

  /// Drops the in-progress stroke/shape without writing. Returns true if cancelled.
  bool cancelCurrentStroke() {
    if (_currentInkStroke == null) return false;
    _currentInkStroke = null;
    notifyListeners();
    return true;
  }

  /// One-click rubber stamp centered on [normCenter] (not a text caret).
  void placeStampAtNorm(Offset normCenter) {
    final pw = math.max(pageWidthPt, 1.0);
    final ph = math.max(pageHeightPt, 1.0);
    final w = (150.0 / pw).clamp(0.05, 0.9);
    final h = (40.0 / ph).clamp(0.02, 0.5);
    final left = (normCenter.dx - w / 2).clamp(0.0, 1.0 - w);
    final top = (normCenter.dy - h / 2).clamp(0.0, 1.0 - h);
    final a = Offset(left, top);
    final b = Offset(left + w, top + h);
    final pts = [
      Offset(a.dx, a.dy),
      Offset(b.dx, a.dy),
      Offset(b.dx, b.dy),
      Offset(a.dx, b.dy),
      Offset(a.dx, a.dy),
    ];
    _drawTool = LiveDrawTool.stamp;
    _inkStrokesNorm.add(pts);
    _queueDrawCommit(pts);
    _currentInkStroke = null;
    notifyListeners();
  }

  void setShapeDraft(Offset startNorm, Offset endNorm) {
    final isNew = _currentInkStroke == null;
    _currentInkStroke = [startNorm, endNorm];
    if (isNew) {
      notifyListeners();
    } else {
      _notifyDraft();
    }
  }

  void commitShapeDraft({bool queueCommit = true}) {
    final cur = _currentInkStroke;
    if (cur == null || cur.length < 2) {
      _currentInkStroke = null;
      notifyListeners();
      return;
    }
    // Ignore accidental clicks: shapes need a visible extent.
    final a = cur.first;
    final b = cur.last;
    final tiny = (a.dx - b.dx).abs() < 0.004 && (a.dy - b.dy).abs() < 0.004;
    if (!tiny) {
      final expanded = expandShapePoints(_drawTool, a, b);
      if (expanded.length >= 2) {
        _inkStrokesNorm.add(expanded);
        if (queueCommit) _queueDrawCommit(expanded);
      }
    }
    _currentInkStroke = null;
    notifyListeners();
  }

  void _queueDrawCommit(List<Offset> points) {
    final tool = _drawTool;
    final commit = LiveDrawCommit(
      tool: tool,
      pointsNorm: points,
      color: tool == LiveDrawTool.highlighter
          ? _highlighterColor
          : _markupColor,
      strokeWidthPt: tool == LiveDrawTool.highlighter
          ? math.max(_strokeWidthPt, 8)
          : _strokeWidthPt,
      opacity: tool == LiveDrawTool.highlighter ? kLiveHighlightOpacity : 1.0,
      labelText: tool == LiveDrawTool.stamp
          ? (_labelText?.trim().isNotEmpty == true
                ? _labelText!.trim()
                : 'APPROVED')
          : null,
      pageIndex1Based: _pageIndex1Based,
      closed:
          tool == LiveDrawTool.rectangle ||
          tool == LiveDrawTool.ellipse ||
          tool == LiveDrawTool.callout,
    );
    _pendingDrawCommit = commit;
    _queuedDrawCommits.add(commit);
    _redoDrawCommits.clear();
    _drawCommitEpoch++;
  }

  Color get _highlighterColor => _markupColor.toARGB32() == 0xFFE4002B
      ? kLiveHighlightColor
      : _markupColor;

  /// Queues text-markup bands (highlight / underline / strike / note).
  void queueMarkup({
    required LiveMarkupKind kind,
    required List<Rect> rectsNorm,
    String? noteText,
  }) {
    if (rectsNorm.isEmpty) return;
    final (color, opacity) = switch (kind) {
      LiveMarkupKind.highlight => (kLiveHighlightColor, kLiveHighlightOpacity),
      LiveMarkupKind.underline => (kLiveUnderlineColor, 1.0),
      LiveMarkupKind.strikethrough => (kLiveStrikeColor, 1.0),
      LiveMarkupKind.note => (kLiveNoteFill, 1.0),
    };
    final commit = LiveDrawCommit(
      tool: LiveDrawTool.rectangle,
      pointsNorm: const [],
      color: color,
      strokeWidthPt: 1.2,
      opacity: opacity,
      labelText: noteText,
      pageIndex1Based: _pageIndex1Based,
      markupKind: kind,
      rectsNorm: List.unmodifiable(rectsNorm),
    );
    _pendingDrawCommit = commit;
    _queuedDrawCommits.add(commit);
    _redoDrawCommits.clear();
    _drawCommitEpoch++;
    notifyListeners();
  }

  /// Undo for marks not yet written into the PDF. Returns true if handled.
  bool undoPendingDraw() {
    if (_currentInkStroke != null) {
      _currentInkStroke = null;
      notifyListeners();
      return true;
    }
    for (var i = _queuedDrawCommits.length - 1; i >= 0; i--) {
      final c = _queuedDrawCommits[i];
      if (_burningDrawCommits.contains(c)) continue;
      _queuedDrawCommits.removeAt(i);
      _redoDrawCommits.add(c);
      if (_pendingDrawCommit == c) _pendingDrawCommit = null;
      notifyListeners();
      return true;
    }
    return false;
  }

  bool redoPendingDraw() {
    if (_redoDrawCommits.isEmpty) return false;
    final c = _redoDrawCommits.removeLast();
    _queuedDrawCommits.add(c);
    _pendingDrawCommit = c;
    _drawCommitEpoch++;
    notifyListeners();
    return true;
  }

  /// Marks commits as in flight so undo skips them while the writer runs.
  void markDrawCommitsBurning(Iterable<LiveDrawCommit> commits) {
    _burningDrawCommits.addAll(commits);
  }

  /// Drops commits that were written into the PDF (keeps newer strokes).
  void removeDrawCommits(Iterable<LiveDrawCommit> commits) {
    final set = commits.toSet();
    _queuedDrawCommits.removeWhere(set.contains);
    _burningDrawCommits.removeAll(set);
    if (_pendingDrawCommit != null && set.contains(_pendingDrawCommit)) {
      _pendingDrawCommit = null;
    }
    notifyListeners();
  }

  /// Releases an in-flight mark after a failed write so it can be retried.
  void unmarkDrawCommitsBurning(Iterable<LiveDrawCommit> commits) {
    _burningDrawCommits.removeAll(commits);
  }

  static List<Offset> expandShapePoints(LiveDrawTool tool, Offset a, Offset b) {
    switch (tool) {
      case LiveDrawTool.pen:
      case LiveDrawTool.highlighter:
        return [a, b];
      case LiveDrawTool.line:
        return [a, b];
      case LiveDrawTool.arrow:
        return _arrowPoints(a, b);
      case LiveDrawTool.rectangle:
      case LiveDrawTool.stamp:
        return [
          Offset(a.dx, a.dy),
          Offset(b.dx, a.dy),
          Offset(b.dx, b.dy),
          Offset(a.dx, b.dy),
          Offset(a.dx, a.dy),
        ];
      case LiveDrawTool.ellipse:
        return _ellipsePoints(a, b);
      case LiveDrawTool.callout:
        return _calloutPoints(a, b);
    }
  }

  static List<Offset> _calloutPoints(Offset a, Offset b) {
    final left = math.min(a.dx, b.dx);
    final right = math.max(a.dx, b.dx);
    final top = math.min(a.dy, b.dy);
    final bottom = math.max(a.dy, b.dy);
    final midX = (left + right) / 2;
    final tip = Offset(midX, (bottom + 0.06).clamp(0.0, 1.0));
    return [
      Offset(left, top),
      Offset(right, top),
      Offset(right, bottom),
      Offset(midX + 0.02, bottom),
      tip,
      Offset(midX - 0.02, bottom),
      Offset(left, bottom),
      Offset(left, top),
    ];
  }

  static List<Offset> _arrowPoints(Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = (dx * dx + dy * dy);
    if (len < 1e-10) return [a, b];
    final inv = 1.0 / math.sqrt(len);
    final ux = dx * inv;
    final uy = dy * inv;
    final nx = -uy;
    final ny = ux;
    final head = math.min(0.025, math.sqrt(len) * 0.4);
    final left = Offset(
      b.dx - ux * head + nx * head * 0.55,
      b.dy - uy * head + ny * head * 0.55,
    );
    final right = Offset(
      b.dx - ux * head - nx * head * 0.55,
      b.dy - uy * head - ny * head * 0.55,
    );
    return [a, b, left, b, right];
  }

  static List<Offset> _ellipsePoints(Offset a, Offset b) {
    final cx = (a.dx + b.dx) / 2;
    final cy = (a.dy + b.dy) / 2;
    final rx = ((b.dx - a.dx).abs() / 2).clamp(0.001, 1.0);
    final ry = ((b.dy - a.dy).abs() / 2).clamp(0.001, 1.0);
    const steps = 72;
    final pts = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * math.pi * 2;
      pts.add(Offset(cx + rx * math.cos(t), cy + ry * math.sin(t)));
    }
    return pts;
  }

  void clearPendingDrawCommit() {
    if (_pendingDrawCommit == null) return;
    _pendingDrawCommit = null;
    notifyListeners();
  }

  /// Takes queued commits for a single coalesced PDF write (autosave 6s).
  List<LiveDrawCommit> takeQueuedDrawCommits() {
    final out = List<LiveDrawCommit>.from(_queuedDrawCommits);
    _queuedDrawCommits.clear();
    _pendingDrawCommit = null;
    return out;
  }

  void clearInk() {
    _inkStrokesNorm.clear();
    _currentInkStroke = null;
    _pendingDrawCommit = null;
    _queuedDrawCommits.clear();
    _redoDrawCommits.clear();
    _burningDrawCommits.clear();
    notifyListeners();
  }

  void setDragRectNorm(Rect? rect, {Offset? origin, bool draft = false}) {
    final next = rect == null
        ? null
        : clampNormRect(
            rect,
            minFraction:
                _toolId == ViewerToolId.addLink ||
                    _toolId == ViewerToolId.markupBurn
                ? 0.0
                : kPagePlacementMinFraction,
          );
    _dragRectNorm = next;
    if (origin != null) _dragOriginNorm = origin;
    if (next != null && _cropMode == LiveCropMode.rectangle) {
      _cropQuadNorm = PageCropQuadNorm.fromRect(next);
    }
    if (_toolId == ViewerToolId.redact &&
        next != null &&
        _redactRectsNorm.isNotEmpty) {
      final i = _activeRedactIndex.clamp(0, _redactRectsNorm.length - 1);
      _redactRectsNorm[i] = next;
    }
    if (draft) {
      _notifyDraft();
    } else {
      notifyListeners();
    }
  }

  void clearDragRect() {
    _dragRectNorm = null;
    _dragOriginNorm = null;
    _selectedLinkIndex = null;
    notifyListeners();
  }

  void setLinkHits(int page1Based, List<LiveLinkHit> hits) {
    _linkHits
      ..clear()
      ..addAll(hits);
    _linkHitsPage = page1Based;
    if (_selectedLinkIndex != null && _selectedLinkIndex! >= hits.length) {
      _selectedLinkIndex = null;
    }
    notifyListeners();
  }

  /// Selects an existing link (its rect becomes the editable drag rect).
  void selectLink(int? index) {
    if (index == null || index < 0 || index >= _linkHits.length) {
      _selectedLinkIndex = null;
    } else {
      _selectedLinkIndex = index;
      _dragRectNorm = _linkHits[index].normRect;
      _dragOriginNorm = null;
    }
    notifyListeners();
  }

  final Map<int, List<Rect>> _textCharRectsByPage = {};

  /// Normalized top-left character boxes for [page1Based] (markup snapping).
  List<Rect>? textCharRectsFor(int page1Based) =>
      _textCharRectsByPage[page1Based];

  void setTextCharRects(int page1Based, List<Rect> rects) {
    _textCharRectsByPage[page1Based] = List.unmodifiable(rects);
    notifyListeners();
  }

  void clearTextCharRects() => _textCharRectsByPage.clear();

  void _resetFormDetection() {
    _formSpots = const [];
    _formValues.clear();
    _activeFormSpotId = null;
    _formSpotsLoaded = false;
    _formSpotsMessage = null;
    _formPagesScanned.clear();
    _formScanAccepted.clear();
    _formScanQueue.clear();
  }

  void setFormSpots(List<PdfFormSpot> spots, {String? emptyMessage}) {
    _formSpots = List.unmodifiable(_sortedFormSpots(spots));
    _formSpotsLoaded = true;
    _formSpotsMessage = spots.isEmpty
        ? (emptyMessage ?? noFillInBlanksOnPageMessage)
        : null;
    _formPagesScanned
      ..clear()
      ..addAll(spots.map((s) => s.pageIndex1Based));
    if (spots.isEmpty) _formPagesScanned.add(_pageIndex1Based);
    _formScanAccepted
      ..clear()
      ..addAll(_formPagesScanned);
    _formScanQueue.clear();
    _activeFormSpotId = null;
    notifyListeners();
  }

  /// Clears in-memory blanks so the open document can be scanned again.
  void beginFormDetection() {
    _resetFormDetection();
    notifyListeners();
  }

  /// Asks for a text-layer scan of one page. Already-seen pages are ignored.
  /// Notification is deferred so this is safe to call from a page overlay.
  void requestFormPageScan(int page1Based) {
    if (page1Based < 1 || _closed) return;
    if (!_formScanAccepted.add(page1Based)) return;
    _formScanQueue.add(page1Based);
    if (_formScanNotifyQueued) return;
    _formScanNotifyQueued = true;
    scheduleMicrotask(() {
      _formScanNotifyQueued = false;
      if (_closed) return;
      notifyListeners();
    });
  }

  /// Next page to scan, closest to [preferNear]. Removes it from the queue.
  int? takeNextFormScanPage(int preferNear) {
    if (_formScanQueue.isEmpty) return null;
    var bestI = 0;
    var bestD = (_formScanQueue[0] - preferNear).abs();
    for (var i = 1; i < _formScanQueue.length; i++) {
      final d = (_formScanQueue[i] - preferNear).abs();
      if (d < bestD ||
          (d == bestD && _formScanQueue[i] < _formScanQueue[bestI])) {
        bestI = i;
        bestD = d;
      }
    }
    return _formScanQueue.removeAt(bestI);
  }

  /// Merges real AcroForm widgets. Text blanks that sit on the same rect are
  /// dropped so the widget stays the field the user types into.
  void addAcroFormSpots(List<PdfFormSpot> spots) {
    final incoming = [
      for (final s in spots)
        if (s.kind != PdfFormSpotKind.signature) s,
    ];
    if (incoming.isEmpty) {
      notifyListeners();
      return;
    }
    for (final a in incoming) {
      for (final s in _formSpots) {
        final typed = _formValues[s.id];
        if (typed == null || typed.isEmpty) continue;
        if (!s.id.startsWith(textBlankSpotIdPrefix)) continue;
        if (s.pageIndex1Based != a.pageIndex1Based) continue;
        if (!formNormOverlap(a.normRect, s.normRect)) continue;
        _formValues.putIfAbsent(a.id, () => typed);
      }
    }
    final kept = <PdfFormSpot>[];
    for (final s in _formSpots) {
      final covered =
          s.id.startsWith(textBlankSpotIdPrefix) &&
          incoming.any(
            (a) =>
                a.pageIndex1Based == s.pageIndex1Based &&
                formNormOverlap(a.normRect, s.normRect),
          );
      if (covered) {
        _formValues.remove(s.id);
        continue;
      }
      kept.add(s);
    }
    final have = {for (final s in kept) s.id};
    for (final s in incoming) {
      if (have.add(s.id)) kept.add(s);
    }
    _formSpots = List.unmodifiable(_sortedFormSpots(kept));
    if (_activeFormSpotId != null &&
        !_formSpots.any((s) => s.id == _activeFormSpotId)) {
      _activeFormSpotId = null;
    }
    notifyListeners();
  }

  /// Publishes text-layer blanks for one page and marks that page checked.
  void setDetectedTextBlanks(int page1Based, List<PdfFormSpot> blanks) {
    _formPagesScanned.add(page1Based);
    _formScanAccepted.add(page1Based);
    _formScanQueue.remove(page1Based);
    final acro = [
      for (final s in _formSpots)
        if (s.pageIndex1Based == page1Based &&
            !s.id.startsWith(textBlankSpotIdPrefix))
          s,
    ];
    final others = [
      for (final s in _formSpots)
        if (s.pageIndex1Based != page1Based) s,
    ];
    final added = <PdfFormSpot>[
      for (final b in blanks)
        if (!acro.any((a) => formNormOverlap(a.normRect, b.normRect))) b,
    ];
    _formSpots = List.unmodifiable(
      _sortedFormSpots([...others, ...acro, ...added]),
    );
    _formSpotsLoaded = true;
    _formSpotsMessage = null;
    if (_activeFormSpotId != null &&
        !_formSpots.any((s) => s.id == _activeFormSpotId)) {
      _activeFormSpotId = null;
    }
    notifyListeners();
  }

  List<PdfFormSpot> _sortedFormSpots(List<PdfFormSpot> spots) {
    final copy = [...spots];
    copy.sort((a, b) {
      final p = a.pageIndex1Based.compareTo(b.pageIndex1Based);
      if (p != 0) return p;
      final t = a.normRect.top.compareTo(b.normRect.top);
      if (t != 0) return t;
      return a.normRect.left.compareTo(b.normRect.left);
    });
    return copy;
  }

  void focusFormSpot(String id) {
    _activeFormSpotId = id;
    _formFocusGeneration++;
    // Do not set _inlineEditing — that drives the free-text caret tool.
    for (final s in _formSpots) {
      if (s.id == id) {
        _placement = clampPagePlacement(
          normRectToPlacement(s.normRect),
          minFraction: 0.005,
        );
        break;
      }
    }
    notifyListeners();
  }

  /// Moves focus to the next (or previous) fillable spot — Acrobat Tab.
  void focusNextFormSpot({bool reverse = false}) {
    if (_formSpots.isEmpty) return;
    final fillable = [
      for (final s in _formSpots)
        if (s.kind != PdfFormSpotKind.signature) s,
    ];
    if (fillable.isEmpty) return;
    var idx = 0;
    if (_activeFormSpotId != null) {
      final cur = fillable.indexWhere((s) => s.id == _activeFormSpotId);
      if (cur >= 0) {
        idx = reverse
            ? (cur - 1 + fillable.length) % fillable.length
            : (cur + 1) % fillable.length;
      }
    } else if (reverse) {
      idx = fillable.length - 1;
    }
    focusFormSpot(fillable[idx].id);
  }

  void clearActiveFormSpot() {
    if (_activeFormSpotId == null) return;
    _activeFormSpotId = null;
    notifyListeners();
  }

  void setFormValue(String id, String value) {
    _formValues[id] = value;
    notifyListeners();
  }

  /// Drops spots whose values were flattened into the page (keeps focus on
  /// any other field the user is typing in).
  void removeFormSpots(Set<String> ids) {
    if (ids.isEmpty) return;
    _formSpots = List.unmodifiable([
      for (final s in _formSpots)
        if (!ids.contains(s.id)) s,
    ]);
    _formValues.removeWhere((k, _) => ids.contains(k));
    if (ids.contains(_activeFormSpotId)) _activeFormSpotId = null;
    notifyListeners();
  }

  void clearFormValues() {
    if (_formValues.isEmpty) return;
    _formValues.clear();
    notifyListeners();
  }

  void toggleCheckbox(String id) {
    final cur = _formValues[id];
    _formValues[id] = (cur == 'Yes' || cur == 'true' || cur == '1')
        ? 'Off'
        : 'Yes';
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    draftRevision.dispose();
    super.dispose();
  }
}
