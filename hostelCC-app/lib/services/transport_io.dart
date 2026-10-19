import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Transport {
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final _storage = const FlutterSecureStorage();
  final Map<String, Cookie> _cookies = {};
  String? _origin;
  Future<(int, String)> send(
      Uri uri, String method, Map<String, String> headers, String? body) async {
    final origin = '${uri.scheme}://${uri.authority}';
    if (_origin != origin) {
      _origin = origin;
      _cookies.clear();
      final saved = await _storage.read(key: 'hostelcc_cookie_$origin');
      if (saved != null) {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        if (DateTime.parse(data['expires']).isAfter(DateTime.now())) {
          _cookies['HOSTELCC_SESSION'] =
              Cookie('HOSTELCC_SESSION', data['value'])
                ..httpOnly = true
                ..expires = DateTime.parse(data['expires']);
        } else {
          await _storage.delete(key: 'hostelcc_cookie_$origin');
        }
      }
    }
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    request.cookies.addAll(_cookies.values
        .where((c) => c.expires == null || c.expires!.isAfter(DateTime.now())));
    if (body != null) {
      request.write(body);
    }
    final response = await request.close().timeout(const Duration(seconds: 25));
    for (final cookie in response.cookies) {
      if (cookie.maxAge == 0 || cookie.value.isEmpty) {
        _cookies.remove(cookie.name);
      } else {
        _cookies[cookie.name] = cookie;
      }
      if (cookie.name == 'HOSTELCC_SESSION') {
        if (cookie.maxAge != null && cookie.maxAge! > 0) {
          final expires = DateTime.now().add(Duration(seconds: cookie.maxAge!));
          cookie.expires = expires;
          await _storage.write(
              key: 'hostelcc_cookie_$origin',
              value: jsonEncode({
                'value': cookie.value,
                'expires': expires.toIso8601String()
              }));
        } else {
          await _storage.delete(key: 'hostelcc_cookie_$origin');
        }
      }
    }
    return (response.statusCode, await utf8.decoder.bind(response).join());
  }
}
