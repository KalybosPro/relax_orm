import 'sync_status.dart';

/// A single CRUD operation queued for sync.
///
/// Stored in an internal `_relax_sync_queue` table and replayed
/// when connectivity is restored.
class SyncOperation {
  /// Unique ID for this operation.
  final String id;

  /// The table this operation targets.
  final String tableName;

  /// The type of operation (add, update, delete).
  final SyncOperationType type;

  /// The primary key of the affected entity.
  final String entityId;

  /// The serialized entity data (null for deletes).
  final Map<String, dynamic>? data;

  /// When the operation was created locally.
  final DateTime createdAt;

  /// Current status of this operation.
  final OperationStatus status;

  /// Number of times sync has been attempted and failed.
  final int retryCount;

  const SyncOperation({
    required this.id,
    required this.tableName,
    required this.type,
    required this.entityId,
    this.data,
    required this.createdAt,
    this.status = OperationStatus.pending,
    this.retryCount = 0,
  });

  SyncOperation copyWith({
    OperationStatus? status,
    int? retryCount,
  }) {
    return SyncOperation(
      id: id,
      tableName: tableName,
      type: type,
      entityId: entityId,
      data: data,
      createdAt: createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}
