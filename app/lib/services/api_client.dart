import "dart:convert";

import "package:http/http.dart" as http;

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl$path"),
      headers: _headers(token),
      body: jsonEncode(body),
    );
    return _parse(response);
  }

  Future<List<dynamic>> getList(String path, {String? token}) async {
    final response = await http.get(
      Uri.parse("$baseUrl$path"),
      headers: _headers(token),
    );
    final parsed = _parse(response);
    if (parsed["data"] is List<dynamic>) {
      return parsed["data"] as List<dynamic>;
    }
    return <dynamic>[];
  }

  Future<Map<String, dynamic>> getMap(String path, {String? token}) async {
    final response = await http.get(
      Uri.parse("$baseUrl$path"),
      headers: _headers(token),
    );
    final parsed = _parse(response);
    if (parsed["data"] is Map<String, dynamic>) {
      return parsed["data"] as Map<String, dynamic>;
    }
    return <String, dynamic>{};
  }

  Map<String, String> _headers(String? token) {
    return {
      "Content-Type": "application/json",
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
    };
  }

  Map<String, dynamic> _parse(http.Response response) {
    final dynamic decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        return {"ok": true, "data": decoded};
      }
      if (decoded is List<dynamic>) {
        return {"ok": true, "data": decoded};
      }
      return {"ok": true, "data": <String, dynamic>{}};
    }

    String message = "Request failed (${response.statusCode})";
    if (decoded is Map<String, dynamic> && decoded["detail"] != null) {
      message = decoded["detail"].toString();
    }
    throw Exception(message);
  }
}
