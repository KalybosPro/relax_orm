import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relax_orm/relax_orm.dart';
import 'package:relax_orm/src/database/relax_database.dart';
import 'package:relax_orm/src/sync/offline_queue.dart';

// -- Test model --

class Task {
  final String id;
  final String title;
  final bool done;

  Task({required this.id, required this.title, this.done = false});

  Task copyWith({String? title, bool? done}) =>
      Task(id: id, title: title ?? this.title, done: done ?? this.done);
}

final taskSchema = TableSchema<Task>(
  tableName: 'tasks',
  columns: [
    ColumnDef.text('id', isPrimaryKey: true),
    ColumnDef.text('title'),
    ColumnDef.boolean('done'),
  ],
  fromMap: (m) => Task(
    id: m['id'] as String,
    title: m['title'] as String,
    done: m['done'] as bool,
  ),
  toMap: (t) => {'id': t.id, 'title': t.title, 'done': t.done},
);

// -- Mock SyncAdapter --

class MockSyncAdapter implements SyncAdapter<Task> {
  final List<Task> pushedEntities = [];
  final List<Object> pushedDeletes = [];
  int pushCallCount = 0;
  int pullCallCount = 0;

  SyncPullResult<Task> nextPullResult =
      SyncPullResult<Task>(upserts: [], deletedIds: []);

  Object? pushError;

  @override
  Future<List<Task>> push(List<Task> entities) async {
    pushCallCount++;
    if (pushError != null) throw pushError!;
    pushedEntities.addAll(entities);
    return entities;
  }

  @override
  Future<void> pushDeletes(List<Object> ids) async {
    pushCallCount++;
    if (pushError != null) throw pushError!;
    pushedDeletes.addAll(ids);
  }

  @override
  Future<SyncPullResult<Task>> pull({DateTime? since}) async {
    pullCallCount++;
    return nextPullResult;
  }
}

// -- Tests --

