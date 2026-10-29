/// Tolerant readers for the backend's response envelopes.
///
/// The backend is not uniform: most endpoints answer `{ success, data }`, some
/// `{ success, results }`, and list endpoints nest the array under a named key
/// (`data.tickets`, `data.requests`, `data.results`, `data.data`, ...). These
/// helpers never throw, so a shape change degrades to an empty state instead of
/// an uncaught cast error that leaves a spinner running forever.
class ApiEnvelope {
  ApiEnvelope._();

  static const List<String> _defaultListKeys = [
    'results',
    'data',
    'items',
    'docs',
    'list',
  ];

  /// The `data` payload when present, otherwise the body itself.
  static dynamic payload(dynamic body) {
    if (body is Map && body.containsKey('data')) return body['data'];
    return body;
  }

  /// The payload as a map (empty when absent or not a map).
  static Map<String, dynamic> map(dynamic body) {
    final p = payload(body);
    if (p is Map<String, dynamic>) return p;
    if (p is Map) return Map<String, dynamic>.from(p);
    return <String, dynamic>{};
  }

  /// Finds the list in [body], trying [keys] first and then common keys,
  /// one level into `data` as well as at the top level.
  static List<Map<String, dynamic>> list(
    dynamic body, {
    List<String> keys = const [],
  }) {
    final allKeys = [...keys, ..._defaultListKeys];
    List<dynamic>? found;
    dynamic search(dynamic node, int depth) {
      if (node is List) return node;
      if (node is Map && depth < 3) {
        for (final k in allKeys) {
          final v = node[k];
          if (v is List) return v;
        }
        for (final k in allKeys) {
          final v = node[k];
          if (v is Map) {
            final r = search(v, depth + 1);
            if (r is List) return r;
          }
        }
      }
      return null;
    }

    final r = search(body, 0);
    if (r is List) found = r;
    return (found ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
