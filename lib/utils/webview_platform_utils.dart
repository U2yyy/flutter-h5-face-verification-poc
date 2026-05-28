import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Android WebView tuning and user-facing error text for H5 flows.
class WebViewPlatformUtils {
  WebViewPlatformUtils._();

  /// Applies Android-specific settings used by Aliyun/Tencent H5 WebViews.
  static Future<void> configureForCloudH5(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMixedContentMode(MixedContentMode.compatibilityMode);
    }
  }

  /// Logs navigation/resource failures for device debugging (logcat / Xcode).
  static void logWebResourceError(
    WebResourceError error, {
    String? tag,
  }) {
    final prefix = tag == null ? 'WebView' : 'WebView[$tag]';
    debugPrint(
      '$prefix resource error: code=${error.errorCode} '
      'type=${error.errorType} mainFrame=${error.isForMainFrame} '
      'url=${error.url} desc=${error.description}',
    );
  }

  static void logNavigation(String url, {String? tag}) {
    final prefix = tag == null ? 'WebView' : 'WebView[$tag]';
    debugPrint('$prefix navigation: $url');
  }

  /// Builds a detailed message for SSL/CDN/network failures.
  static String formatResourceError(
    WebResourceError error, {
    String? failedResourceHint,
  }) {
    final buffer = StringBuffer();
    if (failedResourceHint != null && failedResourceHint.isNotEmpty) {
      buffer.writeln(failedResourceHint);
    }
    buffer.write(error.description);
    if (error.url != null && error.url!.isNotEmpty) {
      buffer.write('\nURL: ${error.url}');
    }
    buffer.write('\nError code: ${error.errorCode}');
    if (error.errorType != null) {
      buffer.write(' (${error.errorType!.name})');
    }

    final sslLike = error.errorType == WebResourceErrorType.failedSslHandshake ||
        error.errorCode == -100 ||
        error.description.toLowerCase().contains('ssl') ||
        error.description.toLowerCase().contains('handshake');
    if (sslLike) {
      buffer.write(
        '\n\nPossible causes: network firewall/VPN, incorrect device date/time, '
        'or blocked access to the CDN. Try another network or disable VPN, then Retry.',
      );
    }
    return buffer.toString();
  }
}