void main() {
  // -- OfflineQueue tests (uses raw RelaxDatabase) --

  group('OfflineQueue', () {
    late RelaxDatabase rawDb;
    late OfflineQueue queue;

    setUp(() async {
      rawDb = RelaxDatabase(NativeDatabase.memory());
      queue = OfflineQueue(rawDb);
      await queue.init();
    });

    tearDown(() async {
      await rawDb.close();
    });

    test('enqueue and retrieve pending operations', () async {
      await queue.enqueue(SyncOperation(
        id: 'op1',
        tableName: 'tasks',
        type: SyncOperationType.add,
        entityId: '1',
        data: {'id': '1', 'title': 'Test', 'done': false},
        createdAt: DateTime.now(),
      ));

      final pending = await queue.getPending('tasks');
      expect(pending.length, 1);
      expect(pending.first.entityId, '1');
      expect(pending.first.type, SyncOperationType.add);
    });

    test('complete removes operation', () async {
      await queue.enqueue(SyncOperation(
        id: 'op1',
        tableName: 'tasks',
        type: SyncOperationType.add,
        entityId: '1',
        createdAt: DateTime.now(),
      ));

      await queue.complete('op1');
      final pending = await queue.getPending('tasks');
      expect(pending, isEmpty);
    });

    test('getAllPending returns ops across tables', () async {
      await queue.enqueue(SyncOperation(
        id: 'op1',
        tableName: 'tasks',
        type: SyncOperationType.add,
        entityId: '1',
        createdAt: DateTime.now(),
      ));
      await queue.enqueue(SyncOperation(
        id: 'op2',
        tableName: 'other',
        type: SyncOperationType.update,
        entityId: '2',
        createdAt: DateTime.now(),
      ));

      final all = await queue.getAllPending();
      expect(all.length, 2);
    });

    test('clear removes all operations', () async {
      await queue.enqueue(SyncOperation(
        id: 'op1',
        tableName: 'tasks',
        type: SyncOperationType.add,
        entityId: '1',
        createdAt: DateTime.now(),
      ));
      await queue.clear();
      expect(await queue.getAllPending(), isEmpty);
    });

    test('data round-trips through JSON serialization', () async {
      final data = {'id': '1', 'title': 'JSON test', 'done': true};
      await queue.enqueue(SyncOperation(
        id: 'op1',
        tableName: 'tasks',
        type: SyncOperationType.add,
        entityId: '1',
        data: data,
        createdAt: DateTime(2024, 6, 15),
      ));

      final pending = await queue.getPending('tasks');
      expect(pending.first.data, data);
      expect(pending.first.createdAt, DateTime(2024, 6, 15));
    });
  });

  // -- SyncEngine tests --

  group('SyncEngine', () {
    late RelaxDB db;
    late SyncEngine engine;
    late MockSyncAdapter adapter;

    setUp(() async {
      db = await RelaxDB.openInMemory(schemas: [taskSchema]);
      engine = await db.sync;
      adapter = MockSyncAdapter();
      engine.register(SyncConfig<Task>(
        schema: taskSchema,
        adapter: adapter,
      ));
    });

    tearDown(() async {
      await db.close();
    });

    test('queueOperation stores operation in queue', () async {
      await engine.queueOperation(
        tableName: 'tasks',
        type: SyncOperationType.add,
        entityId: '1',
        data: {'id': '1', 'title': 'Test', 'done': false},
      );

      expect(await engine.pendingCount(), greaterThan(0));
    });

    test('syncTable pushes pending operations', () async {
      // Queue an operation directly on the engine (bypassing collection).
      await engine.queueOperation(
        tableName: 'tasks',
        type: SyncOperationType.add,
        entityId: '1',
        data: {'id': '1', 'title': 'Push me', 'done': false},
      );

      await engine.syncTable('tasks');

      expect(adapter.pushedEntities.length, 1);
      expect(adapter.pushedEntities.first.title, 'Push me');
      expect(await engine.pendingCount(), 0);
    });

    test('syncTable pushes delete operations', () async {
      await engine.queueOperation(
        tableName: 'tasks',
        type: SyncOperationType.delete,
        entityId: '42',
      );

      await engine.syncTable('tasks');

      expect(adapter.pushedDeletes, contains('42'));
    });

    test('syncTable pulls remote changes into local DB', () async {
      adapter.nextPullResult = SyncPullResult<Task>(
        upserts: [Task(id: 'remote1', title: 'From server')],
        deletedIds: [],
      );

      await engine.syncTable('tasks');

      final tasks = db.collection<Task>();
      final result = await tasks.get('remote1');
      expect(result, isNotNull);
      expect(result!.title, 'From server');
    });

    test('pull with conflict uses remoteWins by default', () async {
      // Use a separate DB without sync to add local data without queuing.
      final db2 = await RelaxDB.openInMemory(schemas: [taskSchema]);
      await db2.collection<Task>().add(Task(id: '1', title: 'Local version'));

      // Set up engine on db2.
      final engine2 = await db2.sync;
      final adapter2 = MockSyncAdapter();
      adapter2.nextPullResult = SyncPullResult<Task>(
        upserts: [Task(id: '1', title: 'Remote version')],
        deletedIds: [],
      );
      engine2.register(SyncConfig<Task>(
        schema: taskSchema,
        adapter: adapter2,
      ));

      await engine2.syncTable('tasks');

      final result = await db2.collection<Task>().get('1');
      expect(result!.title, 'Remote version');

      await db2.close();
    });

    test('pull with localWins resolver keeps local data', () async {
      final db2 = await RelaxDB.openInMemory(schemas: [taskSchema]);
      await db2.collection<Task>().add(Task(id: '1', title: 'Local version'));

      final engine2 = await db2.sync;
      final adapter2 = MockSyncAdapter();
      adapter2.nextPullResult = SyncPullResult<Task>(
        upserts: [Task(id: '1', title: 'Remote version')],
        deletedIds: [],
      );
      engine2.register(SyncConfig<Task>(
        schema: taskSchema,
        adapter: adapter2,
        conflictResolver: ConflictResolver.localWins<Task>(),
      ));

      await engine2.syncTable('tasks');

      final result = await db2.collection<Task>().get('1');
      expect(result!.title, 'Local version');

      await db2.close();
    });

    test('pull deletes remove local entities', () async {
      final db2 = await RelaxDB.openInMemory(schemas: [taskSchema]);
      await db2.collection<Task>().add(Task(id: '1', title: 'To be deleted'));

      final engine2 = await db2.sync;
      final adapter2 = MockSyncAdapter();
      adapter2.nextPullResult = SyncPullResult<Task>(
        upserts: [],
        deletedIds: ['1'],
      );
      engine2.register(SyncConfig<Task>(
        schema: taskSchema,
        adapter: adapter2,
      ));

      await engine2.syncTable('tasks');

      expect(await db2.collection<Task>().get('1'), isNull);

      await db2.close();
    });

    test('status stream emits syncing then synced', () async {
      final statuses = <SyncStatus>[];
      engine.status.listen(statuses.add);

      await engine.syncTable('tasks');
      await Future.delayed(Duration(milliseconds: 50));

      expect(statuses, contains(SyncStatus.syncing));
      expect(statuses, contains(SyncStatus.synced));
    });

    test('connectivity offline→online triggers sync', () async {
      final controller = StreamController<bool>.broadcast();
      engine.connectivityStream = controller.stream;

      // Go offline.
      controller.add(false);
      await Future.delayed(Duration(milliseconds: 20));

      // Queue while offline.
      await engine.queueOperation(
        tableName: 'tasks',
        type: SyncOperationType.add,
        entityId: '1',
        data: {'id': '1', 'title': 'Queued offline', 'done': false},
      );

      // Go online — should trigger sync.
      controller.add(true);
      await Future.delayed(Duration(milliseconds: 200));

      expect(adapter.pushCallCount, greaterThan(0));
      expect(adapter.pushedEntities.first.title, 'Queued offline');

      await controller.close();
    });

    test('collection.add queues sync operation', () async {
      final tasks = db.collection<Task>();
      await tasks.add(Task(id: '1', title: 'Auto queued'));

      expect(await engine.pendingCount(), greaterThan(0));

      // Sync to verify the queued operation is valid.
      await engine.syncTable('tasks');
      expect(adapter.pushedEntities.any((t) => t.title == 'Auto queued'), isTrue);
    });
  });

  // -- ConflictResolver tests --

  group('ConflictResolver', () {
    test('remoteWins returns remote', () {
      final resolver = ConflictResolver.remoteWins<Task>();
      final result = resolver.resolve(
        Task(id: '1', title: 'local'),
        Task(id: '1', title: 'remote'),
      );
      expect(result.title, 'remote');
    });

    test('localWins returns local', () {
      final resolver = ConflictResolver.localWins<Task>();
      final result = resolver.resolve(
        Task(id: '1', title: 'local'),
        Task(id: '1', title: 'remote'),
      );
      expect(result.title, 'local');
    });

    test('custom resolver applies custom logic', () {
      final resolver = ConflictResolver<Task>.custom((local, remote) {
        return Task(id: local.id, title: '${local.title}+${remote.title}');
      });
      final result = resolver.resolve(
        Task(id: '1', title: 'A'),
        Task(id: '1', title: 'B'),
      );
      expect(result.title, 'A+B');
    });
  });
}
