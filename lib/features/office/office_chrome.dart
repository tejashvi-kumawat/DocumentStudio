import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shared chrome of the Word and PowerPoint editors, in the Document Studio
/// theme and laid out like Google Docs / Slides: back + app icon + title
/// over a menu bar, one rounded toolbar, a side panel, and the page.

/// Accent of each app (brand red for documents, warm orange for slides).
const kDocsAccent = DsColors.primary;
const kSlidesAccent = Color(0xFFE8710A);

Color officeCanvas(Brightness b) =>
    b == Brightness.dark ? const Color(0xFF0B1220) : const Color(0xFFF1F3F6);
Color officeBar(Brightness b) =>
    b == Brightness.dark ? DsColors.surfaceDark : Colors.white;
Color officePill(Brightness b, Color accent) => b == Brightness.dark
    ? const Color(0xFF1E293B)
    : Color.alphaBlend(
        accent.withValues(alpha: 0.045),
        const Color(0xFFF4F6F9),
      );

/// Top bar: back button followed by the menus (File, Edit…). Nothing else:
/// the document's actions live in the toolbar below.
class OfficeTopBar extends StatelessWidget {
  const OfficeTopBar({
    super.key,
    required this.onBack,
    required this.menus,
    this.actions = const [],
  });

  final VoidCallback onBack;
  final List<Widget> menus;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      color: officeBar(b),
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.fromLTRB(6, 2, 10, 0),
      child: Row(
        children: [
          TbButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: onBack,
            size: 32,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: MenuBar(
                style: const MenuStyle(
                  backgroundColor: WidgetStatePropertyAll(Colors.transparent),
                  elevation: WidgetStatePropertyAll(0),
                  shadowColor: WidgetStatePropertyAll(Colors.transparent),
                  padding: WidgetStatePropertyAll(EdgeInsets.zero),
                ),
                children: menus,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A top-level menu (File, Edit…).
Widget officeMenu(String label, List<Widget> children) => SubmenuButton(
  style: const ButtonStyle(
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
    minimumSize: WidgetStatePropertyAll(Size(0, 28)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
  ),
  menuStyle: const MenuStyle(
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
  ),
  menuChildren: children,
  child: Text(label, style: const TextStyle(fontSize: 13.5)),
);

/// A menu command with optional icon and shortcut hint.
Widget officeItem(
  String label,
  VoidCallback? onTap, {
  IconData? icon,
  SingleActivator? shortcut,
  bool checked = false,
}) => MenuItemButton(
  onPressed: onTap,
  shortcut: shortcut,
  leadingIcon: SizedBox(
    width: 20,
    child: checked
        ? const Icon(Icons.check, size: 18)
        : (icon == null ? null : Icon(icon, size: 18)),
  ),
  style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(220, 34))),
  child: Text(label, style: const TextStyle(fontSize: 13.5)),
);

Widget officeSub(String label, List<Widget> children, {IconData? icon}) =>
    SubmenuButton(
      leadingIcon: SizedBox(
        width: 20,
        child: icon == null ? null : Icon(icon, size: 18),
      ),
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(220, 34)),
      ),
      menuChildren: children,
      child: Text(label, style: const TextStyle(fontSize: 13.5)),
    );

const officeMenuDivider = Divider(height: 9, indent: 8, endIndent: 8);

/// The single rounded toolbar under the menus. When its tools do not fit,
/// the mouse wheel scrolls it sideways and arrows appear at the clipped
/// edge.
class OfficeToolbar extends StatefulWidget {
  const OfficeToolbar({
    super.key,
    required this.accent,
    required this.children,
    this.trailing = const [],
  });
  final Color accent;
  final List<Widget> children;
  final List<Widget> trailing;

  @override
  State<OfficeToolbar> createState() => _OfficeToolbarState();
}

class _OfficeToolbarState extends State<OfficeToolbar> {
  final _scroll = ScrollController();
  bool _canLeft = false, _canRight = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(OfficeToolbar old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final l = p.pixels > 1, r = p.pixels < p.maxScrollExtent - 1;
    if (l != _canLeft || r != _canRight) {
      setState(() {
        _canLeft = l;
        _canRight = r;
      });
    }
  }

  void _by(double dx) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    _scroll.animateTo(
      (p.pixels + dx).clamp(0, p.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    Widget arrow(IconData icon, double dx) => TbButton(
      icon: icon,
      tooltip: dx < 0 ? 'More tools on the left' : 'More tools',
      size: 26,
      accent: widget.accent,
      onTap: () => _by(dx),
    );
    return Container(
      color: officeBar(b),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: officePill(b, widget.accent),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            if (_canLeft) arrow(Icons.chevron_left, -240),
            Expanded(
              child: Listener(
                // The vertical wheel scrolls the tools sideways.
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent && _scroll.hasClients) {
                    final p = _scroll.position;
                    _scroll.jumpTo(
                      (p.pixels + e.scrollDelta.dy + e.scrollDelta.dx).clamp(
                        0,
                        p.maxScrollExtent,
                      ),
                    );
                  }
                },
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (_) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _update(),
                    );
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: Row(children: widget.children),
                  ),
                ),
              ),
            ),
            if (_canRight) arrow(Icons.chevron_right, 240),
            ...widget.trailing,
          ],
        ),
      ),
    );
  }
}

