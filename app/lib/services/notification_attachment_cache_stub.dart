class NotificationAttachmentCache {
  String resolveAttachmentUrl(String attachmentUrl, String apiBaseUrl) {
    final trimmed = attachmentUrl.trim();
    if (trimmed.isEmpty) {
      return "";
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }

    final baseUri = Uri.parse(apiBaseUrl);
    if (trimmed.startsWith("//")) {
      return "${baseUri.scheme}:$trimmed";
    }
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
