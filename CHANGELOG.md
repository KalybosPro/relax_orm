## 0.1.0

- Initial release
- **ORM Core**: `RelaxDB`, `Collection<T>` with full CRUD (add, addAll, update, upsert, delete, deleteAll, get, getAll, count)
- **Real-time streams**: `watchAll()`, `watchOne()` with Drift-powered reactive queries
- **Query builder**: fluent API with filters (equals, greaterThan, contains, isIn, isNull...), orderBy, limit, offset
- **Encryption**: transparent SQLite3MultipleCiphers encryption via `encryptionKey` parameter
- **Sync engine**: offline queue, push/pull sync, configurable conflict resolution (remoteWins, localWins, custom)
- **Code generation**: `@RelaxTable`, `@PrimaryKey`, `@Column`, `@Ignore` annotations with automatic schema generation
- **Schema definition**: `TableSchema<T>` with type-safe column definitions and automatic Dart/SQL type conversion
