import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/form_sign/digital_id_dialogs.dart';
import 'package:document_studio/features/form_sign/digital_id_list.dart';
import 'package:document_studio/features/form_sign/sign_sheet.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/infrastructure/pdf/saved_visual_signature_store.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_cos.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_incremental_signer.dart';
import 'package:document_studio/infrastructure/pdf/signing/signing_credential.dart';
import 'package:document_studio/infrastructure/pdf/signing/signing_credential_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final signingCredentialServiceProvider =
    Provider<SigningCredentialService>((ref) => SigningCredentialService());

enum AppearanceGraphic { signature, name, none }

const kSignReasons = <String>[
  'I approve this document',
  'I am the author of this document',
  'I have reviewed this document',
  'I agree to the terms defined by this document',
  'I attest to the accuracy of this document',
];

String commonNameOf(String dn, {String fallback = ''}) {
  for (final part in dn.split(RegExp(r',(?=\s*[A-Za-z.0-9]+=)'))) {
    final eq = part.indexOf('=');
    if (eq > 0 && part.substring(0, eq).trim().toUpperCase() == 'CN') {
      return part.substring(eq + 1).trim();
    }
  }
  return fallback.isEmpty ? dn : fallback;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// `2026.09.29 14:05:31 +05'30'` — the Acrobat appearance date format.
String formatSignatureDate(DateTime t) {
  final off = t.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final m = off.inMinutes.abs();
  return '${t.year}.${_two(t.month)}.${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)} '
      "$sign${_two(m ~/ 60)}'${_two(m % 60)}'";
}

/// Renders the visible signature appearance at [pxPerPt] for a field of
/// [sizePt]. Graphic on the left (or top for tall fields), details beside it.
Future<Uint8List> composeSignatureAppearance({
  required Size sizePt,
  required AppearanceGraphic graphic,
  Uint8List? signaturePng,
  required String name,
  required List<String> lines,
  Color textColor = const Color(0xFF1F2937),
  double pxPerPt = 4,
}) async {
  final w = math.max(8.0, sizePt.width);
  final h = math.max(8.0, sizePt.height);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pxPerPt);
  final hasGraphic = graphic == AppearanceGraphic.name ||
      (graphic == AppearanceGraphic.signature && signaturePng != null);
  final wide = w / h >= 1.7;
  final pad = math.min(w, h) * 0.06;
  Rect gRect;
  Rect tRect;
  if (!hasGraphic) {
    gRect = Rect.zero;
    tRect = Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2);
  } else if (lines.isEmpty) {
    gRect = Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2);
    tRect = Rect.zero;
  } else if (wide) {
    final gw = (w - pad * 3) * 0.5;
    gRect = Rect.fromLTWH(pad, pad, gw, h - pad * 2);
    tRect = Rect.fromLTWH(pad * 2 + gw, pad, w - gw - pad * 3, h - pad * 2);
  } else {
    final gh = (h - pad * 3) * 0.52;
    gRect = Rect.fromLTWH(pad, pad, w - pad * 2, gh);
    tRect = Rect.fromLTWH(pad, pad * 2 + gh, w - pad * 2, h - gh - pad * 3);
  }

  if (graphic == AppearanceGraphic.signature && signaturePng != null) {
    final codec = await ui.instantiateImageCodec(signaturePng);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    final s = math.min(gRect.width / iw, gRect.height / ih);
    final dst = Rect.fromCenter(
      center: gRect.center,
      width: iw * s,
      height: ih * s,
    );
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, iw, ih),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    img.dispose();
    codec.dispose();
  } else if (graphic == AppearanceGraphic.name) {
    _paintFitted(
      canvas,
      [name],
      gRect,
      TextStyle(
        fontFamily: 'DS Sans',
        color: textColor,
        fontWeight: FontWeight.w700,
        height: 1.05,
      ),
      maxSize: gRect.height * 0.6,
      center: true,
    );
  }
  if (lines.isNotEmpty && tRect.width > 2 && tRect.height > 2) {
    _paintFitted(
      canvas,
      lines,
      tRect,
      TextStyle(fontFamily: 'DS Sans', color: textColor, height: 1.15),
      maxSize: 10,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (w * pxPerPt).round(),
    (h * pxPerPt).round(),
  );
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void _paintFitted(
  Canvas canvas,
  List<String> lines,
  Rect box,
  TextStyle style, {
  required double maxSize,
  bool center = false,
}) {
  var size = maxSize;
  TextPainter layout(double s) => TextPainter(
        text: TextSpan(text: lines.join('\n'), style: style.copyWith(fontSize: s)),
        textDirection: TextDirection.ltr,
        textAlign: center ? TextAlign.center : TextAlign.left,
      )..layout(maxWidth: box.width);
  var tp = layout(size);
  while ((tp.height > box.height || tp.width > box.width + 0.5 ||
          tp.computeLineMetrics().length > lines.length) &&
      size > 3) {
    tp.dispose();
    size *= 0.92;
    tp = layout(size);
  }
  final dy = box.top + (box.height - tp.height) / 2;
  final dx = center ? box.left + (box.width - tp.width) / 2 : box.left;
  tp.paint(canvas, Offset(dx, dy));
  tp.dispose();
}

/// Outcome of the digital signing flow.
class DigitalSignResult {
  const DigitalSignResult({required this.committed, this.savedCopyPath});
  final bool committed;
  final String? savedCopyPath;
}

/// Opens the "Sign with digital ID" sheet for [target].
Future<DigitalSignResult?> showDigitalSignFlow(
  BuildContext context, {
  required PdfSignatureTarget target,
  required Size fieldSizePt,
  required String fieldLabel,
  List<SavedSignature> signatures = const [],
}) {
  return showSignSheet<DigitalSignResult>(
    context,
    maxWidth: 820,
    dismissible: false,
    builder: (_) => _DigitalSignSheet(
      target: target,
      fieldSizePt: fieldSizePt,
      fieldLabel: fieldLabel,
      signatures: signatures,
    ),
  );
}

class _DigitalSignSheet extends ConsumerStatefulWidget {
  const _DigitalSignSheet({
    required this.target,
    required this.fieldSizePt,
    required this.fieldLabel,
    required this.signatures,
  });

  final PdfSignatureTarget target;
  final Size fieldSizePt;
  final String fieldLabel;
  final List<SavedSignature> signatures;

  @override
  ConsumerState<_DigitalSignSheet> createState() => _DigitalSignSheetState();
}

class _DigitalSignSheetState extends ConsumerState<_DigitalSignSheet> {
  static String _lastReason = kSignReasons.first;
  static String _lastLocation = '';
  static String? _lastCredentialId;

  final _listKey = GlobalKey<DigitalIdListState>();
  late final _reason = TextEditingController(text: _lastReason);
  late final _location = TextEditingController(text: _lastLocation);
  final _pin = TextEditingController();
  SigningCredential? _cred;
  int _step = 0;
  bool _rememberPin = true;
  bool _revealPin = false;
  late AppearanceGraphic _graphic = widget.signatures.isEmpty
      ? AppearanceGraphic.name
      : AppearanceGraphic.signature;
  late SavedSignature? _sig =
      widget.signatures.isEmpty ? null : widget.signatures.first;
  bool _showName = true;
  bool _showDate = true;
  bool _showReason = true;
  bool _showLocation = true;
  bool _showLabels = true;
  Uint8List? _preview;
  int _previewGen = 0;
  Timer? _previewDebounce;
  bool _busy = false;
  String? _error;
  final DateTime _openedAt = DateTime.now();

  SigningCredentialService get _service =>
      ref.read(signingCredentialServiceProvider);

  String get _signerName => _cred == null
      ? 'Your Name'
      : commonNameOf(_cred!.subjectDn, fallback: _cred!.displayName);

  @override
  void initState() {
    super.initState();
    _reason.addListener(_schedulePreview);
    _location.addListener(_schedulePreview);
    _schedulePreview();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _reason.dispose();
    _location.dispose();
    _pin.dispose();
    super.dispose();
  }

  List<String> _lines(DateTime when) {
    final l = <String>[];
    if (_showName) {
      l.add(_showLabels ? 'Digitally signed by $_signerName' : _signerName);
    }
    if (_showDate) {
      l.add(_showLabels
          ? 'Date: ${formatSignatureDate(when)}'
          : formatSignatureDate(when));
    }
    final reason = _reason.text.trim();
    if (_showReason && reason.isNotEmpty) {
      l.add(_showLabels ? 'Reason: $reason' : reason);
    }
    final loc = _location.text.trim();
    if (_showLocation && loc.isNotEmpty) {
      l.add(_showLabels ? 'Location: $loc' : loc);
    }
    return l;
  }

  Future<Uint8List> _compose(DateTime when, {double pxPerPt = 4}) {
    return composeSignatureAppearance(
      sizePt: widget.fieldSizePt,
      graphic: _graphic,
      signaturePng: _sig?.bytes,
      name: _signerName,
      lines: _lines(when),
      pxPerPt: pxPerPt,
    );
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 90), () async {
      final gen = ++_previewGen;
      final png = await _compose(_openedAt, pxPerPt: 3);
      if (!mounted || gen != _previewGen) return;
      setState(() => _preview = png);
    });
  }

  void _update(VoidCallback fn) {
    setState(fn);
    _schedulePreview();
  }

  Future<String?> _pickP12() async {
    final ref0 = await ref.read(fileStorageProvider).pickOpenFile(
      allowedExtensions: const ['p12', 'pfx'],
    );
    return ref0?.path;
  }

  Future<String?> _pickDriver() async {
    final ref0 = await ref.read(fileStorageProvider).pickOpenFile(
      allowedExtensions: Platform.isWindows
          ? const ['dll']
          : Platform.isMacOS
              ? const ['dylib', 'so']
              : const ['so'],
    );
    return ref0?.path;
  }

  Future<void> _import() async {
    final id = await importDigitalIdFlow(
      context,
      store: _service.store,
      pickP12Path: _pickP12,
    );
    if (id == null) return;
    await _listKey.currentState?.refresh();
    _selectById('store:${id.id}');
  }

  Future<void> _createSelfSigned() async {
    final id = await showCreateDigitalIdDialog(
      context,
      store: _service.store,
      suggestedName: _cred == null ? null : _signerName,
    );
    if (id == null) return;
    await _listKey.currentState?.refresh();
    _selectById('store:${id.id}');
  }

  void _selectById(String id) {
    final items = _listKey.currentState?.items ?? const <SigningCredential>[];
    for (final c in items) {
      if (c.id == id || c.id.endsWith(id.replaceFirst('store:', ''))) {
        _update(() => _adoptCredential(c));
        return;
      }
    }
  }

  String? _whyNot(SigningCredential c) {
    if (c.isExpired) return 'This digital ID has expired.';
    if (c.isNotYetValid) return 'This digital ID is not valid yet.';
    if (!c.canSignDocuments) {
      return 'This certificate is not allowed to sign documents.';
    }
    if (!c.hasPrivateKey && c.source != SigningCredentialSource.smartCard) {
      return 'No private key is available for this ID.';
    }
    return null;
  }

  bool get _needsSecret {
    final c = _cred;
    if (c == null || c.protectedAuthPath) return false;
    return c.requiresPin;
  }

  void _adoptCredential(SigningCredential c) {
    _cred = c;
    final saved = _service.sessionPin(c.id);
    _pin.text = saved ?? '';
    _error = _whyNot(c);
  }

  Future<void> _sign({required bool saveCopy}) async {
    final cred = _cred;
    if (cred == null) {
      setState(() => _error = 'Choose a digital ID to sign with.');
      return;
    }
    final why = _whyNot(cred);
    if (why != null) {
      setState(() => _error = why);
      return;
    }
    final typed = _pin.text;
    if (_needsSecret && typed.isEmpty) {
      setState(() => _error = cred.hardwareBacked
          ? 'Enter the token PIN.'
          : 'Enter the certificate store password.');
      return;
    }
    final String? pin = _needsSecret ? typed : _service.sessionPin(cred.id);
    if (_needsSecret && _rememberPin && pin != null && pin.isNotEmpty) {
      _service.rememberPin(cred.id, pin);
    }
    if (!mounted) return;
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    if (session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _lastReason = _reason.text.trim();
    _lastLocation = _location.text.trim();
    _lastCredentialId = cred.id;
    try {
      final now = DateTime.now();
      final appearance = await _compose(now);
      final input = await File(session.file.path).readAsBytes();
      final out = await _service.signPdf(
        input: input,
        credential: cred,
        target: widget.target,
        pin: pin,
        details: PdfSignDetails(
          signingTime: now,
          name: _signerName,
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          location: _location.text.trim().isEmpty ? null : _location.text.trim(),
          appearancePng: appearance,
        ),
      );
      if (!mounted) return;
      if (saveCopy) {
        final base = session.file.displayName.replaceAll(
          RegExp(r'\.pdf$', caseSensitive: false),
          '',
        );
        final path = await ref.read(fileStorageProvider).pickSavePath(
              suggestedName: '$base-signed.pdf',
              bytes: out,
              allowedExtensions: const ['pdf'],
              mimeType: 'application/pdf',
            );
        if (!mounted) return;
        if (path == null) {
          setState(() => _busy = false);
          return;
        }
        Navigator.of(context).pop(
          DigitalSignResult(committed: false, savedCopyPath: path),
        );
        return;
      }
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: tabs,
        session: session,
        bytes: out,
        successMessage: 'Signed by $_signerName.',
      );
      if (!mounted) return;
      Navigator.of(context).pop(const DigitalSignResult(committed: true));
    } on PdfEncryptedException {
      _fail('This PDF is password-encrypted. Remove the password (Protect → '
          'Remove security), then sign.');
    } catch (e) {
      final text = describeSignError(e);
      if (RegExp(r'pin|password|CKR_PIN', caseSensitive: false).hasMatch(text)) {
        _service.forgetPin(cred.id);
      }
      _fail(text);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ids = _idsColumn(theme);
    final appearance = _appearanceColumn(theme);
    return SignSheetScaffold(
      title: 'Sign with a digital ID',
      subtitle: widget.target.isNewField
          ? 'New signature field on page ${widget.target.page1Based}'
          : widget.fieldLabel.isEmpty
          ? 'Signature field'
          : 'Field “${widget.fieldLabel}”',
      icon: Icons.verified_user_outlined,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_step == 0)
            ids
          else ...[
            appearance,
            _secretField(theme),
          ],
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
        if (_step == 0) ...[
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _cred == null || _whyNot(_cred!) != null
                ? null
                : () => setState(() => _step = 1),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Continue'),
          ),
        ] else ...[
          TextButton(
            onPressed: _busy ? null : () => setState(() => _step = 0),
            child: const Text('Back'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || _cred == null ? null : () => _sign(saveCopy: true),
            icon: const Icon(Icons.save_as_outlined, size: 18),
            label: const Text('Sign & save copy…'),
          ),
          FilledButton.icon(
            onPressed: _busy || _cred == null ? null : () => _sign(saveCopy: false),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.draw_rounded, size: 18),
            label: const Text('Sign'),
          ),
        ],
      ],
    );
  }

  Widget _secretField(ThemeData theme) {
    if (!_needsSecret) return const SizedBox(width: double.infinity);
    final hw = _cred?.hardwareBacked ?? false;
    return Padding(
      padding: const EdgeInsets.only(top: DsSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pin,
            obscureText: !_revealPin,
            enabled: !_busy,
            decoration: InputDecoration(
              isDense: true,
              labelText: hw ? 'Token PIN' : 'Certificate store password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key_outlined, size: 18),
              suffixIcon: IconButton(
                tooltip: _revealPin ? 'Hide' : 'Show',
                onPressed: () => setState(() => _revealPin = !_revealPin),
                icon: Icon(
                  _revealPin
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _rememberPin,
            onChanged: _busy
                ? null
                : (v) => setState(() => _rememberPin = v ?? false),
            title: Text(
              'Remember password until the app closes',
              style: theme.textTheme.bodySmall,
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }

  Widget _idsColumn(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DigitalIdList(
          key: _listKey,
          service: _service,
          selectedId: _cred?.id,
          compact: true,
          enabled: !_busy,
          pickDriverPath: _pickDriver,
          onSelected: (c) => _update(() => _adoptCredential(c)),
        ),
        const SizedBox(height: DsSpacing.sm),
        Wrap(
          spacing: DsSpacing.sm,
          runSpacing: DsSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.file_open_outlined, size: 17),
              label: const Text('Import .p12 / .pfx'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _createSelfSigned,
              icon: const Icon(Icons.add_moderator_outlined, size: 17),
              label: const Text('Create self-signed ID'),
            ),
          ],
        ),
        if (!SigningCredentialService.supportsSystemStores) ...[
          const SizedBox(height: DsSpacing.sm),
          _InfoBanner(
            icon: Icons.usb_off_rounded,
            text: 'USB tokens, smart cards and system certificate stores are '
                'available in the desktop app. On this device, sign with an '
                'imported .p12 / .pfx or a self-signed ID.',
          ),
        ],
        _AutoSelect(
          listKey: _listKey,
          preferredId: _lastCredentialId,
          onPick: (c) => _update(() => _cred = c),
          enabled: _cred == null,
        ),
      ],
    );
  }

  Widget _appearanceColumn(ThemeData theme) {
    final aspect = widget.fieldSizePt.width / math.max(1, widget.fieldSizePt.height);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Appearance', style: theme.textTheme.labelLarge),
        const SizedBox(height: DsSpacing.sm),
        Container(
          padding: const EdgeInsets.all(DsSpacing.md),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
            border: Border.all(color: DsColors.border(theme.brightness)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: AspectRatio(
                aspectRatio: aspect.clamp(0.3, 8.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: AnimatedSwitcher(
                    duration: DsMotion.hoverDuration,
                    child: _preview == null
                        ? const SizedBox.expand()
                        : Image.memory(
                            _preview!,
                            key: ValueKey(_previewGen),
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: DsSpacing.md),
        SignSegmented<AppearanceGraphic>(
          value: _graphic,
          onChanged: (g) => _update(() => _graphic = g),
          segments: const [
            (AppearanceGraphic.signature, 'Signature', Icons.gesture_rounded),
            (AppearanceGraphic.name, 'Name', Icons.title_rounded),
            (AppearanceGraphic.none, 'Text only', Icons.notes_rounded),
          ],
        ),
        AnimatedSize(
          duration: DsMotion.switchDuration,
          curve: DsMotion.switchCurve,
          child: _graphic == AppearanceGraphic.signature
              ? Padding(
                  padding: const EdgeInsets.only(top: DsSpacing.sm),
                  child: widget.signatures.isEmpty
                      ? Text(
                          'No saved signatures yet — create one in the '
                          'Signatures tab, or use Name.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: DsColors.textSecondary(theme.brightness),
                          ),
                        )
                      : SizedBox(
                          height: 52,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.signatures.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: DsSpacing.sm),
                            itemBuilder: (context, i) {
                              final s = widget.signatures[i];
                              final sel = s.id == _sig?.id;
                              return InkWell(
                                onTap: () => _update(() => _sig = s),
                                borderRadius: BorderRadius.circular(8),
                                child: AnimatedContainer(
                                  duration: DsMotion.hoverDuration,
                                  width: 110,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F8FA),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: sel
                                          ? theme.colorScheme.primary
                                          : DsColors.border(theme.brightness),
                                      width: sel ? 1.8 : 1,
                                    ),
                                  ),
                                  child: Image.memory(s.bytes, fit: BoxFit.contain),
                                ),
                              );
                            },
                          ),
                        ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: DsSpacing.sm),
        TextField(
          controller: _reason,
          decoration: InputDecoration(
            isDense: true,
            labelText: 'Reason',
            border: const OutlineInputBorder(),
            suffixIcon: PopupMenuButton<String>(
              tooltip: 'Common reasons',
              icon: const Icon(Icons.expand_more_rounded, size: 20),
              onSelected: (r) => _reason.text = r,
              itemBuilder: (_) => [
                for (final r in kSignReasons)
                  PopupMenuItem(value: r, child: Text(r)),
              ],
            ),
          ),
        ),
        const SizedBox(height: DsSpacing.sm),
        TextField(
          controller: _location,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Location (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: DsSpacing.xs),
        Wrap(
          spacing: 6,
          runSpacing: 0,
          children: [
            _Toggle('Name', _showName, (v) => _update(() => _showName = v)),
            _Toggle('Date', _showDate, (v) => _update(() => _showDate = v)),
            _Toggle('Reason', _showReason, (v) => _update(() => _showReason = v)),
            _Toggle('Location', _showLocation,
                (v) => _update(() => _showLocation = v)),
            _Toggle('Labels', _showLabels, (v) => _update(() => _showLabels = v)),
          ],
        ),
      ],
    );
  }
}

/// Selects the last-used (or first usable) ID once the list has loaded.
class _AutoSelect extends StatefulWidget {
  const _AutoSelect({
    required this.listKey,
    required this.preferredId,
    required this.onPick,
    required this.enabled,
  });

  final GlobalKey<DigitalIdListState> listKey;
  final String? preferredId;
  final ValueChanged<SigningCredential> onPick;
  final bool enabled;

  @override
  State<_AutoSelect> createState() => _AutoSelectState();
}

class _AutoSelectState extends State<_AutoSelect> {
  Timer? _t;
  int _tries = 0;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 250), (_) => _check());
  }

  void _check() {
    if (!widget.enabled || ++_tries > 40) {
      _t?.cancel();
      return;
    }
    final items = widget.listKey.currentState?.items ?? const [];
    if (items.isEmpty) return;
    final usable = items.where((c) => c.isUsable && c.canSignDocuments).toList();
    if (usable.isEmpty) {
      _t?.cancel();
      return;
    }
    final pick = usable.firstWhere(
      (c) => c.id == widget.preferredId,
      orElse: () => usable.first,
    );
    _t?.cancel();
    widget.onPick(pick);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged);

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      visualDensity: VisualDensity.compact,
      labelStyle: const TextStyle(fontSize: 12),
      showCheckmark: true,
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(DsSpacing.sm + 2),
      decoration: BoxDecoration(
        color: DsColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
        border: Border.all(color: DsColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: DsColors.warning),
          const SizedBox(width: DsSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
