import 'package:facedetection/services/finauth/finauth_h5_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FinAuthH5UrlBuilder', () {
    test('buildDoVerificationUrl embeds token query param', () {
      expect(
        FinAuthH5UrlBuilder.buildDoVerificationUrl(
          token: 'abc123',
          doVerificationBase: 'https://api-global.yljz.com/finauth/lite/do',
        ),
        'https://api-global.yljz.com/finauth/lite/do?token=abc123',
      );
    });

    test('buildSession wires token and biz_id through session fields', () {
      final session = FinAuthH5UrlBuilder.buildSession(
        token: 'tok',
        bizId: 'biz-1',
        returnUrl: 'https://example.com/cb',
        doVerificationBase: 'https://api-global.yljz.com/finauth/lite/do',
      );

      expect(session.token, 'tok');
      expect(session.bizId, 'biz-1');
      expect(session.returnUrl, 'https://example.com/cb');
      expect(session.verificationUrl, contains('token=tok'));
      expect(session.verificationUrl, contains('api-global.yljz.com'));
    });
  });

  group('FinAuthH5CallbackParser', () {
    test('isCompletionRedirect matches return_url with biz_id', () {
      const redirect = 'https://facedetection.local/finauth/h5/callback';
      expect(
        FinAuthH5CallbackParser.isCompletionRedirect(
          'https://facedetection.local/finauth/h5/callback?biz_id=1462259748,abc',
          redirect,
        ),
        isTrue,
      );
    });

    test('extractBizId reads biz_id query parameter', () {
      expect(
        FinAuthH5CallbackParser.extractBizId(
          'https://facedetection.local/finauth/h5/callback?biz_id=biz-xyz&foo=1',
        ),
        'biz-xyz',
      );
    });
  });
}
