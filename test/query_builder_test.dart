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
  String toString() => 'User(id: $id, name: $name, age: $age, active: $active)';
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

// -- Seed data --

final _seedUsers = [
  User(id: '1', name: 'Alice', age: 30, active: true, createdAt: DateTime(2024, 1, 1)),
  User(id: '2', name: 'Bob', age: 17, active: true, createdAt: DateTime(2024, 2, 1)),
  User(id: '3', name: 'Charlie', age: 25, active: false, createdAt: DateTime(2024, 3, 1)),
  User(id: '4', name: 'Diana', age: 42, active: true, createdAt: DateTime(2024, 4, 1)),
  User(id: '5', name: 'Eve', age: 19, active: false, createdAt: DateTime(2024, 5, 1)),
];

void main() {
  late RelaxDB db;
  late Collection<User> users;

  setUp(() async {
    db = await RelaxDB.openInMemory(schemas: [userSchema]);
    users = db.collection<User>();
    await users.addAll(_seedUsers);
  });

  tearDown(() async {
    await db.close();
  });

  // -- Equality --

  group('where equals', () {
    test('filters by exact value', () async {
      final results = await users.query().where('name', equals: 'Alice').find();
      expect(results.length, 1);
      expect(results.first.name, 'Alice');
    });

    test('returns empty for no match', () async {
      final results = await users.query().where('name', equals: 'Nobody').find();
      expect(results, isEmpty);
    });
  });

  group('where notEquals', () {
    test('excludes matching rows', () async {
      final results = await users.query().where('name', notEquals: 'Alice').find();
      expect(results.length, 4);
      expect(results.every((u) => u.name != 'Alice'), isTrue);
    });
  });

  // -- Comparisons --

  group('where greaterThan / lessThan', () {
    test('greaterThan filters correctly', () async {
      final results = await users.query().where('age', greaterThan: 25).find();
      expect(results.length, 2); // Alice(30), Diana(42)
      expect(results.every((u) => u.age > 25), isTrue);
    });

    test('greaterThanOrEquals includes boundary', () async {
      final results = await users.query().where('age', greaterThanOrEquals: 25).find();
      expect(results.length, 3); // Alice(30), Charlie(25), Diana(42)
    });

    test('lessThan filters correctly', () async {
      final results = await users.query().where('age', lessThan: 20).find();
      expect(results.length, 2); // Bob(17), Eve(19)
    });

    test('lessThanOrEquals includes boundary', () async {
      final results = await users.query().where('age', lessThanOrEquals: 19).find();
      expect(results.length, 2); // Bob(17), Eve(19)
    });
  });

  // -- String matching --

  group('where contains / startsWith / endsWith', () {
    test('contains matches substring', () async {
      final results = await users.query().where('name', contains: 'li').find();
      expect(results.length, 2); // Alice, Charlie
    });

    test('startsWith matches prefix', () async {
      final results = await users.query().where('name', startsWith: 'Ch').find();
      expect(results.length, 1);
      expect(results.first.name, 'Charlie');
    });

    test('endsWith matches suffix', () async {
      final results = await users.query().where('name', endsWith: 'e').find();
      // Alice, Charlie, Eve
      expect(results.length, 3);
    });
  });

  // -- IN --

  group('where isIn', () {
    test('matches any value in list', () async {
      final results = await users.query().where('name', isIn: ['Alice', 'Bob', 'Eve']).find();
      expect(results.length, 3);
    });
  });

  // -- NULL --

  group('where isNull', () {
    // All our test data is non-null, so isNull should return nothing.
    test('isNull returns empty for non-null column', () async {
      final results = await users.query().where('name', isNull: true).find();
      expect(results, isEmpty);
    });

    test('isNotNull returns all for non-null column', () async {
      final results = await users.query().where('name', isNull: false).find();
      expect(results.length, 5);
    });
  });

  // -- Combined filters --

  group('multiple filters (AND)', () {
    test('combines two conditions', () async {
      final results = await users
          .query()
          .where('age', greaterThan: 18)
          .where('active', equals: 1) // boolean stored as int
          .find();
      // Alice(30, active), Diana(42, active)
      expect(results.length, 2);
      expect(results.every((u) => u.age > 18 && u.active), isTrue);
    });
  });

  // -- ORDER BY --

  group('orderBy', () {
    test('sorts ascending by default', () async {
      final results = await users.query().orderBy('age').find();
      final ages = results.map((u) => u.age).toList();
      expect(ages, [17, 19, 25, 30, 42]);
    });

    test('sorts descending', () async {
      final results = await users.query().orderBy('age', desc: true).find();
      final ages = results.map((u) => u.age).toList();
      expect(ages, [42, 30, 25, 19, 17]);
    });

    test('supports multiple orderBy', () async {
      final results = await users
          .query()
          .orderBy('active') // false(0) first, then true(1)
          .orderBy('age')
          .find();
      // inactive sorted by age: Charlie(25), Eve(19) → Eve(19), Charlie(25)
      // active sorted by age: Bob(17), Alice(30), Diana(42)
      expect(results.first.name, 'Eve');
      expect(results.last.name, 'Diana');
    });
  });

  // -- LIMIT / OFFSET --

  group('limit / offset', () {
    test('limit restricts result count', () async {
      final results = await users.query().orderBy('age').limit(3).find();
      expect(results.length, 3);
      expect(results.map((u) => u.age).toList(), [17, 19, 25]);
    });

    test('offset skips rows', () async {
      final results = await users.query().orderBy('age').offset(2).limit(2).find();
      expect(results.length, 2);
      expect(results.map((u) => u.age).toList(), [25, 30]);
    });
  });

  // -- findOne --

  group('findOne', () {
    test('returns first match', () async {
      final result = await users.query().where('name', equals: 'Bob').findOne();
      expect(result, isNotNull);
      expect(result!.name, 'Bob');
    });

    test('returns null for no match', () async {
      final result = await users.query().where('name', equals: 'Nobody').findOne();
      expect(result, isNull);
    });
  });

  // -- count --

  group('count', () {
    test('counts all rows without filters', () async {
      final c = await users.query().count();
      expect(c, 5);
    });

    test('counts filtered rows', () async {
      final c = await users.query().where('age', greaterThan: 20).count();
      expect(c, 3); // Alice(30), Charlie(25), Diana(42)
    });
  });

  // -- watch --

  group('watch', () {
    test('emits matching results reactively', () async {
      final stream = users.query().where('age', greaterThan: 40).watch();

      // Initially only Diana(42) matches.
      final first = await stream.first;
      expect(first.length, 1);
      expect(first.first.name, 'Diana');
    });
  });
}
