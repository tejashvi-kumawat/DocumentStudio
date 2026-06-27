import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/form_sign/digital_id_dialogs.dart';
import 'package:document_studio/features/form_sign/digital_id_list.dart';
import 'package:document_studio/features/form_sign/digital_sign_dialog.dart';
import 'package:document_studio/features/form_sign/sign_page_layers.dart';
import 'package:document_studio/features/form_sign/sign_placement_bridge.dart';
import 'package:document_studio/features/form_sign/sign_sheet.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_incremental_signer.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_signature_validator.dart';
import 'package:document_studio/infrastructure/pdf/signing/signing_credential_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _fmtTime(DateTime? t) {
  if (t == null) return 'unknown time';
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String verdictTitle(PdfSignatureVerdict v) => switch (v) {
      PdfSignatureVerdict.valid => 'Valid',
      PdfSignatureVerdict.identityUnknown => 'Valid · identity unknown',
      PdfSignatureVerdict.modified => 'Changed after signing',
      PdfSignatureVerdict.invalid => 'Invalid',
      PdfSignatureVerdict.unknown => 'Not verified',
    };

/// Digital tab: signature fields, draw-a-field, signature status, IDs.
class DigitalSignaturesView extends ConsumerWidget {
  const DigitalSignaturesView({
    super.key,
    required this.controller,
    required this.report,
    required this.loading,
    required this.onSignField,
    required this.onRefresh,
  });

  final SignPlacementController controller;
  final PdfSignatureReport? report;
  final bool loading;
  final ValueChanged<PdfSignatureFieldInfo> onSignField;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final unsigned = controller.fields.where((f) => !f.signed).toList();
        final sigs = report?.signatures ?? const <PdfSignatureStatus>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (report?.error != null && sigs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: DsSpacing.sm),
                child: Text(
                  report!.error!,
                  style: theme.textTheme.bodySmall?.copyWith(color: DsColors.error),
                ),
              ),
            if (sigs.isNotEmpty) ...[
              SignSectionLabel(
                'Signatures in this document',
                trailing: IconButton(
                  tooltip: 'Re-verify',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              _SummaryBanner(report: report!),
              const SizedBox(height: DsSpacing.sm),
              for (var i = 0; i < sigs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: DsSpacing.sm),
                  child: DsMotion.fadeRiseIn(
                    duration: DsMotion.contentReveal + DsMotion.staggerStep * i,
                    child: SignatureStatusCard(
                      status: sigs[i],
                      onShow: sigs[i].page1Based > 0 && sigs[i].normRect != null
                          ? () => controller.showField(
                                sigs[i].page1Based,
                                _rectOf(sigs[i].normRect!),
                              )
                          : null,
                    ),
                  ),
                ),
            ],
            SignSectionLabel(
              unsigned.isEmpty ? 'Signature fields' : 'Fields to sign (${unsigned.length})',
            ),
            if (unsigned.isEmpty)
              Text(
                controller.fields.isEmpty
                    ? 'This document has no signature fields. Draw one where '
                        'the signature should appear.'
                    : 'All signature fields are signed.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DsColors.textSecondary(theme.brightness),
                ),
              )
            else
              for (final f in unsigned)
                _FieldRow(
                  field: f,
                  onSign: () => onSignField(f),
                  onShow: () => controller.showField(
                    f.pageIndex1Based,
                    signFieldRect(f),
                  ),
                ),
            const SizedBox(height: DsSpacing.sm),
            _DrawFieldButton(controller: controller),
            const SignSectionLabel('Digital IDs'),
            const _DigitalIdManager(),
            const SizedBox(height: DsSpacing.lg),
          ],
        );
      },
    );
  }
}

