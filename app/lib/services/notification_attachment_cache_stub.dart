class NotificationAttachmentCache {
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
    return null;
  }

  Future<String> ensureCached({
    required int notificationId,
    required String attachmentUrl,
    required String apiBaseUrl,
    Map<String, String>? headers,
  }) async {
    throw Exception(
        "Offline attachment cache is not supported on this platform.");
  }

  Future<List<int>> readCachedBytes(String filePath) async {
    throw Exception(
        "Offline attachment cache is not supported on this platform.");
  }

  void close() {}
}
