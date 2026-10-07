import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tools the user opened most recently (newest first), for the sidebar.
class RecentToolsNotifier extends Notifier<List<String>> {
  static const _key = 'recent_tool_ids_v1';
  static const maxItems = 6;

  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key);
      if (saved != null) state = saved;
    } catch (_) {}
  }

  Future<void> record(String id) async {
    final next = [id, ...state.where((e) => e != id)].take(maxItems).toList();
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, next);
    } catch (_) {}
  }
}

final recentToolsProvider = NotifierProvider<RecentToolsNotifier, List<String>>(
  RecentToolsNotifier.new,
);
