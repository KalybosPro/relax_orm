import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relax_orm/relax_orm.dart';

void main() {
  group('RelaxOrmJson', () {
    test('encodes and decodes nested JSON structures', () {
      final encoded = RelaxOrmJson.encode({
        'name': 'Alice',
        'tags': ['admin', 'editor'],
        'profile': {'active': true},
      });

      final decoded = RelaxOrmJson.asMap(RelaxOrmJson.decode(encoded));
      expect(decoded['name'], 'Alice');
      expect(RelaxOrmJson.asList(decoded['tags']), ['admin', 'editor']);
      expect(RelaxOrmJson.asMap(decoded['profile'])['active'], isTrue);
    });

    test('round-trips bytes through base64 helpers', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final encoded = RelaxOrmJson.bytesToBase64(bytes);
      final decoded = RelaxOrmJson.base64ToBytes(encoded);

      expect(decoded, bytes);
    });
  });
}
