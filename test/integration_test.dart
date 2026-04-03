import 'package:flutter_test/flutter_test.dart';
import 'package:relax_orm/relax_orm.dart';

// -- Test model --

class User {
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

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.id == id &&
      other.name == name &&
      other.age == age &&
      other.active == active;

  @override
  int get hashCode => Object.hash(id, name, age, active);

  @override
  String toString() => 'User(id: $id, name: $name, age: $age, active: $active)';

  User copyWith({String? name, int? age, bool? active}) => User(
        id: id,
        name: name ?? this.name,
        age: age ?? this.age,
        active: active ?? this.active,
        createdAt: createdAt,
      );
}

final userSchema = TableSchema<User>(
  tableName: 'users',
  columns: [
    ColumnDef.text('id', isPrimaryKey: true),
    ColumnDef.text('name'),
    ColumnDef.integer('age'),
    ColumnDef.boolean('active'),
    ColumnDef.dateTime('created_at'),
  ],
  fromMap: (map) => User(
    id: map['id'] as String,
    name: map['name'] as String,
    age: map['age'] as int,
    active: map['active'] as bool,
    createdAt: map['created_at'] as DateTime,
  ),
  toMap: (user) => {
    'id': user.id,
    'name': user.name,
    'age': user.age,
    'active': user.active,
    'created_at': user.createdAt,
  },
);

// -- Helpers --

User _makeUser(String id, {String name = 'Test', int age = 25, bool active = true}) =>
    User(id: id, name: name, age: age, active: active, createdAt: DateTime(2024));

void main() {
  late RelaxDB db;
  late Collection<User> users;

  setUp(() async {
    db = await RelaxDB.openInMemory(schemas: [userSchema]);
    users = db.collection<User>();
  });

  tearDown(() async {
    await db.close();
  });

  // -- CRUD --

  group('add / get', () {
    test('adds and retrieves an entity by primary key', () async {
      final user = _makeUser('1', name: 'Alice', age: 30);
      await users.add(user);

      final result = await users.get('1');
      expect(result, isNotNull);
      expect(result!.id, '1');
      expect(result.name, 'Alice');
      expect(result.age, 30);
    });

    test('returns null for non-existent id', () async {
      final result = await users.get('missing');
      expect(result, isNull);
    });
  });

  group('getAll', () {
    test('returns empty list on empty table', () async {
      final all = await users.getAll();
      expect(all, isEmpty);
    });

    test('returns all inserted entities', () async {
      await users.add(_makeUser('1', name: 'Alice'));
      await users.add(_makeUser('2', name: 'Bob'));
      await users.add(_makeUser('3', name: 'Charlie'));

      final all = await users.getAll();
      expect(all.length, 3);
      expect(all.map((u) => u.name), containsAll(['Alice', 'Bob', 'Charlie']));
    });
  });

  group('addAll', () {
    test('batch inserts multiple entities', () async {
      final batch = [
        _makeUser('1', name: 'Alice'),
        _makeUser('2', name: 'Bob'),
        _makeUser('3', name: 'Charlie'),
      ];
      await users.addAll(batch);

      expect(await users.count(), 3);
      expect((await users.get('2'))!.name, 'Bob');
    });
  });

  group('update', () {
    test('updates an existing entity', () async {
      await users.add(_makeUser('1', name: 'Alice', age: 25));
      final updated = await users.update(_makeUser('1', name: 'Alice Updated', age: 26));

      expect(updated, isTrue);
      final result = await users.get('1');
      expect(result!.name, 'Alice Updated');
      expect(result.age, 26);
    });

    test('returns false for non-existent entity', () async {
      final updated = await users.update(_makeUser('missing', name: 'Ghost'));
      expect(updated, isFalse);
    });
  });

  group('upsert', () {
    test('inserts when entity does not exist', () async {
      await users.upsert(_makeUser('1', name: 'Alice'));
      expect(await users.count(), 1);
      expect((await users.get('1'))!.name, 'Alice');
    });

    test('updates when entity already exists', () async {
      await users.add(_makeUser('1', name: 'Alice'));
      await users.upsert(_makeUser('1', name: 'Alice V2'));

      expect(await users.count(), 1);
      expect((await users.get('1'))!.name, 'Alice V2');
    });
  });

  group('delete', () {
    test('deletes an existing entity', () async {
      await users.add(_makeUser('1', name: 'Alice'));
      final deleted = await users.delete('1');

      expect(deleted, isTrue);
      expect(await users.get('1'), isNull);
    });

    test('returns false for non-existent id', () async {
      final deleted = await users.delete('missing');
      expect(deleted, isFalse);
    });
  });

  group('deleteAll', () {
    test('removes all entities', () async {
      await users.addAll([
        _makeUser('1'),
        _makeUser('2'),
        _makeUser('3'),
      ]);
      expect(await users.count(), 3);

      await users.deleteAll();
      expect(await users.count(), 0);
    });
  });

  group('count', () {
    test('returns 0 on empty table', () async {
      expect(await users.count(), 0);
    });

    test('returns correct count after operations', () async {
      await users.add(_makeUser('1'));
      await users.add(_makeUser('2'));
      expect(await users.count(), 2);

      await users.delete('1');
      expect(await users.count(), 1);
    });
  });

  // -- Type conversion round-trips --

  group('type conversions', () {
    test('boolean values round-trip correctly', () async {
      await users.add(_makeUser('1', active: true));
      await users.add(_makeUser('2', active: false));

      expect((await users.get('1'))!.active, isTrue);
      expect((await users.get('2'))!.active, isFalse);
    });

    test('dateTime values round-trip correctly', () async {
      final dt = DateTime(2024, 6, 15, 10, 30);
      final user = User(id: '1', name: 'Test', age: 20, active: true, createdAt: dt);
      await users.add(user);

      final result = await users.get('1');
      expect(result!.createdAt, dt);
    });
  });

  // -- Streams --

  group('watchAll', () {
    test('emits initial state and updates', () async {
      await users.add(_makeUser('1', name: 'Alice'));

      final stream = users.watchAll();
      final first = await stream.first;
      expect(first.length, 1);
      expect(first.first.name, 'Alice');
    });

    test('re-emits after insert', () async {
      final stream = users.watchAll();

      // Set up expectation before performing the insert.
      final expectation = expectLater(
        stream,
        emitsInOrder([
          // First emission: empty table.
          predicate<List<User>>((list) => list.isEmpty),
          // Second emission after insert.
          predicate<List<User>>((list) => list.length == 1 && list.first.name == 'Alice'),
        ]),
      );

      // Give the stream time to subscribe and emit initial value.
      await Future.delayed(Duration(milliseconds: 50));
      await users.add(_makeUser('1', name: 'Alice'));

      await expectation;
    });
  });

  group('watchOne', () {
    test('emits the entity when it exists', () async {
      await users.add(_makeUser('1', name: 'Alice'));

      final result = await users.watchOne('1').first;
      expect(result, isNotNull);
      expect(result!.name, 'Alice');
    });

    test('emits null when entity does not exist', () async {
      final result = await users.watchOne('missing').first;
      expect(result, isNull);
    });
  });
}
