import 'dart:convert';

import '../database/relax_database.dart';
import 'sync_operation.dart';
import 'sync_status.dart';

/// Persists pending sync operations in an internal SQLite table.
///
/// Operations are stored in `_relax_sync_queue` and replayed by the [SyncEngine]
/// when connectivity is restored.
class OfflineQueue {
  static const _table = '_relax_sync_queue';

  final RelaxDatabase _db;

  OfflineQueue(this._db);

  /// Creates the internal queue table if it doesn't exist.
  Future<void> init() async {
    await _db.createTable('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        data TEXT,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Enqueues a new operation.
  Future<void> enqueue(SyncOperation op) async {
    await _db.rawInsert(_table, _toRow(op));
  }

  /// Returns all pending operations for a given table, ordered by creation time.
  Future<List<SyncOperation>> getPending(String tableName) async {
    final rows = await _db.rawSelect(
      _table,
      where: "table_name = ? AND status = 'pending'",
      whereArgs: [tableName],
    );
    return rows.map(_fromRow).toList();
  }

  /// Returns all pending operations across all tables.
  Future<List<SyncOperation>> getAllPending() async {
    final rows = await _db.rawSelect(
      _table,
      where: "status = 'pending'",
      whereArgs: [],
    );
    return rows.map(_fromRow).toList();
  }

  /// Marks an operation as completed and removes it from the queue.
  Future<void> complete(String operationId) async {
    await _db.rawDelete(
      _table,
      where: 'id = ?',
      whereArgs: [operationId],
    );
  }

  /// Marks multiple operations as completed.
  Future<void> completeAll(List<String> operationIds) async {
    for (final id in operationIds) {
      await complete(id);
    }
  }

  /// Marks an operation as failed and increments its retry count.
  Future<void> markFailed(String operationId) async {
    await _db.customStatement(
      'UPDATE $_table SET status = ?, retry_count = retry_count + 1 WHERE id = ?',
      ['failed', operationId],
    );
  }

  /// Resets failed operations back to pending so they'll be retried.
  Future<void> resetFailed({int maxRetries = 5}) async {
    await _db.customStatement(
      "UPDATE $_table SET status = 'pending' WHERE status = 'failed' AND retry_count < ?",
      [maxRetries],
    );
  }

  /// Returns the number of pending operations.
  Future<int> pendingCount() async {
    return _db.rawCount("$_table WHERE status = 'pending'");
  }

  /// Clears all operations from the queue.
  Future<void> clear() async {
    await _db.rawDelete(_table, where: '1 = 1', whereArgs: []);
  }

  // -- Serialization --

  Map<String, Object?> _toRow(SyncOperation op) {
    return {
      'id': op.id,
      'table_name': op.tableName,
      'type': op.type.name,
      'entity_id': op.entityId,
      'data': op.data != null ? jsonEncode(op.data) : null,
      'created_at': op.createdAt.millisecondsSinceEpoch,
      'status': op.status.name,
      'retry_count': op.retryCount,
    };
  }

  SyncOperation _fromRow(Map<String, dynamic> row) {
    return SyncOperation(
      id: row['id'] as String,
      tableName: row['table_name'] as String,
      type: SyncOperationType.values.byName(row['type'] as String),
      entityId: row['entity_id'] as String,
      data: row['data'] != null
          ? jsonDecode(row['data'] as String) as Map<String, dynamic>
          : null,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      status: OperationStatus.values.byName(row['status'] as String),
      retryCount: row['retry_count'] as int,
    );
  }
}
