import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'transport_io.dart' if (dart.library.html) 'transport_web.dart';
import 'local_cache.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}

class Api {
  static final cacheNotice = ValueNotifier<String?>(null);
  final LocalCache? cacheOverride;
  late final LocalCache cache = cacheOverride ?? LocalCache(baseUrl);
  final Transport _transport = Transport();
  String? _csrf;
  int generation = 0;
  static const configuredUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');
  final String baseUrl;
  Api({String? baseUrl, this.cacheOverride})
      : baseUrl = baseUrl ??
            (configuredUrl.isNotEmpty
                ? configuredUrl
                : kIsWeb
                    ? '${Uri.base.origin}/api'
                    : 'http://10.0.2.2:8080/api');
  Future<dynamic> call(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      bool retry = true}) async {
    if (method != 'GET') generation++;
    final requestGeneration = generation;
    if (path == '/auth/logout') {
      try {
        await request(path, method: method, body: body, retry: retry);
      } finally {
        await cache.clear();
        await _transport.clear();
        _csrf = null;
        cacheNotice.value = null;
      }
      return {'message': 'Signed out'};
    }
    try {
      final result =
          await request(path, method: method, body: body, retry: retry);
      cacheNotice.value = null;
      if (path == '/auth/me' || path == '/auth/verify-code') {
        await cache.load();
        if (cache.state['identity'] !=
            cache.identity(Map<String, dynamic>.from(result))) {
          generation++;
        }
        await cache.profile(Map<String, dynamic>.from(result));
      } else if (method == 'GET' && !path.startsWith('/auth/')) {
        if (requestGeneration == generation) await cache.put(path, result);
      } else if (method != 'GET' && !path.startsWith('/auth/')) {
        await cache.invalidate();
      }
      return result;
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        generation++;
        await cache.clear();
      }
      rethrow;
    } catch (_) {
      if (requestGeneration == generation &&
          method == 'GET' &&
          (!path.startsWith('/auth/') || path == '/auth/me')) {
        final saved = await cache.get(path);
        if (saved != null) {
          cacheNotice.value =
              'Offline · cached ${saved['savedAt']} · changes require a connection';
          return saved['value'];
        }
      }
      rethrow;
    }
  }

  Future<dynamic> request(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      bool retry = true}) async {
    if (method != 'GET' && _csrf == null) {
      _csrf = (await call('/auth/csrf'))['token'];
    }
    final (status, text) = await _transport.send(
        Uri.parse('${baseUrl.replaceFirst(RegExp(r'/$'), '')}$path'),
        method,
        {
          'Content-Type': 'application/json',
          if (method != 'GET') 'X-XSRF-TOKEN': _csrf!
        },
        body == null ? null : jsonEncode(body));
    dynamic result;
    try {
      result = jsonDecode(text);
    } catch (_) {
      throw ApiException(
          'Unexpected server response. Check your connection.', status);
    }
    if (status >= 400) {
      final message =
          result['message'] as String? ?? 'The request could not be completed.';
      if (status == 403 && message.contains('CSRF') && retry) {
        _csrf = null;
        return call(path, method: method, body: body, retry: false);
      }
      throw ApiException(message, status);
    }
    return result;
  }
}

String label(dynamic value) => (value ?? '')
    .toString()
    .replaceAll('_', ' ')
    .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .toLowerCase()
    .split(' ')
    .map((s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}')
    .join(' ');
bool has(Map<String, dynamic> user, String book, [String? target]) =>
    user['role'] == 'ADMIN' ||
    (user['scopes'] as List? ?? []).any((s) =>
        s['active'] == true &&
        s['book'] == book &&
        (target == null || s['targetId'] == target));
List<Map<String, dynamic>> rows(Map<String, dynamic> data, String key) =>
    (data[key] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
