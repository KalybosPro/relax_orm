/// Supported column types in RelaxORM.
enum ColumnType {
  text,
  integer,
  real,
  boolean,
  dateTime,
  blob,
}

/// Defines a column in a [TableSchema].
class ColumnDef {
  final String name;
  final ColumnType type;
  final bool isPrimaryKey;
  final bool isNullable;
  final String? defaultValue;

  const ColumnDef({
    required this.name,
    required this.type,
    this.isPrimaryKey = false,
    this.isNullable = false,
    this.defaultValue,
  });

  // -- Convenience constructors --

  const ColumnDef.text(
    this.name, {
    this.isPrimaryKey = false,
    this.isNullable = false,
    this.defaultValue,
  }) : type = ColumnType.text;

  const ColumnDef.integer(
    this.name, {
    this.isPrimaryKey = false,
    this.isNullable = false,
    this.defaultValue,
  }) : type = ColumnType.integer;

  const ColumnDef.real(
    this.name, {
    this.isPrimaryKey = false,
    this.isNullable = false,
    this.defaultValue,
  }) : type = ColumnType.real;

  const ColumnDef.boolean(
    this.name, {
    this.isPrimaryKey = false,
    this.isNullable = false,
    this.defaultValue,
  }) : type = ColumnType.boolean;

  const ColumnDef.dateTime(
    this.name, {
    this.isPrimaryKey = false,
    this.isNullable = false,
    this.defaultValue,
  }) : type = ColumnType.dateTime;

  const ColumnDef.blob(
    this.name, {
    this.isPrimaryKey = false,
    this.isNullable = false,
    this.defaultValue,
  }) : type = ColumnType.blob;

  /// Returns the SQL type string for this column.
  String get sqlType {
    switch (type) {
      case ColumnType.text:
        return 'TEXT';
      case ColumnType.integer:
        return 'INTEGER';
      case ColumnType.real:
        return 'REAL';
      case ColumnType.boolean:
        return 'INTEGER';
      case ColumnType.dateTime:
        return 'INTEGER';
      case ColumnType.blob:
        return 'BLOB';
    }
  }

  /// Converts a Dart value to its SQL representation.
  Object? toSql(Object? value) {
    if (value == null) return null;
    switch (type) {
      case ColumnType.boolean:
        return (value as bool) ? 1 : 0;
      case ColumnType.dateTime:
        return (value as DateTime).millisecondsSinceEpoch;
      default:
        return value;
    }
  }

  /// Converts a SQL value back to its Dart representation.
  Object? fromSql(Object? value) {
    if (value == null) return null;
    switch (type) {
      case ColumnType.boolean:
        return value == 1;
      case ColumnType.dateTime:
        return DateTime.fromMillisecondsSinceEpoch(value as int);
      default:
        return value;
    }
  }
}
