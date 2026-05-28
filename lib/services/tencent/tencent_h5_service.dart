/// Tencent FaceID Mobile H5 liveness helpers.
///
/// Flow (intl): ApplyWebVerificationBizTokenIntl → open [verificationUrl] in
/// WebView → user completes liveness → redirect to [redirectUrl]?token={BizToken}
/// → GetWebVerificationResultIntl.
library;

/// Session returned by ApplyWebVerificationBizTokenIntl.
class TencentH5Session {
  const TencentH5Session({
    required this.bizToken,
    required this.verificationUrl,
    required this.redirectUrl,
    this.requestId,
  });

  final String bizToken;
  final String verificationUrl;
  final String redirectUrl;
  final String? requestId;
}

/// Result of the in-app H5 WebView liveness step.
class H5LivenessCompletion {
  const H5LivenessCompletion({
    required this.success,
    this.bizToken,
    this.errorMessage,
  });

  final bool success;
  final String? bizToken;
  final String? errorMessage;
}

/// Parses H5 redirect URLs and detects verification completion.
class TencentH5CallbackParser {
  /// Normalizes a redirect URL for prefix matching (scheme + host + path).
  static String redirectBase(String redirectUrl) {
    final uri = Uri.parse(redirectUrl.trim());
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return '${uri.scheme}://${uri.host.toLowerCase()}$path'.toLowerCase();
  }

  /// Whether [url] is a redirect to the configured callback with a BizToken.
  static bool isCompletionRedirect(String url, String redirectUrl) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return false;

    final token = parsed.queryParameters['token'];
    if (token == null || token.isEmpty) return false;

    final currentBase = redirectBase(url);
    final expectedBase = redirectBase(redirectUrl);
    return currentBase == expectedBase ||
        currentBase.startsWith(expectedBase) ||
        expectedBase.startsWith(currentBase);
  }

  /// Extracts the BizToken from `?token=` on the redirect URL.
  static String? extractBizToken(String url) {
    final parsed = Uri.tryParse(url);
    final token = parsed?.queryParameters['token'];
    if (token == null || token.isEmpty) return null;
    return token;
  }
}

/// High-level H5 liveness bridge — URL/callback utilities (API calls live in
/// [TencentFaceIdService]).
class TencentH5LivenessBridge {
  const TencentH5LivenessBridge._();

  static String redirectBase(String redirectUrl) =>
      TencentH5CallbackParser.redirectBase(redirectUrl);

  static bool isCompletionRedirect(String url, String redirectUrl) =>
      TencentH5CallbackParser.isCompletionRedirect(url, redirectUrl);

  static String? extractBizToken(String url) =>
      TencentH5CallbackParser.extractBizToken(url);
}