class TbDivider extends StatelessWidget {
  const TbDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Theme.of(context).dividerColor.withValues(alpha: 0.8),
  );
}

/// Toolbar button with a soft hover/press fade and an "on" state.
class TbButton extends StatefulWidget {
  const TbButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.label,
    this.active = false,
    this.menu,
    this.size = 30,
    this.accent,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final String? label;
  final bool active;
  final List<Widget>? menu;
  final double size;
  final Color? accent;

  @override
  State<TbButton> createState() => _TbButtonState();
}

class _TbButtonState extends State<TbButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accent ?? kDocsAccent;
    Widget face(VoidCallback? tap) {
      final enabled = tap != null;
      final fg = !enabled
          ? theme.disabledColor
          : widget.active
          ? accent
          : theme.colorScheme.onSurface.withValues(alpha: 0.82);
      return Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 450),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            onTap: tap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              height: widget.size,
              constraints: BoxConstraints(minWidth: widget.size),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: EdgeInsets.symmetric(
                horizontal: widget.label == null && widget.menu == null ? 0 : 7,
              ),
              decoration: BoxDecoration(
                color: widget.active
                    ? accent.withValues(alpha: 0.13)
                    : (_hover && enabled
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.07)
                          : Colors.transparent),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 19, color: fg),
                  if (widget.label != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      widget.label!,
                      style: TextStyle(
                        fontSize: 13,
                        color: fg,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (widget.menu != null)
                    Icon(Icons.arrow_drop_down, size: 16, color: fg),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (widget.menu == null) return face(widget.onTap);
    return MenuAnchor(
      menuChildren: widget.menu!,
      builder: (context, c, _) => face(() => c.isOpen ? c.close() : c.open()),
    );
  }
}

