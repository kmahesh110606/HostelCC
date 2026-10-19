import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_cc_app/services/local_cache.dart';
import 'package:hostel_cc_app/services/api.dart';

class NetworkApi extends Api {
  Object? failure;
  NetworkApi(LocalCache cache)
      : super(baseUrl: 'https://test/api', cacheOverride: cache);
  @override
  Future<dynamic> request(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      bool retry = true}) async {
    if (failure != null) throw failure!;
    if (path == '/auth/me') return {'id': 'one', 'role': 'STUDENT'};
    return {
      'items': [
        {'name': 'Cached menu'}
      ]
    };
  }
}

class MemoryStorage implements CacheStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test(
      'network failure serves cached reads but never queues writes or bypasses authorization',
      () async {
    final cache = LocalCache('network', storage: MemoryStorage());
    final api = NetworkApi(cache);
    await api.call('/auth/me');
    await api.call('/workspace');
    api.failure = Exception('offline');
    expect((await api.call('/workspace'))['items'][0]['name'], 'Cached menu');
    expect(Api.cacheNotice.value, isNotNull);
    await expectLater(
        api.call('/campus/gate', method: 'POST', body: {}), throwsException);
    api.failure = ApiException('Access revoked', 403);
    await expectLater(api.call('/workspace'), throwsA(isA<ApiException>()));
    expect(await cache.get('/workspace'), isNull);
  });
  test('cache persists per origin, expires, and never mixes accounts',
      () async {
    final storage = MemoryStorage();
    var time = DateTime(2026, 10, 19, 12);
    final cache = LocalCache('https://hostel.test/api',
        storage: storage, clock: () => time);
    await cache.profile({'id': 'one', 'role': 'STUDENT'});
    await cache.put('/workspace', {'name': 'First'});
    final restored = LocalCache('https://hostel.test/api',
        storage: storage, clock: () => time);
    expect((await restored.get('/workspace'))?['value']['name'], 'First');
    final another = LocalCache('https://other.test/api',
        storage: storage, clock: () => time);
    expect(await another.get('/workspace'), isNull);
    time = time.add(const Duration(minutes: 16));
    expect(await cache.get('/workspace'), isNull);
    await cache.profile({'id': 'two', 'role': 'STUDENT'});
    expect(await cache.get('/workspace'), isNull);
  });
  test('scope changes, mutations, and logout clear cached records', () async {
    final cache = LocalCache('local', storage: MemoryStorage());
    await cache.profile({
      'id': 'staff',
      'role': 'WARDEN',
      'scopes': ['A']
    });
    await cache.put('/workspace', {'block': 'A'});
    await cache.profile({
      'id': 'staff',
      'role': 'WARDEN',
      'scopes': ['B']
    });
    expect(await cache.get('/workspace'), isNull);
    await cache.put('/workspace', {'block': 'B'});
    await cache.invalidate();
    expect(await cache.get('/workspace'), isNull);
    await cache.put('/workspace', {});
    await cache.clear();
    expect(await cache.get('/auth/me'), isNull);
    expect(await cache.get('/workspace'), isNull);
  });
  test('cache is bounded and ordered concurrent writes remain readable',
      () async {
    final storage = MemoryStorage(),
        cache = LocalCache('bounded', storage: MemoryStorage());
    await cache.profile({'id': 'one'});
    await Future.wait(
        List.generate(70, (i) => cache.put('/record/$i', {'id': i})));
    expect(await cache.get('/record/0'), isNull);
    expect((await cache.get('/record/69'))?['value']['id'], 69);
    final persistent = LocalCache('serial', storage: storage);
    await persistent.profile({'id': 'one'});
    await Future.wait([persistent.put('/a', 1), persistent.put('/b', 2)]);
    final restored = LocalCache('serial', storage: storage);
    expect((await restored.get('/a'))?['value'], 1);
    expect((await restored.get('/b'))?['value'], 2);
  });
}
