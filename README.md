# RelaxORM

A **local-first ORM** for Flutter with offline support, real-time streams, automatic sync, and encryption.

Inspired by Firebase and PowerSync — but free, self-hosted, and with no SaaS dependency.

## Features

- **Simple API** — `db.collection<User>()` with typed CRUD
- **Real-time streams** — `watchAll()` / `watchOne()` for reactive UI
- **Offline-first** — all operations succeed locally, sync when back online
- **Sync engine** — push/pull with configurable conflict resolution
- **Encryption** — transparent AES database encryption via SQLite3MultipleCiphers
- **Query builder** — fluent, type-safe filters, sorting, pagination
- **Code generation** — annotate your models, schemas are generated automatically
- **Zero SaaS** — bring your own API, no vendor lock-in

## Quick Start

### 1. Add dependencies

```yaml
dependencies:
  relax_orm: ^0.1.0

dev_dependencies:
  relax_orm_generator: ^0.1.0
  build_runner: ^2.4.0
```

### 2. Define your model

```dart
import 'package:relax_orm/relax_orm.dart';

part 'user.g.dart';

@RelaxTable()
class User {
  @PrimaryKey()
  final String id;
  final String name;
  final int age;
  final bool active;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    required this.age,
    required this.active,
    required this.createdAt,
  });
}
```

### 3. Generate the schema

```bash
dart run build_runner build
```

This generates `user.g.dart` containing a `userSchema` variable with all the column definitions, mappers, and type conversions.

### 4. Open the database and use it

```dart
final db = await RelaxDB.open(
  name: 'my_app',
  schemas: [userSchema],
  encryptionKey: 'optional-secret', // omit for no encryption
);

final users = db.collection<User>();
```

## CRUD Operations

```dart
// Create
await users.add(User(id: '1', name: 'Alice', age: 30, active: true, createdAt: DateTime.now()));

// Read
final user = await users.get('1');
final all = await users.getAll();
final count = await users.count();

// Update
await users.update(user.copyWith(name: 'Alice Updated'));

// Upsert (insert or update)
await users.upsert(user);

// Delete
await users.delete('1');
await users.deleteAll();

// Batch insert
await users.addAll([user1, user2, user3]);
```

## Queries

```dart
final adults = await users
    .query()
    .where('age', greaterThan: 18)
    .where('active', equals: 1)
    .orderBy('name')
    .limit(10)
    .offset(20)
    .find();

// Single result
final admin = await users.query().where('name', equals: 'Admin').findOne();

// Count matching
final activeCount = await users.query().where('active', equals: 1).count();
```

### Available filters

| Filter | Example |
|---|---|
| `equals` | `.where('name', equals: 'Alice')` |
| `notEquals` | `.where('status', notEquals: 'banned')` |
| `greaterThan` | `.where('age', greaterThan: 18)` |
| `greaterThanOrEquals` | `.where('age', greaterThanOrEquals: 18)` |
| `lessThan` | `.where('age', lessThan: 65)` |
| `lessThanOrEquals` | `.where('score', lessThanOrEquals: 100)` |
| `contains` | `.where('name', contains: 'ali')` |
| `startsWith` | `.where('name', startsWith: 'Al')` |
| `endsWith` | `.where('email', endsWith: '.com')` |
| `isIn` | `.where('role', isIn: ['admin', 'mod'])` |
| `isNull` | `.where('deletedAt', isNull: true)` |

## Real-time Streams

```dart
// Watch all entities (re-emits on every table change)
users.watchAll().listen((list) {
  setState(() => _users = list);
});

// Watch a single entity
users.watchOne('1').listen((user) {
  setState(() => _currentUser = user);
});

// Watch a query
users.query().where('active', equals: 1).watch().listen((activeUsers) {
  setState(() => _activeUsers = activeUsers);
});
```

## Sync Engine

### 1. Implement a SyncAdapter for your API

```dart
class UserSyncAdapter implements SyncAdapter<User> {
  final ApiClient api;
  UserSyncAdapter(this.api);

  @override
  Future<List<User>> push(List<User> entities) async {
    final response = await api.post('/users/batch', entities);
    return response.users; // server-confirmed versions
  }

  @override
  Future<void> pushDeletes(List<Object> ids) async {
    await api.delete('/users/batch', ids);
  }

  @override
  Future<SyncPullResult<User>> pull({DateTime? since}) async {
    final response = await api.get('/users/changes', since: since);
    return SyncPullResult(
      upserts: response.updated,
      deletedIds: response.deleted,
    );
  }
}
```

### 2. Configure and start

```dart
final engine = await db.sync;

engine.register(SyncConfig<User>(
  schema: userSchema,
  adapter: UserSyncAdapter(api),
  conflictResolver: ConflictResolver.remoteWins(), // default
  autoSyncInterval: Duration(minutes: 5),          // optional
));

// Connect your connectivity stream (e.g. from connectivity_plus)
engine.connectivityStream = Connectivity().onConnectivityChanged
    .map((result) => result != ConnectivityResult.none);

// Listen to sync status
engine.status.listen((status) {
  print(status); // idle, syncing, synced, offline, error
});

// Start syncing
await engine.start();
```

### 3. That's it

All CRUD operations on synced collections are automatically queued and pushed when connectivity is restored.

### Conflict Resolution

```dart
// Remote always wins (default)
ConflictResolver.remoteWins<User>()

// Local always wins
ConflictResolver.localWins<User>()

// Custom logic
ConflictResolver<User>.custom((local, remote) {
  return remote.updatedAt.isAfter(local.updatedAt) ? remote : local;
})
```

## Encryption

RelaxORM uses SQLite3MultipleCiphers for transparent database encryption.

### Setup

Add to your app's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

### Usage

```dart
final db = await RelaxDB.open(
  name: 'my_app',
  schemas: [userSchema],
  encryptionKey: 'your-secret-key',
);
```

The entire database file is encrypted. Without the correct key, the file is unreadable.

## Annotations Reference

| Annotation | Usage |
|---|---|
| `@RelaxTable()` | Marks a class as an ORM entity |
| `@RelaxTable(name: 'custom')` | Custom table name |
| `@PrimaryKey()` | Marks the primary key field |
| `@Column(name: 'col')` | Custom column name |
| `@Column(nullable: true)` | Nullable column |
| `@Ignore()` | Excludes a field from the schema |

### Supported types

`String`, `int`, `double`, `bool`, `DateTime`, `Uint8List`

Nullable variants (`String?`, `int?`, etc.) are also supported.

## Database Access

```dart
// Production (recommended) — Drift handles paths & isolates
final db = await RelaxDB.open(name: 'app', schemas: [...]);

// Custom file path
final db = await RelaxDB.openFile(file: File('path.db'), schemas: [...]);

// In-memory (testing)
final db = await RelaxDB.openInMemory(schemas: [...]);

// Close when done
await db.close();
```

## Architecture

```
+--------------------------------------------------+
|                  Your Flutter App                 |
+--------------------------------------------------+
|   RelaxDB          Collection<T>     QueryBuilder |
|   (entry point)    (typed CRUD)      (fluent API) |
+--------------------------------------------------+
|   SyncEngine       OfflineQueue      Conflict     |
|   (push/pull)      (persisted)       Resolver     |
+--------------------------------------------------+
|   Drift (SQLite)   SQLite3MultipleCiphers         |
|   (hidden)         (encryption)                   |
+--------------------------------------------------+
```

## License

MIT
