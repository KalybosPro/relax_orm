import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../database/relax_database.dart';
import '../schema/table_schema.dart';
import '../sync/offline_queue.dart';
import '../sync/sync_engine.dart';
import 'collection.dart';

/// Callback applied to the raw SQLite database right after opening.
///
/// Use this to run PRAGMAs or install custom functions.
typedef DatabaseSetup = void Function(dynamic rawDb);

/// The main entry point for RelaxORM.
///
/// ```dart
/// final db = await RelaxDB.open(
///   name: 'my_app',
///   schemas: [userSchema, postSchema],
///   encryptionKey: 'optional-secret-key',
/// );
///
/// final users = db.collection<User>();
/// await users.add(user);
/// ```
class RelaxDB {
  final RelaxDatabase _database;
  final Map<Type, TableSchema> _schemas;
  SyncEngine? _syncEngine;
  OfflineQueue? _offlineQueue;

  RelaxDB._(this._database, this._schemas);

  /// Opens (or creates) a RelaxORM database using [drift_flutter].
  ///
  /// This is the recommended way to open a database in a Flutter app.
  /// Drift handles platform-specific file paths and isolates.
  ///
  /// - [name]: The database file name (without extension).
  /// - [schemas]: List of table schemas to create.
  /// - [encryptionKey]: Optional encryption key (enables SQLite3MultipleCiphers).
  static Future<RelaxDB> open({
    required String name,
    required List<TableSchema> schemas,
    String? encryptionKey,
  }) async {
    final executor = driftDatabase(
      name: name,
      native: DriftNativeOptions(
        setup: _buildSetup(encryptionKey),
      ),
    );

    return _init(RelaxDatabase(executor), schemas);
  }

  /// Opens a database from a specific file path.
  ///
  /// Useful for tests or when you need full control over the file location.
  ///
  /// - [file]: The database file.
  /// - [schemas]: List of table schemas to create.
  /// - [encryptionKey]: Optional encryption key (enables SQLite3MultipleCiphers).
  static Future<RelaxDB> openFile({
    required File file,
    required List<TableSchema> schemas,
    String? encryptionKey,
  }) async {
    final nativeDb = NativeDatabase(
      file,
      setup: _buildSetup(encryptionKey),
    );

    return _init(RelaxDatabase(nativeDb), schemas);
  }

  /// Opens an in-memory database (for testing).
  ///
  /// Data is not persisted — the database is destroyed when [close] is called.
  ///
  /// Note: encryption is not supported for in-memory databases (SQLite limitation).
  /// Use [openFile] for encrypted databases.
  static Future<RelaxDB> openInMemory({
    required List<TableSchema> schemas,
  }) async {
    final nativeDb = NativeDatabase.memory();
    return _init(RelaxDatabase(nativeDb), schemas);
  }

  /// Returns a typed [Collection] for the given entity type.
  ///
  /// The type [T] must match one of the schemas registered at [open].
  ///
  /// ```dart
  /// final users = db.collection<User>();
  /// ```
  Collection<T> collection<T>() {
    final schema = _findSchema<T>();
    return Collection<T>(_database, schema, syncEngine: _syncEngine);
  }

  /// Returns the [SyncEngine], creating it lazily if needed.
  ///
  /// Use this to register sync adapters and control the sync lifecycle.
  ///
  /// ```dart
  /// db.sync.register(SyncConfig(
  ///   schema: userSchema,
  ///   adapter: UserSyncAdapter(api),
  /// ));
  /// db.sync.connectivityStream = connectivityStream;
  /// db.sync.start();
  /// ```
  Future<SyncEngine> get sync async {
    if (_syncEngine != null) return _syncEngine!;

    _offlineQueue = OfflineQueue(_database);
    await _offlineQueue!.init();
    _syncEngine = SyncEngine(_database, _offlineQueue!);
    return _syncEngine!;
  }

  /// Closes the database connection and disposes the sync engine.
  Future<void> close() async {
    await _syncEngine?.dispose();
    await _database.close();
  }

  // -- Private helpers --

  static Future<RelaxDB> _init(
    RelaxDatabase database,
    List<TableSchema> schemas,
  ) async {
    for (final schema in schemas) {
      await database.createTable(schema.toCreateTableSql());
    }

    final schemaMap = <Type, TableSchema>{};
    for (final schema in schemas) {
      schemaMap[schema.runtimeType] = schema;
    }

    return RelaxDB._(database, schemaMap);
  }

  /// Returns `true` if the SQLite library supports encryption
  /// (SQLite3MultipleCiphers is linked).
  ///
  /// Requires an open database. Call after [open], [openFile], or [openInMemory].
  Future<bool> isEncryptionAvailable() async {
    try {
      final rows = await _database.customSelect('PRAGMA cipher').get();
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static DatabaseSetup? _buildSetup(String? encryptionKey) {
    if (encryptionKey == null) return null;
    return (rawDb) {
      // Verify cipher support before applying key.
      final cipherResult = rawDb.select('PRAGMA cipher');
      if (cipherResult.isEmpty) {
        throw StateError(
          'Encryption requested but SQLite3MultipleCiphers is not available. '
          'Add this to your pubspec.yaml:\n'
          'hooks:\n'
          '  user_defines:\n'
          '    sqlite3:\n'
          '      source: sqlite3mc',
        );
      }
      rawDb.execute("PRAGMA key = '$encryptionKey'");
    };
  }

  TableSchema<T> _findSchema<T>() {
    for (final schema in _schemas.values) {
      if (schema is TableSchema<T>) return schema;
    }
    throw StateError(
      'No schema registered for type $T. '
      'Make sure you passed a TableSchema<$T> to RelaxDB.open().',
    );
  }
}
