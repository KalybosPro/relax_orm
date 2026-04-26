import 'dart:convert';
import 'dart:typed_data';

/// Small JSON helpers used by generated RelaxORM schemas.
abstract final class RelaxOrmJson {
  static String? encode(Object? value) {
    if (value == null) return null;
    return jsonEncode(value);
  }

  static Object? decode(Object? value) {
    if (value == null) return null;
    if (value is String) return jsonDecode(value);
    return value;
  }

  static Map<String, dynamic> asMap(Object? value) {
    final map = value as Map;
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<dynamic> asList(Object? value) {
    return (value as List).cast<dynamic>();
  }

  static String bytesToBase64(Uint8List value) {
    return base64Encode(value);
  }

  static Uint8List base64ToBytes(String value) {
    return base64Decode(value);
  }
}
