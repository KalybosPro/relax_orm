/// Strategy for resolving conflicts when local and remote data diverge.
///
/// ```dart
/// // Use a built-in strategy:
/// final resolver = ConflictResolver.remoteWins<User>();
///
/// // Or implement your own:
/// final resolver = ConflictResolver<User>.custom((local, remote) {
///   return remote.updatedAt.isAfter(local.updatedAt) ? remote : local;
/// });
/// ```
class ConflictResolver<T> {
  final T Function(T local, T remote) _resolve;

  const ConflictResolver._(this._resolve);

  /// Creates a resolver with a custom merge function.
  const ConflictResolver.custom(T Function(T local, T remote) resolve)
      : _resolve = resolve;

  /// Remote data always wins. (Safe default for most apps.)
  static ConflictResolver<T> remoteWins<T>() {
    return ConflictResolver<T>._((_, remote) => remote);
  }

  /// Local data always wins. (Use when local edits are authoritative.)
  static ConflictResolver<T> localWins<T>() {
    return ConflictResolver<T>._((local, _) => local);
  }

  /// Resolves a conflict between a local and remote version of an entity.
  T resolve(T local, T remote) => _resolve(local, remote);
}
