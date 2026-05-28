import 'package:facedetection/utils/aliyun_metainfo_bootstrap.dart';
import 'package:facedetection/utils/webview_platform_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  test('bootstrapHtml references official jsvm_all.js CDN URL', () {
    final html = AliyunMetaInfoBootstrap.bootstrapHtml();
    expect(html, contains(AliyunMetaInfoBootstrap.jsUrl));
    expect(html, contains('onerror="aliyunOnSdkError()"'));
    expect(html, contains('__aliyunBootstrapReady'));
  });

  test('navigationTimeout exceeds bootstrapTimeout', () {
    expect(
      AliyunMetaInfoBootstrap.navigationTimeout,
      greaterThan(AliyunMetaInfoBootstrap.bootstrapTimeout),
    );
  });

  test('formatResourceError adds SSL guidance for handshake failures', () {
    const error = WebResourceError(
      errorCode: -100,
      description: 'net::ERR_CONNECTION_CLOSED',
      errorType: WebResourceErrorType.failedSslHandshake,
      url: AliyunMetaInfoBootstrap.jsUrl,
      isForMainFrame: false,
    );

    final message = WebViewPlatformUtils.formatResourceError(
      error,
      failedResourceHint: 'Failed to load Aliyun MetaInfo SDK:',
    );

    expect(message, contains('Failed to load Aliyun MetaInfo SDK:'));
    expect(message, contains(AliyunMetaInfoBootstrap.jsUrl));
    expect(message, contains('VPN'));
  });
}
