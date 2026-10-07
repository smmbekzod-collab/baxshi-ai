import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

class LocalStore {
  LocalStore._(this.box);
  final Box<String> box;
  static Future<LocalStore> open() async {
    final directory = await getApplicationSupportDirectory();
    Hive.init(directory.path);
    const secure = FlutterSecureStorage();
    var key = await secure.read(key: 'hive_key_v1');
    if (key == null) {
      key = base64UrlEncode(Hive.generateSecureKey());
      await secure.write(key: 'hive_key_v1', value: key);
    }
    return LocalStore._(
      await Hive.openBox<String>(
        'baxshi_v1',
        encryptionCipher: HiveAesCipher(base64Url.decode(key)),
      ),
    );
  }

  Map<String, dynamic>? read(String key) {
    final raw = box.get(key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> write(String key, Map<String, dynamic> data) =>
      box.put(key, jsonEncode(data));
  Future<void> remove(String key) => box.delete(key);
  // Account-scoped reports must never be reused for another account.
  Future<void> clearAccount(String subject) async {
    final keys = box.keys
        .where((k) => k.toString().startsWith('$subject:'))
        .toList();
    await box.deleteAll(keys);
  }
}
