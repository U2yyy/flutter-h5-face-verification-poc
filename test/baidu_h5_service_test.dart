import 'package:facedetection/services/baidu/baidu_h5_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BaiduH5UrlBuilder', () {
    test('callbackWithToken embeds verify_token query param', () {
      expect(
        BaiduH5UrlBuilder.callbackWithToken(
          callbackBase: 'https://facedetection.local/baidu/h5/callback',
          verifyToken: 'abc123',
        ),
        'https://facedetection.local/baidu/h5/callback?token=abc123',
      );
    });

    test('buildPrintUrl includes token and redirect URLs', () {
      final url = BaiduH5UrlBuilder.buildPrintUrl(
        verifyToken: 'tok',
        callbackUrl:
            'https://facedetection.local/baidu/h5/callback?token=tok',
      );

      final uri = Uri.parse(url);
      expect(uri.host, 'brain.baidu.com');
      expect(uri.path, '/face/print/');
      expect(uri.queryParameters['token'], 'tok');
      expect(uri.queryParameters['successUrl'],
          'https://facedetection.local/baidu/h5/callback?token=tok');
      expect(uri.queryParameters['failedUrl'],
          'https://facedetection.local/baidu/h5/callback?token=tok');
    });

    test('buildSession wires verify token through session fields', () {
      final session = BaiduH5UrlBuilder.buildSession(
        verifyToken: 'verify-xyz',
        callbackBase: 'https://example.com/cb',
      );

      expect(session.verifyToken, 'verify-xyz');
      expect(session.callbackUrl, 'https://example.com/cb?token=verify-xyz');
      expect(session.verificationUrl, contains('brain.baidu.com'));
      expect(session.verificationUrl, contains('token=verify-xyz'));
    });
  });
}
