import '../database/relax_database.dart';
import '../schema/table_schema.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_status.dart';
import 'query_builder.dart';

/// A typed collection providing CRUD operations and real-time streams.
///
/// ```dart
/// final users = db.collection<User>();
///
/// await users.add(user);
/// final user = await users.get('some-id');
/// final all = await users.getAll();
/// await users.update(user);
/// await users.delete('some-id');
///
/// users.watchAll().listen((list) => print(list));
/// users.watchOne('some-id').listen((user) => print(user));
/// ```
class Collection<T> {
  final RelaxDatabase _db;
  final TableSchema<T> _schema;
  final SyncEngine? _syncEngine;

  Collection(this._db, this._schema, {SyncEngine? syncEngine})
    : _syncEngine = syncEngine;

  /// Inserts a new entity into the collection.
  ///
  /// If sync is enabled, the operation is queued for push to the server.
  Future<void> add(T entity) async {
    final row = _schema.entityToRow(entity);
    await _db.rawInsert(_schema.tableName, row);
    final updatedEntity = _schema.rowToEntity(row);
    await _queueSync(SyncOperationType.add, updatedEntity);
  }

  /// Inserts multiple entities in a single batch operation.
  Future<void> addAll(List<T> entities) async {
    final rows = entities.map(_schema.entityToRow).toList();
    await _db.rawBatchInsert(_schema.tableName, rows);
  }

  /// Updates an existing entity (matched by primary key).
  ///
  /// Returns `true` if a row was updated, `false` if no matching row was found.
  Future<bool> update(T entity) async {
    final row = _schema.entityToRow(entity);
    final pk = _schema.primaryKey;
    final pkValue = row.remove(pk.name);

    final affected = await _db.rawUpdate(
      _schema.tableName,
      row,
      where: '${pk.name} = ?',
      whereArgs: [pkValue],
    );
    if (affected > 0) await _queueSync(SyncOperationType.update, entity);
    return affected > 0;
  }

  /// Inserts the entity if it doesn't exist, updates it otherwise.
  Future<void> upsert(T entity) async {
    final exists = await get(_schema.getPrimaryKeyValue(entity));
    if (exists != null) {
      await update(entity);
    } else {
      await add(entity);
    }
  }

  /// Deletes an entity by its primary key value.
  ///
  /// Returns `true` if a row was deleted, `false` if no matching row was found.
  Future<bool> delete(Object id) async {
    final pk = _schema.primaryKey;
    final sqlId = pk.toSql(id);
    final affected = await _db.rawDelete(
      _schema.tableName,
      where: '${pk.name} = ?',
      whereArgs: [sqlId],
    );
    if (affected > 0) await _queueSyncDelete(id);
    return affected > 0;
  }

  /// Deletes all rows in the collection.
  Future<void> deleteAll() async {
    await _db.rawDelete(_schema.tableName, where: '1 = 1', whereArgs: []);
  }

  /// Retrieves a single entity by primary key, or `null` if not found.
  Future<T?> get(Object id) async {
    final pk = _schema.primaryKey;
    final sqlId = pk.toSql(id);
    final row = await _db.rawSelectOne(
      _schema.tableName,
      where: '${pk.name} = ?',
      whereArgs: [sqlId],
    );
    if (row == null) return null;
    return _schema.rowToEntity(row);
  }

  /// Retrieves all entities in the collection.
  Future<List<T>> getAll() async {
    final rows = await _db.rawSelect(_schema.tableName);
    return rows.map(_schema.rowToEntity).toList();
  }

  /// Returns the number of entities in the collection.
  Future<int> count() async {
    return _db.rawCount(_schema.tableName);
  }

  /// Watches all entities in the collection as a reactive stream.
  ///
  /// The stream emits a new list every time the table is modified.
  Stream<List<T>> watchAll() {
    return _db
        .rawWatch(_schema.tableName)
        .map((rows) => rows.map(_schema.rowToEntity).toList());
  }

  /// Watches a single entity by primary key as a reactive stream.
  ///
  /// Emits `null` if the entity is deleted or doesn't exist.
  Stream<T?> watchOne(Object id) {
    final pk = _schema.primaryKey;
    final sqlId = pk.toSql(id);
    return _db
        .rawWatchOne(
          _schema.tableName,
          where: '${pk.name} = ?',
          whereArgs: [sqlId],
        )
        .map((row) => row == null ? null : _schema.rowToEntity(row));
  }

  /// Returns a [QueryBuilder] for building filtered, sorted, paginated queries.
  ///
  /// ```dart
  /// final adults = await users
  ///     .query()
  ///     .where('age', greaterThan: 18)
  ///     .orderBy('name')
  ///     .limit(10)
  ///     .find();
  /// ```
  QueryBuilder<T> query() => QueryBuilder<T>(_db, _schema);

  // -- Sync helpers --

  Future<void> _queueSync(SyncOperationType type, T entity) async {
    if (_syncEngine == null) return;
    final id = _schema.getPrimaryKeyValue(entity).toString();
    final data = _schema.toMap(entity);
    await _syncEngine.queueOperation(
      tableName: _schema.tableName,
      type: type,
      entityId: id,
      data: data,
    );
  }

  Future<void> _queueSyncDelete(Object id) async {
    if (_syncEngine == null) return;
    await _syncEngine.queueOperation(
      tableName: _schema.tableName,
      type: SyncOperationType.delete,
      entityId: id.toString(),
    );
  }
}
