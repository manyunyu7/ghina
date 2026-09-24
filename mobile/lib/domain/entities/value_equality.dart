/// Structural equality for the notes/content entities (lists and maps compared
/// deeply), so streams can `.distinct()` their read models.
library;

bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !deepEquals(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

int deepHash(Object? v) => switch (v) {
  final List<Object?> l => Object.hashAll(l.map(deepHash)),
  final Map<Object?, Object?> m => Object.hashAllUnordered(
    m.entries.map((e) => Object.hash(deepHash(e.key), deepHash(e.value))),
  ),
  _ => v.hashCode,
};

/// `==`/`hashCode` from [props] (same runtime type + deep-equal props).
mixin ValueEquality {
  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other.runtimeType == runtimeType &&
          other is ValueEquality &&
          deepEquals(props, other.props));

  @override
  int get hashCode => Object.hash(runtimeType, deepHash(props));
}
