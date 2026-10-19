import 'package:http/browser_client.dart';
import 'package:http/http.dart';

class Transport {
  final _client = BrowserClient()..withCredentials = true;
  Future<(int, String)> send(
      Uri uri, String method, Map<String, String> headers, String? body) async {
    final request = Request(method, uri)..headers.addAll(headers);
    if (body != null) {
      request.body = body;
    }
    final response = await Response.fromStream(await _client.send(request))
        .timeout(const Duration(seconds: 25));
    return (response.statusCode, response.body);
  }
}
