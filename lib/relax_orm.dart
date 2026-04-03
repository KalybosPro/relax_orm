/// RelaxORM — A local-first ORM for Flutter.
///
/// Provides offline-first data persistence with real-time streams,
/// automatic encryption, and a simple developer experience.
///
/// ```dart
/// final db = await RelaxDB.open(
///   name: 'my_app',
///   schemas: [userSchema],
/// );
///
/// final users = db.collection<User>();
/// await users.add(user);
/// users.watchAll().listen((list) => print(list));
/// ```
library;

// Annotations
export 'src/annotations/annotations.dart';

// Schema definition
export 'src/schema/column_def.dart';
export 'src/schema/table_schema.dart';

// Public API
export 'src/core/relax_db.dart';
export 'src/core/collection.dart';
export 'src/core/query_builder.dart';

// Sync engine
export 'src/sync/sync_adapter.dart';
export 'src/sync/sync_engine.dart';
export 'src/sync/sync_operation.dart';
export 'src/sync/sync_status.dart';
export 'src/sync/conflict_resolver.dart';