/// Filled primary action in the toolbar (Save / Present).
class TbPrimary extends StatelessWidget {
  const TbPrimary({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
    this.tooltip,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? label,
    child: Padding(
      padding: const EdgeInsets.only(left: 4),
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        icon: Icon(icon, size: 17),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

/// Font name / size box: type a value or pick from the list.
class TbCombo extends StatefulWidget {
  const TbCombo({
    super.key,
    required this.value,
    required this.items,
    required this.onSelected,
    this.width = 120,
    this.tooltip,
    this.itemStyle,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onSelected;
  final double width;
  final String? tooltip;
  final TextStyle? Function(String item)? itemStyle;

  @override
  State<TbCombo> createState() => _TbComboState();
}

class _TbComboState extends State<TbCombo> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();
  bool _hover = false;

  @override
  void didUpdateWidget(TbCombo old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _text.text != widget.value)
      _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String v) {
    final t = v.trim();
    if (t.isNotEmpty) widget.onSelected(t);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: widget.tooltip ?? '',
      waitDuration: const Duration(milliseconds: 600),
      child: MenuAnchor(
        style: const MenuStyle(
          maximumSize: WidgetStatePropertyAll(Size(320, 440)),
        ),
        menuChildren: [
          for (final i in widget.items)
            MenuItemButton(
              onPressed: () => _submit(i),
              child: SizedBox(
                width: widget.width + 60,
                child: Text(
                  i,
                  overflow: TextOverflow.ellipsis,
                  style: (widget.itemStyle?.call(i) ?? const TextStyle())
                      .copyWith(
                        fontSize: 14,
                        fontWeight: i == widget.value ? FontWeight.w700 : null,
                      ),
                ),
              ),
            ),
        ],
        builder: (context, c, _) => MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.width,
            height: 30,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _hover
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: _submit,
                  ),
                ),
                GestureDetector(
                  onTap: () => c.isOpen ? c.close() : c.open(),
                  child: const SizedBox(
                    width: 20,
                    height: 30,
                    child: Icon(Icons.arrow_drop_down, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Theme palette: ten hues in six tints, then standard colours.
const kOfficeThemeColors = <int>[
  0xFFFFFFFF,
  0xFF000000,
  0xFFE7E6E6,
  0xFF44546A,
  0xFF4472C4,
  0xFFED7D31,
  0xFFA5A5A5,
  0xFFFFC000,
  0xFF5B9BD5,
  0xFF70AD47, //
  0xFFF2F2F2,
  0xFF7F7F7F,
  0xFFD0CECE,
  0xFFD6DCE4,
  0xFFD9E2F3,
  0xFFFBE5D5,
  0xFFEDEDED,
  0xFFFFF2CC,
  0xFFDEEBF6,
  0xFFE2EFD9, //
  0xFFD8D8D8,
  0xFF595959,
  0xFFAEABAB,
  0xFFADB9CA,
  0xFFB4C6E7,
  0xFFF7CBAC,
  0xFFDBDBDB,
  0xFFFEE599,
  0xFFBDD7EE,
  0xFFC5E0B3, //
  0xFFBFBFBF,
  0xFF3F3F3F,
  0xFF757070,
  0xFF8496B0,
  0xFF8EAADB,
  0xFFF4B183,
  0xFFC9C9C9,
  0xFFFFD965,
  0xFF9DC3E6,
  0xFFA8D08D, //
  0xFFA5A5A5,
  0xFF262626,
  0xFF3A3838,
  0xFF323F4F,
  0xFF2F5496,
  0xFFC55A11,
  0xFF7B7B7B,
  0xFFBF9000,
  0xFF2E75B5,
  0xFF538135, //
  0xFF7F7F7F,
  0xFF0C0C0C,
  0xFF171616,
  0xFF222A35,
  0xFF1F3864,
  0xFF833C0B,
  0xFF525252,
  0xFF7F6000,
  0xFF1E4E79,
  0xFF375623, //
];
const kOfficeStandardColors = <int>[
  0xFFC00000,
  0xFFFF0000,
  0xFFFFC000,
  0xFFFFFF00,
  0xFF92D050,
  0xFF00B050,
  0xFF00B0F0,
  0xFF0070C0,
  0xFF002060,
  0xFF7030A0,
];
const kHighlightColors = <int>[
  0xFFFFFF00,
  0xFF00FF00,
  0xFF00FFFF,
  0xFFFF00FF,
  0xFF0000FF,
  0xFFFF0000,
  0xFF000080,
  0xFF008080,
  0xFF008000,
  0xFF800080,
  0xFF800000,
  0xFF808000,
  0xFF808080,
  0xFFC0C0C0,
  0xFF000000,
];

/// Colour button: icon with the current colour under it; the arrow opens
/// the palette.
class TbColorButton extends StatefulWidget {
  const TbColorButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPicked,
    this.noneLabel = 'Automatic',
    this.highlight = false,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final ValueChanged<Color?> onPicked;
  final String noneLabel;
  final bool highlight;

  @override
  State<TbColorButton> createState() => _TbColorButtonState();
}

class _TbColorButtonState extends State<TbColorButton> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    Widget swatch(int c) => InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () {
        _menu.close();
        widget.onPicked(Color(c));
      },
      child: Container(
        width: 18,
        height: 18,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Color(c),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33000000), width: 0.6),
        ),
      ),
    );
    Widget grid(List<int> colors, int perRow) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < colors.length; i += perRow)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in colors.sublist(
                i,
                (i + perRow).clamp(0, colors.length),
              ))
                swatch(c),
            ],
          ),
      ],
    );
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () {
                  _menu.close();
                  widget.onPicked(null);
                },
                icon: const Icon(Icons.format_color_reset_outlined, size: 18),
                label: Text(widget.noneLabel),
              ),
              if (widget.highlight)
                grid(kHighlightColors, 5)
              else ...[
                grid(kOfficeThemeColors, 10),
                const SizedBox(height: 8),
                grid(kOfficeStandardColors, 10),
              ],
            ],
          ),
        ),
      ],
      builder: (context, c, _) => TbButton(
        icon: widget.icon,
        tooltip: widget.tooltip,
        onTap: () => c.isOpen ? c.close() : c.open(),
        label: null,
      ).withColorBar(widget.color),
    );
  }
}

extension on TbButton {
  Widget withColorBar(Color c) => Stack(
    alignment: Alignment.bottomCenter,
    children: [
      this,
      Positioned(
        bottom: 4,
        child: IgnorePointer(
          child: Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Left side panel with a header and close button.
class OfficeSidePanel extends StatelessWidget {
  const OfficeSidePanel({super.key, required this.child, this.width = 248});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: officeBar(b),
        border: Border(right: BorderSide(color: DsColors.border(b))),
      ),
      child: child,
    );
  }
}

/// A small label/value line in the side panel's document info.
class OfficeStat extends StatelessWidget {
  const OfficeStat(this.label, this.value, {super.key, this.icon});
  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = DsColors.textSecondary(theme.brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: muted),
            const SizedBox(width: 8),
          ],
          Text(label, style: TextStyle(fontSize: 12.5, color: muted)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OfficePanelHeader extends StatelessWidget {
  const OfficePanelHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
    child: Row(
      children: [
        Flexible(
          child: Text(
            title.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: DsColors.textSecondary(Theme.of(context).brightness),
            ),
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}
