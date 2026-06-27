import 'dart:async';
import 'dart:io';

import 'package:document_studio/core/isolate/run_isolated.dart';

import 'package:document_studio/app/tree_unlock.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/form_sign/digital_sign_dialog.dart';
import 'package:document_studio/features/form_sign/digital_signatures_view.dart';
import 'package:document_studio/features/form_sign/sign_apply.dart';
import 'package:document_studio/features/form_sign/sign_panel_tab.dart';
import 'package:document_studio/features/form_sign/sign_placement_bridge.dart';
import 'package:document_studio/features/form_sign/sign_sheet.dart';
import 'package:document_studio/features/form_sign/signature_library_view.dart';
import 'package:document_studio/features/form_sign/stamp_library_view.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/infrastructure/pdf/saved_stamp_store.dart';
import 'package:document_studio/infrastructure/pdf/saved_visual_signature_store.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_incremental_signer.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_signature_validator.dart';
import 'package:document_studio/infrastructure/pdf/signing/x509.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fill & Sign side panel: signature / initials library, stamps, and
/// digital signatures. Items are dragged (or clicked) onto the live page,
/// adjusted there, and written into the PDF on Apply.
class ViewerVisualSignPanel extends ConsumerStatefulWidget {
  const ViewerVisualSignPanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerVisualSignPanel> createState() =>
      _ViewerVisualSignPanelState();
}

class _ViewerVisualSignPanelState extends ConsumerState<ViewerVisualSignPanel> {
  final _sigStore = SavedVisualSignatureStore();
  final _stampStore = SavedStampStore();
  late final SignPlacementController _c;
  SignPanelTab _tab = SignPanelTab.signatures;
  String _userName = '';
  PdfSignatureReport? _report;
  bool _loadingFields = false;
  bool _applying = false;
  DocumentSession? _session;
  DocumentTabsController? _tabs;
  (String, int)? _loadedFor;
  Timer? _reloadDebounce;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _c = ref.read(signPlacementControllerProvider);
    _c.onApply = _apply;
    _c.onFieldTap = _signField;
    _c.onSignedFieldTap = _showStatus;
    _c.onFieldDrawn = _signNewField;
    _c.addListener(_onController);
    final req = signPanelTabRequest.value;
    if (req != null) _tab = req;
    signPanelTabRequest.addListener(_onTabRequest);
    _stampStore.loadUserName().then((n) {
      if (mounted) setState(() => _userName = n);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final live = ref.read(viewerLiveToolSessionProvider);
      if (live.toolId != ViewerToolId.visualSign) {
        live.activate(
          ViewerToolId.visualSign,
          pageIndex1Based: widget.handoff.currentPage1,
        );
      }
      final tabs = ref.read(documentTabsControllerProvider);
      _tabs = tabs;
      tabs.addListener(_onTabs);
      _onTabs();
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    signPanelTabRequest.removeListener(_onTabRequest);
    _c.removeListener(_onController);
    _session?.removeListener(_onSessionChanged);
    _tabs?.removeListener(_onTabs);
    final c = _c;
    final apply = _apply;
    runWhenTreeUnlocked(() {
      // A replacement panel may already own the controller.
      if (c.onApply == apply) c.reset();
    });
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  void _onTabRequest() {
    final req = signPanelTabRequest.value;
    if (req == null || !mounted) return;
    setState(() => _tab = req);
    signPanelTabRequest.value = null;
  }

  void _onTabs() {
    final s = _tabs?.activeSession;
    if (!identical(s, _session)) {
      _session?.removeListener(_onSessionChanged);
      _session = s;
      s?.addListener(_onSessionChanged);
    }
    _onSessionChanged();
  }

  void _onSessionChanged() {
    final s = _session;
    if (s == null) return;
    final key = (s.file.path, s.revision);
    if (key == _loadedFor) return;
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 250), _loadFields);
  }

