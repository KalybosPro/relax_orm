/// The current state of the sync engine.
enum SyncStatus {
  /// Not started or stopped.
  idle,

  /// Currently pushing local changes or pulling remote changes.
  syncing,

  /// All local changes have been pushed and remote changes pulled.
  synced,

  /// The device is offline — operations are queued locally.
  offline,

  /// An error occurred during sync.
  error,
}

/// The type of a queued sync operation.
enum SyncOperationType {
  add,
  update,
  delete,
}

/// The state of a single queued operation.
enum OperationStatus {
  /// Waiting to be synced.
  pending,

  /// Currently being sent to the server.
  syncing,

  /// Failed to sync (will be retried).
  failed,
}
