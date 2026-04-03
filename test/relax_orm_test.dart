import 'package:flutter_test/flutter_test.dart';
import 'package:relax_orm/relax_orm.dart';

// -- Test model --

class User {
  final String id;
  final String name;
  final int age;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    required this.age,
    required this.createdAt,
  });

  @override
  bool operator ==(Object other) =>
      other is User && other.id == id && other.name == name && other.age == age;

  @override
  int get hashCode => Object.hash(id, name, age);

  @override
  String toString() => 'User(id: $id, name: $name, age: $age)';
}

final userSchema = TableSchema<User>(
  tableName: 'users',
  columns: [
    ColumnDef.text('id', isPrimaryKey: true),
    ColumnDef.text('name'),
    ColumnDef.integer('age'),
    ColumnDef.dateTime('created_at'),
  ],
  fromMap: (map) => User(
    id: map['id'] as String,
    name: map['name'] as String,
    age: map['age'] as int,
    createdAt: map['created_at'] as DateTime,
  ),
  toMap: (user) => {
    'id': user.id,
    'name': user.name,
    'age': user.age,
    'created_at': user.createdAt,
  },
);

// -- Schema tests --

void main() {
  group('TableSchema', () {
    test('generates correct CREATE TABLE SQL', () {
      final sql = userSchema.toCreateTableSql();
      expect(sql, contains('CREATE TABLE IF NOT EXISTS users'));
      expect(sql, contains('id TEXT PRIMARY KEY'));
      expect(sql, contains('name TEXT NOT NULL'));
      expect(sql, contains('age INTEGER NOT NULL'));
      expect(sql, contains('created_at INTEGER NOT NULL'));
    });

    test('identifies primary key', () {
      expect(userSchema.primaryKey.name, 'id');
    });

    test('converts entity to SQL row', () {
      final user = User(
        id: '1',
        name: 'Alice',
        age: 30,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final row = userSchema.entityToRow(user);
      expect(row['id'], '1');
      expect(row['name'], 'Alice');
      expect(row['age'], 30);
      expect(row['created_at'], 1000); // milliseconds
    });

    test('converts SQL row back to entity', () {
      final row = <String, dynamic>{
        'id': '1',
        'name': 'Alice',
        'age': 30,
        'created_at': 1000,
      };
      final user = userSchema.rowToEntity(row);
      expect(user.id, '1');
      expect(user.name, 'Alice');
      expect(user.age, 30);
      expect(user.createdAt, DateTime.fromMillisecondsSinceEpoch(1000));
    });

    test('extracts primary key value from entity', () {
      final user = User(
        id: 'abc',
        name: 'Bob',
        age: 25,
        createdAt: DateTime.now(),
      );
      expect(userSchema.getPrimaryKeyValue(user), 'abc');
    });
  });

  group('ColumnDef', () {
    test('boolean toSql/fromSql', () {
      const col = ColumnDef.boolean('active');
      expect(col.toSql(true), 1);
      expect(col.toSql(false), 0);
      expect(col.fromSql(1), true);
      expect(col.fromSql(0), false);
    });

    test('dateTime toSql/fromSql', () {
      const col = ColumnDef.dateTime('ts');
      final dt = DateTime(2024, 1, 15);
      final ms = dt.millisecondsSinceEpoch;
      expect(col.toSql(dt), ms);
      expect(col.fromSql(ms), dt);
    });

    test('null passthrough', () {
      const col = ColumnDef.text('x');
      expect(col.toSql(null), null);
      expect(col.fromSql(null), null);
    });

    test('sqlType mappings', () {
      expect(const ColumnDef.text('x').sqlType, 'TEXT');
      expect(const ColumnDef.integer('x').sqlType, 'INTEGER');
      expect(const ColumnDef.real('x').sqlType, 'REAL');
      expect(const ColumnDef.boolean('x').sqlType, 'INTEGER');
      expect(const ColumnDef.dateTime('x').sqlType, 'INTEGER');
      expect(const ColumnDef.blob('x').sqlType, 'BLOB');
    });
  });

  group('Annotations', () {
    test('RelaxTable stores optional name', () {
      const t1 = RelaxTable();
      const t2 = RelaxTable(name: 'custom');
      expect(t1.name, null);
      expect(t2.name, 'custom');
    });

    test('Column stores options', () {
      const c = Column(name: 'col_name', nullable: true, defaultValue: '0');
      expect(c.name, 'col_name');
      expect(c.nullable, true);
      expect(c.defaultValue, '0');
    });

    test('shorthand constants exist', () {
      // Just verifying they compile and are accessible.
      expect(relaxTable, isA<RelaxTable>());
      expect(primaryKey, isA<PrimaryKey>());
      expect(ignore, isA<Ignore>());
    });
  });
}
