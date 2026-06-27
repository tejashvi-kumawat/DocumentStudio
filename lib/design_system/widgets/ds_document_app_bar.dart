import 'package:flutter/material.dart';

/// Consistent top bar for document workspaces (viewer, organize, etc.).
class DsDocumentAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DsDocumentAppBar({
    super.key,
    required this.title,
    this.leading,
    this.bottom,
    this.actions,
  });

  final String title;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final List<Widget>? actions;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: leading,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      bottom: bottom,
      actions: actions,
      scrolledUnderElevation: 2,
    );
  }
}
