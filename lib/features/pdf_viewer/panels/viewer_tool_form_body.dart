import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:flutter/material.dart';

/// Collapses engine dumps and stack traces into one short sentence.
String shortToolHelper(String? raw, {required String fallback}) {
  if (raw == null) return fallback;
  var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  text = text.replaceFirst(
    RegExp(
      r'^(Exception|StateError|Bad state|FormatException|Error):\s*',
      caseSensitive: false,
    ),
    '',
  );
  final lower = text.toLowerCase();
  final dump = text.contains('#') ||
      lower.contains('stacktrace') ||
      lower.contains('qpdf') ||
      lower.contains('[b]') ||
      lower.contains('soffice') ||
      lower.contains('engines/');
  if (text.isEmpty || dump || text.length > 160) return fallback;
  return text;
}

/// One-column tool body inside the Acrobat options rail.
///
/// Phone: 16dp padding and [SafeArea] when the form fills the sheet.
/// Desktop: at most [viewerAcrobatOptionsWidth], so the PDF keeps the rest.
class ViewerToolFormBody extends StatelessWidget {
  const ViewerToolFormBody({
    super.key,
    required this.child,
    this.scroll = true,
  });

  final Widget child;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = dsUseCompactToolLayout(context) ||
            (constraints.maxWidth.isFinite && constraints.maxWidth < 520);
        final height = constraints.maxHeight;
        final pageLike = !height.isFinite ||
            height >= MediaQuery.sizeOf(context).height * 0.72;
        final pad = DsSpacing.pagePaddingCompact;
        final maxW = compact ? double.infinity : viewerAcrobatOptionsWidth;

        Widget body = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: child,
            ),
          ),
        );
        if (scroll) {
          body = SingleChildScrollView(child: body);
        }
        if (compact && pageLike) {
          body = SafeArea(child: body);
        }
        return body;
      },
    );
  }
}

class ViewerToolPrimaryButton extends StatelessWidget {
  const ViewerToolPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.check,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final compact = dsUseCompactToolLayout(context);
    final button = FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: DsColors.primary,
        foregroundColor: DsColors.onPrimary,
        disabledBackgroundColor: DsColors.primary.withValues(alpha: 0.35),
        disabledForegroundColor: DsColors.onPrimary.withValues(alpha: 0.8),
        minimumSize: Size(
          compact ? double.infinity : 0,
          DsSpacing.controlHeightComfortable,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.lg),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (!compact) {
      return Align(alignment: Alignment.centerRight, child: button);
    }
    return SizedBox(
      width: double.infinity,
      height: DsSpacing.controlHeightComfortable,
      child: button,
    );
  }
}

class ViewerToolSecondaryButton extends StatelessWidget {
  const ViewerToolSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.open_in_new,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final compact = dsUseCompactToolLayout(context);
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(
          compact ? double.infinity : 0,
          DsSpacing.controlHeightComfortable,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.lg),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (!compact) return button;
    return SizedBox(
      width: double.infinity,
      height: DsSpacing.controlHeightComfortable,
      child: button,
    );
  }
}
