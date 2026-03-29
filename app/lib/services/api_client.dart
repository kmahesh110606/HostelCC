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

  Future<void> delete(String path, {String? token}) async {
    final response = await http.delete(
      Uri.parse("$baseUrl$path"),
      headers: _headers(token),
    );
    _parse(response);
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
    dynamic decoded;
    if (response.body.isEmpty) {
      decoded = <String, dynamic>{};
    } else {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        final isHtml = response.body
                .trimLeft()
                .toLowerCase()
                .startsWith("<!doctype html") ||
            response.body.trimLeft().toLowerCase().startsWith("<html");
        final location = response.headers["location"];
        if (isHtml || location != null) {
          final target = location != null ? " Redirected to: $location." : "";
          throw Exception(
            "API returned HTML instead of JSON (status ${response.statusCode})."
            "$target Check API base URL and Django redirect/login settings.",
          );
        }
        throw Exception(
          "API returned non-JSON response (status ${response.statusCode}).",
        );
      }
    }
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
