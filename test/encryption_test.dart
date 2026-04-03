import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:relax_orm/relax_orm.dart';

// -- Test model --

class Note {
  final String id;
  final String content;

  Note({required this.id, required this.content});
}

final noteSchema = TableSchema<Note>(
  tableName: 'notes',
  columns: [
    ColumnDef.text('id', isPrimaryKey: true),
    ColumnDef.text('content'),
  ],
  fromMap: (map) => Note(id: map['id'] as String, content: map['content'] as String),
  toMap: (note) => {'id': note.id, 'content': note.content},
);

/// Whether SQLite3MultipleCiphers is available in this environment.
late bool _cipherAvailable;

Future<bool> _checkCipherAvailable() async {
  final db = await RelaxDB.openInMemory(schemas: [noteSchema]);
  final available = await db.isEncryptionAvailable();
  await db.close();
  return available;
}

void main() {
  setUpAll(() async {
    _cipherAvailable = await _checkCipherAvailable();
    if (!_cipherAvailable) {
      // ignore: avoid_print
      print('⚠ SQLite3MultipleCiphers not available — encryption tests will be skipped.');
    }
  });

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('relax_orm_enc_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // -- Basic API tests (always run) --

  group('encryption API', () {
    test('isEncryptionAvailable returns a bool', () async {
      final db = await RelaxDB.openInMemory(schemas: [noteSchema]);
      final result = await db.isEncryptionAvailable();
      expect(result, isA<bool>());
      await db.close();
    });

    test('unencrypted file-based DB round-trips correctly', () async {
      final file = File('${tempDir.path}/plain.db');

      final db1 = await RelaxDB.openFile(file: file, schemas: [noteSchema]);
      await db1.collection<Note>().add(Note(id: '1', content: 'Public'));
      await db1.close();

      final db2 = await RelaxDB.openFile(file: file, schemas: [noteSchema]);
      final result = await db2.collection<Note>().get('1');
      expect(result!.content, 'Public');
      await db2.close();
    });
  });

  // -- Encrypted file-based tests (require cipher) --

  group('encryption - file-based', () {
    test('data persists and is readable with correct key', () async {
      if (!_cipherAvailable) {
        markTestSkipped('SQLite3MultipleCiphers not available');
        return;
      }

      final file = File('${tempDir.path}/encrypted.db');

      final db1 = await RelaxDB.openFile(
        file: file,
        schemas: [noteSchema],
        encryptionKey: 'my-secret',
      );
      final notes = db1.collection<Note>();
      await notes.add(Note(id: '1', content: 'Persisted secret'));
      await notes.add(Note(id: '2', content: 'Another secret'));
      expect(await notes.count(), 2);
      await db1.close();

      // Reopen with same key — data intact.
      final db2 = await RelaxDB.openFile(
        file: file,
        schemas: [noteSchema],
        encryptionKey: 'my-secret',
      );
      final result = await db2.collection<Note>().get('1');
      expect(result!.content, 'Persisted secret');
      expect(await db2.collection<Note>().count(), 2);
      await db2.close();
    });

    test('wrong key fails to read data', () async {
      if (!_cipherAvailable) {
        markTestSkipped('SQLite3MultipleCiphers not available');
        return;
      }

      final file = File('${tempDir.path}/enc_wrong.db');

      final db1 = await RelaxDB.openFile(
        file: file,
        schemas: [noteSchema],
        encryptionKey: 'correct-key',
      );
      await db1.collection<Note>().add(Note(id: '1', content: 'Secret'));
      await db1.close();

      expect(
        () async {
          final db2 = await RelaxDB.openFile(
            file: file,
            schemas: [noteSchema],
            encryptionKey: 'wrong-key',
          );
          await db2.collection<Note>().getAll();
        },
        throwsA(anything),
      );
    });

    test('no key fails on encrypted DB', () async {
      if (!_cipherAvailable) {
        markTestSkipped('SQLite3MultipleCiphers not available');
        return;
      }

      final file = File('${tempDir.path}/enc_nokey.db');

      final db1 = await RelaxDB.openFile(
        file: file,
        schemas: [noteSchema],
        encryptionKey: 'a-key',
      );
      await db1.collection<Note>().add(Note(id: '1', content: 'Secret'));
      await db1.close();

      expect(
        () async {
          final db2 = await RelaxDB.openFile(file: file, schemas: [noteSchema]);
          await db2.collection<Note>().getAll();
        },
        throwsA(anything),
      );
    });

    test('encrypted file does not contain plaintext', () async {
      if (!_cipherAvailable) {
        markTestSkipped('SQLite3MultipleCiphers not available');
        return;
      }

      final file = File('${tempDir.path}/binary_check.db');

      final db = await RelaxDB.openFile(
        file: file,
        schemas: [noteSchema],
        encryptionKey: 'check-key',
      );
      await db.collection<Note>().add(
            Note(id: '1', content: 'This should be encrypted on disk'),
          );
      await db.close();

      // Raw bytes should NOT contain our plaintext.
      final rawContent = String.fromCharCodes(await file.readAsBytes());
      expect(rawContent.contains('This should be encrypted on disk'), isFalse);
      expect(rawContent.contains('notes'), isFalse);
    });

    test('queries work on encrypted DB', () async {
      if (!_cipherAvailable) {
        markTestSkipped('SQLite3MultipleCiphers not available');
        return;
      }

      final file = File('${tempDir.path}/enc_query.db');

      final db = await RelaxDB.openFile(
        file: file,
        schemas: [noteSchema],
        encryptionKey: 'query-key',
      );

      final notes = db.collection<Note>();
      await notes.addAll([
        Note(id: '1', content: 'Alpha'),
        Note(id: '2', content: 'Beta'),
        Note(id: '3', content: 'Gamma'),
      ]);

      final results = await notes.query().where('content', startsWith: 'A').find();
      expect(results.length, 1);
      expect(results.first.content, 'Alpha');

      await db.close();
    });
  });

  // -- Error handling --

  group('encryption - error handling', () {
    test('throws StateError if cipher not available but key requested', () async {
      if (_cipherAvailable) {
        markTestSkipped('Cipher IS available — this test only runs without it');
        return;
      }

      final file = File('${tempDir.path}/no_cipher.db');
      expect(
        () => RelaxDB.openFile(
          file: file,
          schemas: [noteSchema],
          encryptionKey: 'any-key',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SQLite3MultipleCiphers is not available'),
        )),
      );
    });
  });
}
