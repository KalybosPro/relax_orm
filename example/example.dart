/// RelaxORM — Complete usage example.
///
/// This example demonstrates:
/// - Model definition with annotations
/// - Database initialization
/// - CRUD operations
/// - Queries with filters, sorting, pagination
/// - Real-time streams
/// - Sync engine setup
library;

import 'dart:async';

import 'package:relax_orm/relax_orm.dart';

import 'models.dart'; // Contains User, Post with generated schemas

// =============================================================================
// BASIC USAGE
// =============================================================================

Future<void> basicExample() async {
  // Open the database with encryption.
  final db = await RelaxDB.open(
    name: 'my_app',
    schemas: [userSchema, postSchema],
    encryptionKey: 'my-secret-key', // optional
  );

  final users = db.collection<User>();

  // -- Create --
  await users.add(User(
    id: '1',
    name: 'Alice',
    age: 30,
    active: true,
    createdAt: DateTime.now(),
  ));

  // -- Read --
  final alice = await users.get('1');
  print('Found: ${alice?.name}'); // Alice

  final allUsers = await users.getAll();
  print('Total users: ${allUsers.length}');

  // -- Update --
  await users.update(User(
    id: '1',
    name: 'Alice Updated',
    age: 31,
    active: true,
    createdAt: alice!.createdAt,
  ));

  // -- Upsert (insert or update) --
  await users.upsert(User(
    id: '2',
    name: 'Bob',
    age: 25,
    active: true,
    createdAt: DateTime.now(),
  ));

  // -- Delete --
  await users.delete('1');

  // -- Count --
  print('Remaining: ${await users.count()}');

  await db.close();
}

// =============================================================================
// QUERIES
// =============================================================================

Future<void> queryExample() async {
  final db = await RelaxDB.open(name: 'queries', schemas: [userSchema]);
  final users = db.collection<User>();

  // Seed data
  await users.addAll([
    User(id: '1', name: 'Alice', age: 30, active: true, createdAt: DateTime(2024, 1, 1)),
    User(id: '2', name: 'Bob', age: 17, active: true, createdAt: DateTime(2024, 2, 1)),
    User(id: '3', name: 'Charlie', age: 25, active: false, createdAt: DateTime(2024, 3, 1)),
    User(id: '4', name: 'Diana', age: 42, active: true, createdAt: DateTime(2024, 4, 1)),
  ]);

  // Filter + sort + paginate
  final adults = await users
      .query()
      .where('age', greaterThanOrEquals: 18)
      .where('active', equals: 1)
      .orderBy('age', desc: true)
      .limit(10)
      .find();
  print('Active adults: ${adults.map((u) => u.name)}'); // Diana, Alice

  // Find one
  final youngest = await users.query().orderBy('age').findOne();
  print('Youngest: ${youngest?.name}'); // Bob

  // Count matching
  final inactiveCount = await users.query().where('active', equals: 0).count();
  print('Inactive: $inactiveCount'); // 1

  // String matching
  final namesWithA = await users.query().where('name', contains: 'a').find();
  print('Names with "a": ${namesWithA.map((u) => u.name)}');

  await db.close();
}

// =============================================================================
// REAL-TIME STREAMS
// =============================================================================

Future<void> streamExample() async {
  final db = await RelaxDB.open(name: 'streams', schemas: [userSchema]);
  final users = db.collection<User>();

  // Watch all users — updates automatically on any table change.
  final subscription = users.watchAll().listen((allUsers) {
    print('Users changed: ${allUsers.length} total');
  });

  // Watch a single user.
  users.watchOne('1').listen((user) {
    print('User 1: ${user?.name ?? "deleted"}');
  });

  // Watch a query.
  users.query().where('active', equals: 1).watch().listen((active) {
    print('Active users: ${active.length}');
  });

  // These writes trigger all the streams above.
  await users.add(User(
    id: '1', name: 'Alice', age: 30, active: true, createdAt: DateTime.now(),
  ));

  await Future.delayed(Duration(milliseconds: 100));
  subscription.cancel();
  await db.close();
}

// =============================================================================
// SYNC ENGINE
// =============================================================================

/// Example SyncAdapter — replace with your actual API client.
class UserSyncAdapter implements SyncAdapter<User> {
  @override
  Future<List<User>> push(List<User> entities) async {
    // POST /api/users/batch
    print('Pushing ${entities.length} users to server...');
    return entities; // return server-confirmed versions
  }

  @override
  Future<void> pushDeletes(List<Object> ids) async {
    // DELETE /api/users/batch
    print('Deleting $ids from server...');
  }

  @override
  Future<SyncPullResult<User>> pull({DateTime? since}) async {
    // GET /api/users/changes?since=...
    print('Pulling user changes since $since...');
    return SyncPullResult(upserts: [], deletedIds: []);
  }
}

Future<void> syncExample() async {
  final db = await RelaxDB.open(name: 'sync', schemas: [userSchema]);

  // Initialize the sync engine.
  final engine = await db.sync;

  // Register a collection for sync.
  engine.register(SyncConfig<User>(
    schema: userSchema,
    adapter: UserSyncAdapter(),
    conflictResolver: ConflictResolver.remoteWins(),
    autoSyncInterval: Duration(minutes: 5),
  ));

  // Listen to sync status.
  engine.status.listen((status) {
    print('Sync status: $status');
  });

  // All CRUD operations are auto-queued for sync.
  final users = db.collection<User>();
  await users.add(User(
    id: '1', name: 'Alice', age: 30, active: true, createdAt: DateTime.now(),
  ));

  // Manually trigger sync.
  await engine.syncAll();

  // Check pending operations.
  print('Pending: ${await engine.pendingCount()}');

  await db.close();
}
