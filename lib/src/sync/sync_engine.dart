import 'dart:async';

import '../database/relax_database.dart';
import '../schema/table_schema.dart';
import 'conflict_resolver.dart';
import 'offline_queue.dart';
import 'sync_adapter.dart';
import 'sync_operation.dart';
import 'sync_status.dart';

/// Configuration for syncing a specific collection.
class SyncConfig<T> {
  final TableSchema<T> schema;
  final SyncAdapter<T> adapter;
  final ConflictResolver<T> conflictResolver;

  /// How often to auto-sync when online (null = manual only).
  final Duration? autoSyncInterval;

  /// Max retry attempts for failed operations.
  final int maxRetries;

  SyncConfig({
    required this.schema,
    required this.adapter,
    ConflictResolver<T>? conflictResolver,
    this.autoSyncInterval,
    this.maxRetries = 5,
  }) : conflictResolver = conflictResolver ?? ConflictResolver.remoteWins<T>();
}

/// Orchestrates offline queue processing, push/pull sync, and conflict resolution.
///
/// ```dart
/// final engine = SyncEngine(database, queue);
///
/// engine.register(SyncConfig(
///   schema: userSchema,
///   adapter: UserSyncAdapter(api),
///   autoSyncInterval: Duration(minutes: 5),
/// ));
///
/// engine.connectivityStream = myConnectivityStream;
/// engine.start();
///
/// engine.status.listen((s) => print('Sync: $s'));
/// ```
class SyncEngine {
  final RelaxDatabase _db;
  final OfflineQueue _queue;
  final Map<String, _SyncRegistration> _registrations = {};

  final _statusController = StreamController<SyncStatus>.broadcast();
  final _lastSyncTimes = <String, DateTime>{};
  final _autoSyncTimers = <String, Timer>{};

  StreamSubscription<bool>? _connectivitySub;
  bool _isOnline = true;
  bool _isSyncing = false;

  SyncEngine(this._db, this._queue);

  /// Stream of sync status changes.
  Stream<SyncStatus> get status => _statusController.stream;

  /// Whether the device is currently online.
  bool get isOnline => _isOnline;

  /// Whether a sync is currently in progress.
  bool get isSyncing => _isSyncing;

  /// Sets the connectivity stream. Emits `true` when online, `false` when offline.
  ///
  /// When transitioning from offline → online, pending operations are automatically synced.
  set connectivityStream(Stream<bool> stream) {
    _connectivitySub?.cancel();
    _connectivitySub = stream.listen(_onConnectivityChanged);
  }

  /// Registers a collection for sync.
  void register<T>(SyncConfig<T> config) {
    _registrations[config.schema.tableName] = _SyncRegistration<T>(config);

    // Set up auto-sync timer if configured.
    if (config.autoSyncInterval != null) {
      _autoSyncTimers[config.schema.tableName]?.cancel();
      _autoSyncTimers[config.schema.tableName] = Timer.periodic(
        config.autoSyncInterval!,
        (_) => syncTable(config.schema.tableName),
      );
    }
  }

  /// Queues a CRUD operation for later sync.
  ///
  /// Called internally by [Collection] when sync is enabled.
  Future<void> queueOperation({
    required String tableName,
    required SyncOperationType type,
    required String entityId,
    Map<String, dynamic>? data,
  }) async {
    final op = SyncOperation(
      id: '${tableName}_${entityId}_${DateTime.now().microsecondsSinceEpoch}',
      tableName: tableName,
      type: type,
      entityId: entityId,
      data: data,
      createdAt: DateTime.now(),
    );
    await _queue.enqueue(op);
  }