Rect _rectOf(List<double> r) => Rect.fromLTRB(r[0], r[1], r[2], r[3]);

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.report});

  final PdfSignatureReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sigs = report.signatures;
    final PdfSignatureVerdict worst = sigs
        .map((s) => s.verdict)
        .reduce((a, b) => _rank(a) >= _rank(b) ? a : b);
    final color = signVerdictColor(worst);
    final text = switch (worst) {
      PdfSignatureVerdict.valid => sigs.length == 1
          ? 'Signed and all signatures are valid.'
          : 'Signed and all ${sigs.length} signatures are valid.',
      PdfSignatureVerdict.identityUnknown =>
        'Signatures are intact, but at least one signer’s identity is not '
            'confirmed by a trusted certificate authority.',
      PdfSignatureVerdict.modified =>
        'The document was changed after at least one signature was applied.',
      PdfSignatureVerdict.invalid =>
        'At least one signature is invalid — the signed content was altered '
            'or the signature is broken.',
      PdfSignatureVerdict.unknown =>
        'At least one signature could not be verified.',
    };
    return AnimatedContainer(
      duration: DsMotion.switchDuration,
      padding: const EdgeInsets.all(DsSpacing.sm + 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(signVerdictIcon(worst), color: color, size: 22),
          const SizedBox(width: DsSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }

  static int _rank(PdfSignatureVerdict v) => switch (v) {
        PdfSignatureVerdict.valid => 0,
        PdfSignatureVerdict.identityUnknown => 1,
        PdfSignatureVerdict.unknown => 2,
        PdfSignatureVerdict.modified => 3,
        PdfSignatureVerdict.invalid => 4,
      };
}

/// One signature's verification result with expandable details.
class SignatureStatusCard extends StatefulWidget {
  const SignatureStatusCard({
    super.key,
    required this.status,
    this.onShow,
    this.initiallyExpanded = false,
  });

  final PdfSignatureStatus status;
  final VoidCallback? onShow;
  final bool initiallyExpanded;

  @override
  State<SignatureStatusCard> createState() => _SignatureStatusCardState();
}

class _SignatureStatusCardState extends State<SignatureStatusCard> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.status;
    final color = signVerdictColor(s.verdict);
    final secondary = DsColors.textSecondary(theme.brightness);
    final cert = s.certificate;
    return Container(
      decoration: DsSpacing.groupedInsetDecoration(
        isDark: theme.brightness == Brightness.dark,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(signVerdictIcon(s.verdict), color: color, size: 18),
                    ),
                    const SizedBox(width: DsSpacing.sm + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.signerName ?? cert?.commonName ?? 'Unknown signer',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${verdictTitle(s.verdict)} · ${_fmtTime(s.signingTime)}',
                            style: theme.textTheme.bodySmall?.copyWith(color: color),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (widget.onShow != null)
                      IconButton(
                        tooltip: 'Show field',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: widget.onShow,
                        icon: const Icon(Icons.center_focus_strong_outlined),
                      ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: DsMotion.switchDuration,
                      child: Icon(Icons.expand_more_rounded, color: secondary),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: DsMotion.switchDuration,
              curve: DsMotion.switchCurve,
              alignment: Alignment.topCenter,
              child: !_open
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(s.summary, style: theme.textTheme.bodySmall),
                          const SizedBox(height: DsSpacing.sm),
                          _kv(theme, 'Field', s.fieldName),
                          if (s.reason != null) _kv(theme, 'Reason', s.reason!),
                          if (s.location != null) _kv(theme, 'Location', s.location!),
                          _kv(
                            theme,
                            'Integrity',
                            s.intact
                                ? (s.coversWholeDocument
                                    ? 'Intact — covers the whole document'
                                    : s.signedAgainOnly
                                        ? 'Intact — later changes are signatures only'
                                        : 'Intact — document changed afterwards')
                                : 'Signed content does not match',
                          ),
                          _kv(
                            theme,
                            'Identity',
                            switch (s.trust) {
                              PdfSignatureTrust.trusted => 'Trusted certificate',
                              PdfSignatureTrust.selfSigned =>
                                'Self-signed — not issued by a trusted authority',
                              PdfSignatureTrust.unknown =>
                                'Issuer not in the trusted list',
                            },
                          ),
                          if (cert != null) ...[
                            _kv(theme, 'Issued by', cert.issuerCommonName),
                            if (cert.email != null) _kv(theme, 'Email', cert.email!),
                            if (cert.organization != null)
                              _kv(theme, 'Organization', cert.organization!),
                            _kv(
                              theme,
                              'Valid',
                              '${_fmtTime(cert.notBefore)} → ${_fmtTime(cert.notAfter)}',
                            ),
                            _kv(theme, 'Serial', cert.serial),
                          ],
                          if (s.subFilter != null) _kv(theme, 'Format', s.subFilter!),
                          if (s.timestamped) _kv(theme, 'Timestamp', 'Embedded (RFC 3161)'),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              k,
              style: theme.textTheme.bodySmall?.copyWith(
                color: DsColors.textSecondary(theme.brightness),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(v, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.onSign,
    required this.onShow,
  });

  final PdfSignatureFieldInfo field;
  final VoidCallback onSign;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = signIsPhoneWidth(context);
    const orange = Color(0xFFE0561B);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.name,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          field.visible
              ? 'Page ${field.pageIndex1Based}'
              : 'Page ${field.pageIndex1Based} · invisible field',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: DsColors.textSecondary(theme.brightness),
          ),
        ),
      ],
    );
    final signButton = FilledButton(
      onPressed: onSign,
      style: FilledButton.styleFrom(
        backgroundColor: DsColors.primary,
        foregroundColor: DsColors.onPrimary,
        minimumSize: Size(
          phone ? double.infinity : 0,
          phone ? DsSpacing.controlHeightComfortable : 36,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: phone ? VisualDensity.standard : VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: const Text('Sign'),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.sm),
      child: Container(
        decoration: DsSpacing.groupedInsetDecoration(
          isDark: theme.brightness == Brightness.dark,
        ),
        padding: EdgeInsets.fromLTRB(
          DsSpacing.md,
          DsSpacing.sm,
          phone ? DsSpacing.md : 6,
          phone ? DsSpacing.md : 6,
        ),
        child: phone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.draw_outlined, color: orange, size: 18),
                      const SizedBox(width: DsSpacing.sm),
                      Expanded(child: title),
                      IconButton(
                        tooltip: 'Show field',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: onShow,
                        icon: const Icon(Icons.center_focus_strong_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: DsSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    height: DsSpacing.controlHeightComfortable,
                    child: signButton,
                  ),
                ],
              )
            : Row(
                children: [
                  const Icon(Icons.draw_outlined, color: orange, size: 18),
                  const SizedBox(width: DsSpacing.sm),
                  Expanded(child: title),
                  IconButton(
                    tooltip: 'Show field',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: onShow,
                    icon: const Icon(Icons.center_focus_strong_outlined),
                  ),
                  signButton,
                ],
              ),
      ),
    );
  }
}

