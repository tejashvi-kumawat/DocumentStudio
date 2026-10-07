import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preference for the floating workspace sidebar (persisted).
@immutable
class DsSidebarState {
  const DsSidebarState({
    this.collapsed = false,
    this.width = defaultWidth,
    this.collapsedSections = const {},
  });

  static const double minWidth = 200;
  static const double maxWidth = 340;
  static const double defaultWidth = 244;

  /// Icon-only rail width (collapsed or narrow windows).
  static const double railWidth = 60;

  final bool collapsed;
  final double width;

  /// Disclosure groups the user folded (section ids).
  final Set<String> collapsedSections;

  DsSidebarState copyWith({
    bool? collapsed,
    double? width,
    Set<String>? collapsedSections,
  }) {
    return DsSidebarState(
      collapsed: collapsed ?? this.collapsed,
      width: width ?? this.width,
      collapsedSections: collapsedSections ?? this.collapsedSections,
    );
  }
}

final dsSidebarProvider = NotifierProvider<DsSidebarNotifier, DsSidebarState>(
  DsSidebarNotifier.new,
);

class DsSidebarNotifier extends Notifier<DsSidebarState> {
  static const _kCollapsed = 'shell.sidebar.collapsed';
  static const _kWidth = 'shell.sidebar.width';
  static const _kSections = 'shell.sidebar.collapsedSections';

  @override
  DsSidebarState build() {
    Future.microtask(_load);
    return const DsSidebarState(collapsedSections: {'tools_automation'});
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = DsSidebarState(
        collapsed: prefs.getBool(_kCollapsed) ?? state.collapsed,
        width: (prefs.getDouble(_kWidth) ?? state.width).clamp(
          DsSidebarState.minWidth,
          DsSidebarState.maxWidth,
        ),
        collapsedSections:
            prefs.getStringList(_kSections)?.toSet() ?? state.collapsedSections,
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kCollapsed, state.collapsed);
      await prefs.setDouble(_kWidth, state.width);
      await prefs.setStringList(_kSections, state.collapsedSections.toList());
    } catch (_) {}
  }

  void toggleCollapsed() {
    state = state.copyWith(collapsed: !state.collapsed);
    _save();
  }

  /// Live resize while dragging; call [commitWidth] on drag end.
  void setWidth(double width) {
    state = state.copyWith(
      width: width.clamp(DsSidebarState.minWidth, DsSidebarState.maxWidth),
    );
  }

  void commitWidth() => _save();

  void toggleSection(String id) {
    final next = {...state.collapsedSections};
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(collapsedSections: next);
    _save();
  }
}
