import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/material.dart';

/// Dense recent/favorite row — fixed 44px height with calm hover wash.
class HomeDocumentListTile extends StatefulWidget {
  const HomeDocumentListTile({
    super.key,
    required this.file,
    required this.leading,
    required this.onTap,
    this.trailing,
    this.showPath = true,
  });

  final LocalFileRef file;
  final Widget leading;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showPath;

  @override
  State<HomeDocumentListTile> createState() => _HomeDocumentListTileState();
}

class _HomeDocumentListTileState extends State<HomeDocumentListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    final wash = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : DsColors.primary.withValues(alpha: 0.04);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: DsMotion.hoverDuration,
        curve: DsMotion.switchCurve,
        height: DsSpacing.documentRowHeight,
        color: _hovered ? wash : Colors.transparent,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            splashColor: DsColors.primary.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DsSpacing.md),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: widget.leading,
                    ),
                  ),
                  const SizedBox(width: DsSpacing.sm),
                  Expanded(
                    child: widget.showPath
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.file.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                widget.file.path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  height: 1.15,
                                  color: secondary,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            widget.file.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