  /// Syncs a single table: pushes local changes, then pulls remote changes.
  Future<void> syncTable(String tableName) async {
    final reg = _registrations[tableName];
    if (reg == null || !_isOnline || _isSyncing) return;

    _isSyncing = true;
    _emitStatus(SyncStatus.syncing);

    try {
      await _pushChanges(tableName, reg);
      await _pullChanges(tableName, reg);

      _lastSyncTimes[tableName] = DateTime.now();
      _emitStatus(SyncStatus.synced);
    } catch (e) {
      _emitStatus(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }

  /// Syncs all registered tables.
  Future<void> syncAll() async {
    for (final tableName in _registrations.keys) {
      await syncTable(tableName);
    }
  }

  /// Starts the sync engine.
  ///
  /// If online, immediately syncs all registered tables.
  Future<void> start() async {
    if (_isOnline) {
      await _queue.resetFailed();
      await syncAll();
    }
  }

  /// Stops the sync engine and cancels all timers.
  void stop() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    for (final timer in _autoSyncTimers.values) {
      timer.cancel();
    }
    _autoSyncTimers.clear();
    _emitStatus(SyncStatus.idle);
  }

  /// Disposes the engine and closes all streams.
  Future<void> dispose() async {
    stop();
    await _statusController.close();
  }

  /// Returns the number of pending operations in the queue.
  Future<int> pendingCount() => _queue.pendingCount();

  void _emitStatus(SyncStatus s) {
    if (!_statusController.isClosed) _statusController.add(s);
  }

  // -- Internal --

  Future<void> _pushChanges(String tableName, _SyncRegistration reg) async {
    final pending = await _queue.getPending(tableName);
    if (pending.isEmpty) return;

    try {
      await reg.pushOperations(pending);
      await _queue.completeAll(pending.map((op) => op.id).toList());
    } catch (e) {
      for (final op in pending) {
        await _queue.markFailed(op.id);
      }
      rethrow;
    }
  }

  Future<void> _pullChanges(String tableName, _SyncRegistration reg) async {
    final since = _lastSyncTimes[tableName];
    await reg.applyPull(_db, tableName, since);
  }

  void _onConnectivityChanged(bool online) {
    final wasOffline = !_isOnline;
    _isOnline = online;

    if (online) {
      if (wasOffline) {
        // Back online — sync all pending operations.
        _emitStatus(SyncStatus.syncing);
        _queue.resetFailed().then((_) => syncAll());
      }
    } else {
      _emitStatus(SyncStatus.offline);
    }
  }
}

/// Internal wrapper that preserves the type parameter [T] for push/pull operations.
class _SyncRegistration<T> {
  final SyncConfig<T> config;
  _SyncRegistration(this.config);

  /// Pushes pending operations to the remote server (typed).
  Future<void> pushOperations(List<SyncOperation> pending) async {
    final adds = pending.where((op) => op.type == SyncOperationType.add).toList();
    final updates = pending.where((op) => op.type == SyncOperationType.update).toList();
    final deletes = pending.where((op) => op.type == SyncOperationType.delete).toList();

    final upsertOps = [...adds, ...updates];
    if (upsertOps.isNotEmpty) {
      final entities = upsertOps
          .where((op) => op.data != null)
          .map((op) => config.schema.fromMap(op.data!))
          .toList();
      if (entities.isNotEmpty) {
        await config.adapter.push(entities);
      }
    }

    if (deletes.isNotEmpty) {
      final ids = deletes.map((op) => op.entityId).toList();
      await config.adapter.pushDeletes(ids);
    }
  }

  /// Pulls remote changes and applies them locally with conflict resolution.
  Future<void> applyPull(
    RelaxDatabase db,
    String tableName,
    DateTime? since,
  ) async {
    final result = await config.adapter.pull(since: since);
    final schema = config.schema;
    final pk = schema.primaryKey;

    for (final T remoteEntity in result.upserts) {
      final id = schema.getPrimaryKeyValue(remoteEntity);

      final localRow = await db.rawSelectOne(
        tableName,
        where: '${pk.name} = ?',
        whereArgs: [pk.toSql(id)],
      );

      if (localRow != null) {
        final T localEntity = schema.rowToEntity(localRow);
        final T resolved =
            config.conflictResolver.resolve(localEntity, remoteEntity);
        final resolvedRow = schema.entityToRow(resolved);
        resolvedRow.remove(pk.name);
        await db.rawUpdate(
          tableName,
          resolvedRow,
          where: '${pk.name} = ?',
          whereArgs: [pk.toSql(id)],
        );
      } else {
        await db.rawInsert(tableName, schema.entityToRow(remoteEntity));
      }
    }

    for (final deletedId in result.deletedIds) {
      await db.rawDelete(
        tableName,
        where: '${pk.name} = ?',
        whereArgs: [pk.toSql(deletedId)],
      );
    }
  }
}

