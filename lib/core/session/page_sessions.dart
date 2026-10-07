/// Live editor state that outlives its widgets while its page tab is open.
///
/// Switching tabs rebuilds the routed page; editors park their document
/// here (by tab location) and pick it up again, so nothing is re-read from
/// disk and unsaved edits survive. Closing the tab releases it.
class PageSessions {
  PageSessions._();

  static final Map<String, Object> _byKey = {};

  static T? get<T extends Object>(String key) {
    final v = _byKey[key];
    return v is T ? v : null;
  }

  static void put(String key, Object session) => _byKey[key] = session;

  static void drop(String key) => _byKey.remove(key);

  static int get length => _byKey.length;
}
