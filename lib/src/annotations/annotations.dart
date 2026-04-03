/// Marks a class as a RelaxORM table entity.
///
/// Used by the code generator (Phase 2) to produce table schemas automatically.
/// For now (Phase 1a), schemas are defined manually via [TableSchema].
///
/// ```dart
/// @RelaxTable()
/// class User {
///   @PrimaryKey()
///   final String id;
///   final String name;
///   final int age;
///
///   User({required this.id, required this.name, required this.age});
/// }
/// ```
class RelaxTable {
  final String? name;

  const RelaxTable({this.name});
}

/// Marks a field as the primary key of the table.
class PrimaryKey {
  const PrimaryKey();
}

/// Customizes how a field is stored in the database.
class Column {
  /// Override the column name in the database.
  final String? name;

  /// Whether the column accepts null values.
  final bool nullable;

  /// Default value for the column (as SQL expression).
  final String? defaultValue;

  const Column({this.name, this.nullable = false, this.defaultValue});
}

/// Marks a field to be ignored by the ORM.
class Ignore {
  const Ignore();
}

// Shorthand constants for cleaner annotation syntax.
const relaxTable = RelaxTable();
const primaryKey = PrimaryKey();
const ignore = Ignore();
