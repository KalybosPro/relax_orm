import 'package:drift/drift.dart';

import '../database/relax_database.dart';
import '../schema/table_schema.dart';

/// Comparison operators for WHERE clauses.
enum FilterOp {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEquals,
  lessThan,
  lessThanOrEquals,
  like,
  contains,
  startsWith,
  endsWith,
  isIn,
  isNull,
  isNotNull,
}

/// A single filter condition.
class Filter {
  final String column;
  final FilterOp op;
  final Object? value;

  const Filter(this.column, this.op, [this.value]);

  /// Generates the SQL WHERE fragment and collects bind arguments.
  String toSql(List<Object?> args) {
    switch (op) {
      case FilterOp.equals:
        args.add(value);
        return '$column = ?';
      case FilterOp.notEquals:
        args.add(value);
        return '$column != ?';
      case FilterOp.greaterThan:
        args.add(value);
        return '$column > ?';
      case FilterOp.greaterThanOrEquals:
        args.add(value);
        return '$column >= ?';
      case FilterOp.lessThan:
        args.add(value);
        return '$column < ?';
      case FilterOp.lessThanOrEquals:
        args.add(value);
        return '$column <= ?';
      case FilterOp.like:
        args.add(value);
        return '$column LIKE ?';
      case FilterOp.contains:
        args.add('%$value%');
        return '$column LIKE ?';
      case FilterOp.startsWith:
        args.add('$value%');
        return '$column LIKE ?';
      case FilterOp.endsWith:
        args.add('%$value');
        return '$column LIKE ?';
      case FilterOp.isIn:
        final list = value as List;
        final placeholders = list.map((_) => '?').join(', ');
        args.addAll(list);
        return '$column IN ($placeholders)';
      case FilterOp.isNull:
        return '$column IS NULL';
      case FilterOp.isNotNull:
        return '$column IS NOT NULL';
    }
  }
}

/// Sort direction for ORDER BY clauses.
class OrderByClause {
  final String column;
  final bool descending;

  const OrderByClause(this.column, {this.descending = false});

  String toSql() => '$column ${descending ? 'DESC' : 'ASC'}';
}

/// A fluent query builder for [Collection].
///
/// ```dart
/// final results = await users
///     .query()
///     .where('age', greaterThan: 18)
///     .where('name', contains: 'John')
///     .orderBy('created_at', desc: true)
///     .limit(10)
///     .find();
/// ```
class QueryBuilder<T> {
  final RelaxDatabase _db;
  final TableSchema<T> _schema;
  final List<Filter> _filters = [];
  final List<OrderByClause> _orderBy = [];
  int? _limit;
  int? _offset;

  QueryBuilder(this._db, this._schema);

  // -- Filters --

  /// Adds an equality filter: `column = value`.
  QueryBuilder<T> where(
    String column, {
    Object? equals,
    Object? notEquals,
    Object? greaterThan,
    Object? greaterThanOrEquals,
    Object? lessThan,
    Object? lessThanOrEquals,
    String? contains,
    String? startsWith,
    String? endsWith,
    String? like,
    List<Object>? isIn,
    bool? isNull,
  }) {
    if (equals != null) _filters.add(Filter(column, FilterOp.equals, equals));
    if (notEquals != null) _filters.add(Filter(column, FilterOp.notEquals, notEquals));
    if (greaterThan != null) _filters.add(Filter(column, FilterOp.greaterThan, greaterThan));
    if (greaterThanOrEquals != null) _filters.add(Filter(column, FilterOp.greaterThanOrEquals, greaterThanOrEquals));
    if (lessThan != null) _filters.add(Filter(column, FilterOp.lessThan, lessThan));
    if (lessThanOrEquals != null) _filters.add(Filter(column, FilterOp.lessThanOrEquals, lessThanOrEquals));
    if (contains != null) _filters.add(Filter(column, FilterOp.contains, contains));
    if (startsWith != null) _filters.add(Filter(column, FilterOp.startsWith, startsWith));
    if (endsWith != null) _filters.add(Filter(column, FilterOp.endsWith, endsWith));
    if (like != null) _filters.add(Filter(column, FilterOp.like, like));
    if (isIn != null) _filters.add(Filter(column, FilterOp.isIn, isIn));
    if (isNull == true) _filters.add(Filter(column, FilterOp.isNull));
    if (isNull == false) _filters.add(Filter(column, FilterOp.isNotNull));
    return this;
  }

  // -- Sorting --

  /// Adds an ORDER BY clause.
  QueryBuilder<T> orderBy(String column, {bool desc = false}) {
    _orderBy.add(OrderByClause(column, descending: desc));
    return this;
  }

  // -- Pagination --

  /// Limits the number of results.
  QueryBuilder<T> limit(int count) {
    _limit = count;
    return this;
  }

  /// Skips the first [count] results.
  QueryBuilder<T> offset(int count) {
    _offset = count;
    return this;
  }

  // -- Execution --

  /// Executes the query and returns the matching entities.
  Future<List<T>> find() async {
    final args = <Object?>[];
    final sql = _buildSql(args);

    final results = await _db.customSelect(
      sql,
      variables: args.map((v) => Variable(v)).toList(),
    ).get();

    return results.map((row) => _schema.rowToEntity(row.data)).toList();
  }

  /// Executes the query and returns the first match, or `null`.
  Future<T?> findOne() async {
    _limit = 1;
    final results = await find();
    return results.isEmpty ? null : results.first;
  }

  /// Returns a reactive stream of the query results.
  ///
  /// Re-emits every time the underlying table is modified.
  Stream<List<T>> watch() {
    final args = <Object?>[];
    final sql = _buildSql(args);

    return _db
        .customSelect(
          sql,
          variables: args.map((v) => Variable(v)).toList(),
          readsFrom: {_db.tableRef(_schema.tableName)},
        )
        .watch()
        .map((rows) => rows.map((row) => _schema.rowToEntity(row.data)).toList());
  }

  /// Returns the count of rows matching the filters.
  Future<int> count() async {
    final args = <Object?>[];
    final whereSql = _buildWhere(args);

    final sql = StringBuffer('SELECT COUNT(*) as c FROM ${_schema.tableName}');
    if (whereSql.isNotEmpty) sql.write(' WHERE $whereSql');

    final results = await _db.customSelect(
      sql.toString(),
      variables: args.map((v) => Variable(v)).toList(),
    ).get();

    return results.first.data['c'] as int;
  }

  // -- SQL generation --

  String _buildSql(List<Object?> args) {
    final sql = StringBuffer('SELECT * FROM ${_schema.tableName}');

    final whereSql = _buildWhere(args);
    if (whereSql.isNotEmpty) sql.write(' WHERE $whereSql');

    if (_orderBy.isNotEmpty) {
      sql.write(' ORDER BY ${_orderBy.map((o) => o.toSql()).join(', ')}');
    }

    if (_limit != null) sql.write(' LIMIT $_limit');
    if (_offset != null) sql.write(' OFFSET $_offset');

    return sql.toString();
  }

  String _buildWhere(List<Object?> args) {
    if (_filters.isEmpty) return '';
    return _filters.map((f) => f.toSql(args)).join(' AND ');
  }
}