  Future<Set<String>> _trustedFingerprints() async {
    try {
      final ids = await ref
          .read(signingCredentialServiceProvider)
          .store
          .loadAll();
      return {
        for (final id in ids)
          if (id.certificateDer != null)
            X509Certificate.parse(id.certificateDer!).fingerprintSha256,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> _loadFields() async {
    final s = _session;
    if (s == null) return;
    final gen = ++_loadGen;
    _loadedFor = (s.file.path, s.revision);
    setState(() => _loadingFields = true);
    try {
      final bytes = await File(s.file.path).readAsBytes();
      final fields = await runIsolated(
        PdfIncrementalSigner.listSignatureFieldsSync,
        bytes,
      );
      final report = fields.any((f) => f.signed)
          ? await PdfSignatureValidator().validateBytes(
              bytes,
              trustedFingerprints: await _trustedFingerprints(),
            )
          : const PdfSignatureReport(signatures: []);
      if (!mounted || gen != _loadGen) return;
      _c.setFields(fields, report.signatures);
      setState(() {
        _report = report;
        _loadingFields = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      _c.setFields(const [], const []);
      setState(() {
        _report = PdfSignatureReport(
          signatures: const [],
          error: s.password != null
              ? 'Signature fields can’t be read while the PDF is encrypted.'
              : null,
        );
        _loadingFields = false;
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _apply() async {
    if (_applying || !_c.hasItems) return;
    setState(() => _applying = true);
    try {
      await applyPlacedSignItems(
        context: context,
        ref: ref,
        controller: _c,
        onMessage: _toast,
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Size _fieldSizePt(PdfSignatureFieldInfo f) => Size(f.widthPt, f.heightPt);

  Future<void> _signField(PdfSignatureFieldInfo f) async {
    if (!f.visible) {
      _toast(
        'This signature field is invisible; the signature will have no '
        'appearance on the page.',
      );
    }
    await _runDigital(PdfSignatureTarget.field(f), _fieldSizePt(f), f.name);
  }

  Future<void> _signNewField(int page, Rect rect) async {
    final pt = _c.pageSizePt(page) ?? const Size(612, 792);
    await _runDigital(
      PdfSignatureTarget.newField(
        page1Based: page,
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
      ),
      Size(rect.width * pt.width, rect.height * pt.height),
      '',
    );
  }

  Future<void> _runDigital(
    PdfSignatureTarget target,
    Size sizePt,
    String label,
  ) async {
    if (_c.hasItems) {
      _toast(
        'Apply or remove the placed items first — a digital signature '
        'must be the last change.',
      );
      return;
    }
    final sigs = await _sigStore.loadAll();
    if (!mounted) return;
    final result = await showDigitalSignFlow(
      context,
      target: target,
      fieldSizePt: sizePt,
      fieldLabel: label,
      signatures: [
        for (final s in sigs)
          if (!s.isInitials) s,
      ],
    );
    if (!mounted || result == null) return;
    if (result.savedCopyPath != null) {
      _toast('Signed copy saved to ${result.savedCopyPath}');
    } else {
      setState(() => _tab = SignPanelTab.digital);
      await _loadFields();
    }
  }

  void _showStatus(PdfSignatureStatus s) {
    showSignSheet<void>(
      context,
      builder: (ctx) => SignSheetScaffold(
        title: 'Signature status',
        icon: Icons.verified_outlined,
        body: SignatureStatusCard(status: s, initiallyExpanded: true),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).maybePop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storage = ref.read(fileStorageProvider);
    final phone = signIsPhoneWidth(context);
    final unsignedCount = _c.fields.where((f) => !f.signed).length;
    final pad = phone ? DsSpacing.pagePaddingCompact : DsSpacing.lg;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageLike = !constraints.maxHeight.isFinite ||
            constraints.maxHeight >= MediaQuery.sizeOf(context).height * 0.72;
        Widget panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, DsSpacing.sm, pad, 0),
          child: SignSegmented<SignPanelTab>(
            value: _tab,
            onChanged: (t) => setState(() => _tab = t),
            segments: [
              (SignPanelTab.signatures, 'Sign', Icons.gesture_rounded),
              (SignPanelTab.stamps, 'Stamps', Icons.approval_outlined),
              (
                SignPanelTab.digital,
                unsignedCount > 0 ? 'Digital · $unsignedCount' : 'Digital',
                Icons.verified_user_outlined,
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: DsMotion.switchDuration,
          curve: DsMotion.switchCurve,
          child: _c.armed != null || _c.drawFieldMode
              ? _ArmedBanner(controller: _c)
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: DsMotion.tabDuration,
            switchInCurve: DsMotion.switchCurve,
            transitionBuilder: (child, a) =>
                DsMotion.fadeRiseTransition(a, child),
            child: SingleChildScrollView(
              key: ValueKey(_tab),
              padding: EdgeInsets.fromLTRB(pad, 0, pad, DsSpacing.lg),
              child: switch (_tab) {
                SignPanelTab.signatures => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SignatureLibraryView(
                      controller: _c,
                      store: _sigStore,
                      storage: storage,
                      userName: _userName,
                      onMessage: _toast,
                    ),
                    if (unsignedCount > 0) ...[
                      const SizedBox(height: DsSpacing.md),
                      _DigitalNudge(
                        count: unsignedCount,
                        onTap: () =>
                            setState(() => _tab = SignPanelTab.digital),
                      ),
                    ],
                    const SizedBox(height: DsSpacing.md),
                    _HowTo(phone: phone),
                  ],
                ),
                SignPanelTab.stamps => StampLibraryView(
                  controller: _c,
                  storage: storage,
                  userName: _userName,
                  onUserNameChanged: (n) {
                    _userName = n;
                    _stampStore.saveUserName(n);
                  },
                  onMessage: _toast,
                ),
                SignPanelTab.digital => DigitalSignaturesView(
                  controller: _c,
                  report: _report,
                  loading: _loadingFields,
                  onSignField: _signField,
                  onRefresh: _loadFields,
                ),
              },
            ),
          ),
        ),
        AnimatedSize(
          duration: DsMotion.switchDuration,
          curve: DsMotion.switchCurve,
          child: _c.hasItems
              ? _ApplyBar(
                  count: _c.items.length,
                  busy: _applying,
                  onApply: _apply,
                  onClear: _c.clearItems,
                )
              : const SizedBox(width: double.infinity),
        ),
        Divider(height: 1, color: DsColors.border(theme.brightness)),
      ],
    );
        panel = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: phone ? double.infinity : viewerAcrobatOptionsWidth,
            ),
            child: panel,
          ),
        );
        if (phone && pageLike) {
          panel = SafeArea(child: panel);
        }
        return panel;
      },
    );
  }
}

class _ArmedBanner extends StatelessWidget {
  const _ArmedBanner({required this.controller});

  final SignPlacementController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final armed = controller.armed;
    final text = controller.drawFieldMode
        ? 'Drag on the page to draw the signature field'
        : 'Drag on the page to place “${armed?.label}”';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.md,
        DsSpacing.sm,
        DsSpacing.md,
        0,
      ),
      child: DsMotion.fadeRiseIn(
        duration: DsMotion.switchDuration,
        risePx: 4,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              if (armed != null)
                Container(
                  width: 44,
                  height: 26,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Image.memory(armed.png, fit: BoxFit.contain),
                )
              else
                Icon(Icons.crop_free_rounded, size: 20, color: accent),
              const SizedBox(width: DsSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => controller.drawFieldMode
                    ? controller.setDrawFieldMode(false)
                    : controller.arm(null),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplyBar extends StatelessWidget {
  const _ApplyBar({
    required this.count,
    required this.busy,
    required this.onApply,
    required this.onClear,
  });

  final int count;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = signIsPhoneWidth(context);
    final label = count == 1 ? '1 item placed' : '$count items placed';
    final applyButton = FilledButton.icon(
      onPressed: busy ? null : onApply,
      style: FilledButton.styleFrom(
        backgroundColor: DsColors.primary,
        foregroundColor: DsColors.onPrimary,
        minimumSize: Size(
          phone ? double.infinity : 0,
          DsSpacing.controlHeightComfortable,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check_rounded, size: 18),
      label: const Text('Apply'),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(
        phone ? DsSpacing.pagePaddingCompact : DsSpacing.lg,
        DsSpacing.sm,
        phone ? DsSpacing.pagePaddingCompact : DsSpacing.lg,
        DsSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: DsColors.border(theme.brightness)),
        ),
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: DsSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  height: DsSpacing.controlHeightComfortable,
                  child: applyButton,
                ),
                TextButton(
                  onPressed: busy ? null : onClear,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      double.infinity,
                      DsSpacing.controlHeightComfortable,
                    ),
                  ),
                  child: const Text('Remove all'),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : onClear,
                  child: const Text('Remove all'),
                ),
                const SizedBox(width: DsSpacing.xs),
                applyButton,
              ],
            ),
    );
  }
}

class _DigitalNudge extends StatelessWidget {
  const _DigitalNudge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const orange = Color(0xFFE0561B);
    return Material(
      color: orange.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
        child: Padding(
          padding: const EdgeInsets.all(DsSpacing.sm + 2),
          child: Row(
            children: [
              const Icon(Icons.draw_outlined, color: orange, size: 18),
              const SizedBox(width: DsSpacing.sm),
              Expanded(
                child: Text(
                  count == 1
                      ? 'This document has a signature field. Click it on the '
                            'page to sign with a digital ID.'
                      : 'This document has $count signature fields. Click one '
                            'on the page to sign with a digital ID.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowTo extends StatelessWidget {
  const _HowTo({required this.phone});

  final bool phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: DsColors.textSecondary(theme.brightness),
      height: 1.4,
    );
    return Text(
      phone
          ? 'Tap a card, then drag a box on the page — or long-press a card and '
                'drag it onto the page. Drag to move, use the handles to '
                'resize or rotate, then Apply.'
          : 'Drag a card onto the page, or click it and drag a box on the '
                'page. Move, resize and rotate with the handles · Delete '
                'removes · Enter applies · R rotates · Ctrl+D duplicates.',
      style: style,
    );
  }
}
