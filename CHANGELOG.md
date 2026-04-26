## 0.1.4

### Added

- Added public `RelaxOrmJson` helpers for generated schemas that need JSON serialization and deserialization
- Added base64 helpers for `Uint8List` values used inside JSON-backed fields

### Changed

- Exported `src/core/relax_orm_json.dart` from the main `relax_orm.dart` library
- Bumped `relax_orm_generator` to `^0.1.6` to support generated mappings for nested objects and `List<T>` fields

## 0.1.3

- Update dependencies

## 0.1.2

### Added

- Automatic UUID generation for text primary keys when inserting an entity with a null ID

### Changed

- `Collection.add()` now queues the persisted entity after ID generation so sync payloads keep the effective primary key
- Bumped `relax_orm_generator` to `^0.1.2`

### Fixed

- Synced inserts with generated text primary keys now keep database rows and queued operations aligned

## 0.1.1

### Changed

- Annotations (`@RelaxTable`, `@PrimaryKey`, `@Column`, `@Ignore`) are now the single source of truth in this package
- Added `relax_orm_annotations.dart` — lightweight export without Flutter/Drift dependencies, safe for use by code generators and pure-Dart contexts
- SDK constraint is now bounded (`>=3.11.0 <4.0.0`)
- Added `license`, `platforms`, `issue_tracker` metadata to pubspec

### Fixed

- Removed runtime dependency on `relax_orm_generator` — heavy build-time packages (`analyzer`, `source_gen`, `build`) are no longer pulled into the app's dependency tree

## 0.1.0

- Initial release
- **ORM Core**: `RelaxDB`, `Collection<T>` with full CRUD (add, addAll, update, upsert, delete, deleteAll, get, getAll, count)
- **Real-time streams**: `watchAll()`, `watchOne()` with Drift-powered reactive queries
- **Query builder**: fluent API with filters (equals, greaterThan, contains, isIn, isNull...), orderBy, limit, offset
- **Encryption**: transparent SQLite3MultipleCiphers encryption via `encryptionKey` parameter
- **Sync engine**: offline queue, push/pull sync, configurable conflict resolution (remoteWins, localWins, custom)
- **Code generation**: `@RelaxTable`, `@PrimaryKey`, `@Column`, `@Ignore` annotations with automatic schema generation
- **Schema definition**: `TableSchema<T>` with type-safe column definitions and automatic Dart/SQL type conversion
