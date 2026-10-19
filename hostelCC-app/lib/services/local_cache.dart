import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class CacheStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceCacheStorage implements CacheStorage {
  final storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) async =>
      kIsWeb ? null : storage.read(key: key);
  @override
  Future<void> write(String key, String value) async {
    if (!kIsWeb) await storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) async {
    if (!kIsWeb) await storage.delete(key: key);
  }
}

class LocalCache {
  final CacheStorage storage;
  final String key;
  final DateTime Function() clock;
  Map<String, dynamic> state = {};
  Future<void>? loading;
  Future<void> writes = Future.value();
  static const lifetime = Duration(minutes: 15);
  LocalCache(String origin, {CacheStorage? storage, DateTime Function()? clock})
      : storage = storage ?? DeviceCacheStorage(),
        clock = clock ?? DateTime.now,
        key = 'hostelcc_cache_${base64Url.encode(utf8.encode(origin))}';
  Future<void> load() => loading ??= () async {
        try {
          final value = await storage.read(key);
          if (value != null) {
            state = Map<String, dynamic>.from(jsonDecode(value));
          }
        } catch (_) {
          state = {};
        }
      }();
  Future<void> persist() {
    final snapshot = jsonEncode(state);
    writes =
        writes.catchError((_) {}).then((_) => storage.write(key, snapshot));
    return writes;
  }

  Future<void> clear() async {
    await load();
    state = {};
    writes = writes.catchError((_) {}).then((_) => storage.delete(key));
    await writes;
  }

  String identity(Map<String, dynamic> user) => jsonEncode([
        user['id'],
        user['role'],
        user['blockId'],
        user['messId'],
        user['cloakroomAccess'],
        user['scopes']
      ]);
  Future<void> profile(Map<String, dynamic> user) async {
    await load();
    final fingerprint = identity(user);
    if (state['identity'] != fingerprint) {
      state = {'identity': fingerprint, 'entries': <String, dynamic>{}};
    }
    await put('/auth/me', user);
  }

  Future<void> invalidate() async {
    await load();
    state['entries'] = <String, dynamic>{};
    await persist();
  }

  Future<void> put(String path, dynamic value) async {
    await load();
    if (state['identity'] == null) return;
    final entries = Map<String, dynamic>.from(state['entries'] ?? {});
    entries.remove(path);
    entries[path] = {'savedAt': clock().toIso8601String(), 'value': value};
    while (entries.length > 60 ||
        utf8.encode(jsonEncode(entries)).length > 1000000) {
      entries.remove(entries.keys.first);
      if (entries.isEmpty) break;
    }
    state['entries'] = entries;
    await persist();
  }

  Future<Map<String, dynamic>?> get(String path) async {
    await load();
    final entry = (state['entries'] as Map?)?[path];
    if (entry == null || state['identity'] == null) return null;
    final saved = DateTime.tryParse(entry['savedAt'] ?? '');
    if (saved == null ||
        clock().difference(saved) > lifetime ||
        saved.isAfter(clock())) {
      return null;
    }
    return Map<String, dynamic>.from(entry);
  }
}
