import 'package:facedetection/services/tencent/tencent_h5_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const redirectUrl = 'https://facedetection.local/liveness/callback';

  group('TencentH5CallbackParser', () {
    test('redirectBase normalizes host and path', () {
      expect(
        TencentH5CallbackParser.redirectBase(
          'https://FaceDetection.Local/liveness/callback/',
        ),
        'https://facedetection.local/liveness/callback',
      );
    });

    test('extractBizToken reads token query parameter', () {
      expect(
        TencentH5CallbackParser.extractBizToken(
          'https://facedetection.local/liveness/callback?token=ABC-123',
        ),
        'ABC-123',
      );
    });

    test('extractBizToken returns null when token missing', () {
      expect(
        TencentH5CallbackParser.extractBizToken(
          'https://facedetection.local/liveness/callback?code=1',
        ),
        isNull,
      );
    });

    test('isCompletionRedirect matches configured redirect with token', () {
      expect(
        TencentH5CallbackParser.isCompletionRedirect(
          'https://facedetection.local/liveness/callback?token=81EEF678',
          redirectUrl,
        ),
        isTrue,
      );
    });

    test('isCompletionRedirect rejects unrelated URLs', () {
      expect(
        TencentH5CallbackParser.isCompletionRedirect(
          'https://intl.faceid.qq.com/reflect/?token=81EEF678',
          redirectUrl,
        ),
        isFalse,
      );
    });

    test('isCompletionRedirect rejects redirect without token', () {
      expect(
        TencentH5CallbackParser.isCompletionRedirect(
          'https://facedetection.local/liveness/callback',
          redirectUrl,
        ),
        isFalse,
      );
    });
  });

  group('TencentH5LivenessBridge', () {
    test('delegates to callback parser', () {
      const completionUrl =
          'https://facedetection.local/liveness/callback?token=t-1';
      expect(
        TencentH5LivenessBridge.isCompletionRedirect(
          completionUrl,
          redirectUrl,
        ),
        isTrue,
      );
      expect(
        TencentH5LivenessBridge.extractBizToken(completionUrl),
        't-1',
      );
    });
  });
}
