/// Baidu faceprint H5 liveness helpers.
///
/// Flow: verifyToken/generate → uploadMatchImage → open brain.baidu.com/face/print
/// in WebView → redirect to callback URL → result/detail.
library;

import '../../utils/app_config.dart';

/// Session returned by faceprint verifyToken/generate (+ uploadMatchImage).
class BaiduH5Session {
  const BaiduH5Session({
    required this.verifyToken,
    required this.verificationUrl,
    required this.callbackUrl,
    this.requestId,
  });

  final String verifyToken;
  final String verificationUrl;
  final String callbackUrl;
  final String? requestId;
}

/// Builds Baidu H5 verification URLs and callback links.
class BaiduH5UrlBuilder {
  const BaiduH5UrlBuilder._();

  static const _printBase = 'https://brain.baidu.com/face/print/';

  /// Callback URL with embedded verify_token for WebView redirect detection.
  static String callbackWithToken({
    required String callbackBase,
    required String verifyToken,
  }) {
    final base = callbackBase.trim();
    final uri = Uri.parse(base);
    final params = Map<String, String>.from(uri.queryParameters)
      ..['token'] = verifyToken;
    return uri.replace(queryParameters: params).toString();
  }

  /// Full H5 page URL opened in WebView.
  static String buildPrintUrl({
    required String verifyToken,
    required String callbackUrl,
  }) {
    return Uri.parse(_printBase).replace(
      queryParameters: {
        'token': verifyToken,
        'successUrl': callbackUrl,
        'failedUrl': callbackUrl,
      },
    ).toString();
  }

  static BaiduH5Session buildSession({
    required String verifyToken,
    String? requestId,
    String? callbackBase,
  }) {
    final base = (callbackBase ?? AppConfig.baiduFaceprintH5CallbackUrl).trim();
    final callbackUrl = callbackWithToken(
      callbackBase: base,
      verifyToken: verifyToken,
    );
    return BaiduH5Session(
      verifyToken: verifyToken,
      verificationUrl: buildPrintUrl(
        verifyToken: verifyToken,
        callbackUrl: callbackUrl,
      ),
      callbackUrl: callbackUrl,
      requestId: requestId,
    );
  }
}
