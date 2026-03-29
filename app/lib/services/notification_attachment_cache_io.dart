import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:http/http.dart" as http;
import "package:path_provider/path_provider.dart";

class NotificationAttachmentCache {
  NotificationAttachmentCache({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  String resolveAttachmentUrl(String attachmentUrl, String apiBaseUrl) {
    final trimmed = attachmentUrl.trim();
    if (trimmed.isEmpty) {
      return "";
    }

    // If URL already has a scheme (http, https), return as-is
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }

    // For relative paths, resolve against API base URL
    final baseUri = Uri.parse(apiBaseUrl);
    if (trimmed.startsWith("//")) {
      return "${baseUri.scheme}:$trimmed";
    }
    
    // Relative path: prepend base URL
    return baseUri.resolve(trimmed).toString();
  }

  Future<String?> getCachedFilePath({
    required int notificationId,
    required String attachmentUrl,
    required String apiBaseUrl,
  }) async {
    final normalizedUrl = resolveAttachmentUrl(attachmentUrl, apiBaseUrl);
    if (normalizedUrl.isEmpty) {
      return null;
    }

    final directory = await _cacheDirectory();
    final extension = _resolveFileExtension(normalizedUrl);
    final file = File(
      "${directory.path}${Platform.pathSeparator}n_${notificationId}_${_shortHash(normalizedUrl)}$extension",
    );

    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  Future<String> ensureCached({
    required int notificationId,
    required String attachmentUrl,
    required String apiBaseUrl,
    Map<String, String>? headers,
  }) async {
    final normalizedUrl = resolveAttachmentUrl(attachmentUrl, apiBaseUrl);
    if (normalizedUrl.isEmpty) {
      throw Exception("Attachment URL is empty.");
    }

    final existingPath = await getCachedFilePath(
      notificationId: notificationId,
      attachmentUrl: normalizedUrl,
      apiBaseUrl: apiBaseUrl,
    );
    if (existingPath != null) {
      return existingPath;
    }

    final response = await _httpClient
        .get(
      Uri.parse(normalizedUrl),
      headers: headers ?? const <String, String>{},
    )
        .timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        throw Exception(
          "Attachment download timed out. Check your internet connection and try again.",
        );
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception("Attachment download failed (${response.statusCode}).");
    }
    if (response.bodyBytes.isEmpty) {
      throw Exception("Attachment download returned empty content.");
    }

    final directory = await _cacheDirectory();
    final extension = _resolveFileExtension(
      normalizedUrl,
      contentType: response.headers["content-type"],
    );
    final file = File(
      "${directory.path}${Platform.pathSeparator}n_${notificationId}_${_shortHash(normalizedUrl)}$extension",
    );
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  Future<Uint8List> readCachedBytes(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception("Cached attachment file was not found.");
    }
    return file.readAsBytes();
  }

  void close() {
    _httpClient.close();
  }

  Future<Directory> _cacheDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      "${documents.path}${Platform.pathSeparator}notification_attachments",
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _shortHash(String input) {
    final encoded = base64Url.encode(utf8.encode(input)).replaceAll("=", "");
    return encoded.length <= 24 ? encoded : encoded.substring(0, 24);
  }

  String _resolveFileExtension(String url, {String? contentType}) {
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();

    if (path.endsWith(".pdf")) {
      return ".pdf";
    }
    if (path.endsWith(".png")) {
      return ".png";
    }
    if (path.endsWith(".jpg")) {
      return ".jpg";
    }
    if (path.endsWith(".jpeg")) {
      return ".jpeg";
    }
    if (path.endsWith(".webp")) {
      return ".webp";
    }

    final normalizedType = (contentType ?? "").toLowerCase();
    if (normalizedType.contains("application/pdf")) {
      return ".pdf";
    }
    if (normalizedType.contains("image/png")) {
      return ".png";
    }
    if (normalizedType.contains("image/jpeg")) {
      return ".jpg";
    }
    if (normalizedType.contains("image/webp")) {
      return ".webp";
    }

    return ".bin";
  }
}
