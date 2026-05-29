/// FinAuth (Megvii) H5 Lite overseas liveness helpers.
///
/// Flow: get_token → open DoVerification URL in WebView → return_url callback
/// with `biz_id` → get_result.
library;

import '../../utils/app_config.dart';

/// Session returned by get_token.
class FinAuthH5Session {
  const FinAuthH5Session({
    required this.token,
    required this.bizId,
    required this.verificationUrl,
    required this.returnUrl,
    this.requestId,
    this.expiredTime,
  });

  final String token;
  final String bizId;
  final String verificationUrl;
  final String returnUrl;
  final String? requestId;
  final int? expiredTime;
}

/// Builds FinAuth DoVerification URLs and parses return_url callbacks.
class FinAuthH5UrlBuilder {
  const FinAuthH5UrlBuilder._();

  static String doVerificationBase([String? configured]) {
    final base = (configured ?? AppConfig.finauthDoVerificationBase).trim();
    return base.endsWith('?') ? base : '$base?';
  }

  static String buildDoVerificationUrl({
    required String token,
    String? doVerificationBase,
  }) {
    final base = doVerificationBase ?? FinAuthH5UrlBuilder.doVerificationBase();
    return Uri.parse(base).replace(queryParameters: {'token': token}).toString();
  }

  static FinAuthH5Session buildSession({
    required String token,
    required String bizId,
    String? requestId,
    int? expiredTime,
    String? returnUrl,
    String? doVerificationBase,
  }) {
    final redirect = (returnUrl ?? AppConfig.finauthH5ReturnUrl).trim();
    return FinAuthH5Session(
      token: token,
      bizId: bizId,
      verificationUrl: buildDoVerificationUrl(
        token: token,
        doVerificationBase: doVerificationBase,
      ),
      returnUrl: redirect,
      requestId: requestId,
      expiredTime: expiredTime,
    );
  }
}

/// Parses FinAuth H5 return_url redirects (`?biz_id=` when action_http_method=GET).
class FinAuthH5CallbackParser {
  static String redirectBase(String redirectUrl) {
    final uri = Uri.parse(redirectUrl.trim());
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return '${uri.scheme}://${uri.host.toLowerCase()}$path'.toLowerCase();
  }

  static bool isCompletionRedirect(String url, String redirectUrl) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return false;

    final bizId = extractBizId(url);
    if (bizId == null || bizId.isEmpty) return false;

    final currentBase = redirectBase(url);
    final expectedBase = redirectBase(redirectUrl);
    return currentBase == expectedBase ||
        currentBase.startsWith(expectedBase) ||
        expectedBase.startsWith(currentBase);
  }

  /// Extracts biz_id from return_url query (GET callback).
  static String? extractBizId(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return null;

    final direct = parsed.queryParameters['biz_id'];
    if (direct != null && direct.isNotEmpty) return direct;

    // POST form callbacks may surface as fragment or encoded query in some WebViews.
    final fragment = parsed.fragment;
    if (fragment.contains('biz_id=')) {
      final fragUri = Uri.parse('?$fragment');
      final fromFragment = fragUri.queryParameters['biz_id'];
      if (fromFragment != null && fromFragment.isNotEmpty) return fromFragment;
    }

    return null;
  }
}
