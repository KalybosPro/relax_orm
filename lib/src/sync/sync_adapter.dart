/// Result of pulling remote changes from the server.
class SyncPullResult<T> {
  /// Entities that were created or updated on the server.
  final List<T> upserts;

  /// Primary key values of entities deleted on the server.
  final List<Object> deletedIds;

  const SyncPullResult({
    this.upserts = const [],
    this.deletedIds = const [],
  });
}

/// Interface for syncing a collection with a remote data source.
///
/// Implement this for each collection that needs sync.
///
/// ```dart
/// class UserSyncAdapter implements SyncAdapter<User> {
///   final ApiClient api;
///   UserSyncAdapter(this.api);
///
///   @override
///   Future<List<User>> push(List<User> entities) async {
///     return await api.post('/users/batch', entities);
///   }
///
///   @override
///   Future<void> pushDeletes(List<Object> ids) async {
///     await api.delete('/users/batch', ids);
///   }
///
///   @override
///   Future<SyncPullResult<User>> pull({DateTime? since}) async {
///     final response = await api.get('/users/changes', since: since);
///     return SyncPullResult(
///       upserts: response.upserts,
///       deletedIds: response.deletedIds,
///     );
///   }
/// }
/// ```
abstract class SyncAdapter<T> {
  /// Pushes created/updated entities to the remote server.
  ///
  /// Returns the server-confirmed versions of the entities
  /// (which may include server-assigned timestamps, ids, etc.).
  Future<List<T>> push(List<T> entities);

  /// Notifies the server about locally deleted entities.
  Future<void> pushDeletes(List<Object> ids);

  /// Pulls remote changes since [since].
  ///
  /// If [since] is null, pulls all data (initial sync).
  Future<SyncPullResult<T>> pull({DateTime? since});
}