class _DrawFieldButton extends StatelessWidget {
  const _DrawFieldButton({required this.controller});

  final SignPlacementController controller;

  @override
  Widget build(BuildContext context) {
    final on = controller.drawFieldMode;
    final phone = signIsPhoneWidth(context);
    final button = on
        ? FilledButton.icon(
            key: const ValueKey('on'),
            onPressed: () => controller.setDrawFieldMode(false),
            style: FilledButton.styleFrom(
              minimumSize: Size(
                phone ? double.infinity : 0,
                DsSpacing.controlHeightComfortable,
              ),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(phone ? 'Cancel drawing' : 'Drag on the page… (Esc to cancel)'),
          )
        : OutlinedButton.icon(
            key: const ValueKey('off'),
            onPressed: () => controller.setDrawFieldMode(true),
            style: OutlinedButton.styleFrom(
              minimumSize: Size(
                phone ? double.infinity : 0,
                DsSpacing.controlHeightComfortable,
              ),
            ),
            icon: const Icon(Icons.crop_free_rounded, size: 18),
            label: const Text('Draw new signature field'),
          );
    return AnimatedSwitcher(
      duration: DsMotion.switchDuration,
      child: phone
          ? SizedBox(
              width: double.infinity,
              height: DsSpacing.controlHeightComfortable,
              child: button,
            )
          : button,
    );
  }
}

class _DigitalIdManager extends ConsumerStatefulWidget {
  const _DigitalIdManager();

  @override
  ConsumerState<_DigitalIdManager> createState() => _DigitalIdManagerState();
}

class _DigitalIdManagerState extends ConsumerState<_DigitalIdManager> {
  final _key = GlobalKey<DigitalIdListState>();

  SigningCredentialService get _service =>
      ref.read(signingCredentialServiceProvider);

  Future<String?> _pick(List<String> ext) async =>
      (await ref.read(fileStorageProvider).pickOpenFile(allowedExtensions: ext))
          ?.path;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DigitalIdList(
          key: _key,
          service: _service,
          compact: true,
          pickDriverPath: () => _pick(
            Platform.isWindows
                ? const ['dll']
                : Platform.isMacOS
                    ? const ['dylib', 'so']
                    : const ['so'],
          ),
          itemTrailing: (c) => c.id.startsWith('store:')
              ? IconButton(
                  tooltip: 'Remove from Document Studio',
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    await _service.store.remove(c.id.substring(6));
                    await _key.currentState?.refresh();
                  },
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: DsSpacing.sm),
        Wrap(
          spacing: DsSpacing.sm,
          runSpacing: DsSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final id = await importDigitalIdFlow(
                  context,
                  store: _service.store,
                  pickP12Path: () => _pick(const ['p12', 'pfx']),
                );
                if (id != null) await _key.currentState?.refresh();
              },
              icon: const Icon(Icons.file_open_outlined, size: 17),
              label: const Text('Import .p12'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final id = await showCreateDigitalIdDialog(
                  context,
                  store: _service.store,
                );
                if (id != null) await _key.currentState?.refresh();
              },
              icon: const Icon(Icons.add_moderator_outlined, size: 17),
              label: const Text('Create self-signed'),
            ),
          ],
        ),
      ],
    );
  }
}
