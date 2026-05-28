import 'package:facedetection/services/aliyun/aliyun_face_verification_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = AliyunFaceVerificationResponseParser(
    providerId: 'aliyun_cloudauth',
    providerName: 'Aliyun CloudAuth',
    matchThreshold: 70,
  );

  group('AliyunFaceVerificationResponseParser', () {
    test('parseDescribeResponse passes when verifyScore above threshold', () {
      final result = parser.parseDescribeResponse(
        response: {
          'RequestId': 'req-1',
          'ResultObject': {
            'Passed': 'T',
            'MaterialInfo': '''
{
  "faceAttack": "F",
  "facialPictureFront": {
    "verifyScore": 85.5,
    "qualityScore": 99.1
  }
}
''',
          },
        },
        latency: Duration.zero,
        certifyId: 'cert-1',
      );

      expect(result.success, isTrue);
      expect(result.isMatch, isTrue);
      expect(result.isLive, isTrue);
      expect(result.similarity, 85.5);
    });

    test('parseDescribeResponse fails match when verifyScore below threshold', () {
      final result = parser.parseDescribeResponse(
        response: {
          'ResultObject': {
            'Passed': 'T',
            'MaterialInfo': {
              'faceAttack': 'F',
              'facialPictureFront': {'verifyScore': 50},
            },
          },
        },
        latency: Duration.zero,
        certifyId: 'cert-2',
      );

      expect(result.success, isTrue);
      expect(result.isMatch, isFalse);
      expect(result.isLive, isTrue);
    });

    test('parseDescribeResponse treats faceAttack as not live', () {
      final result = parser.parseDescribeResponse(
        response: {
          'ResultObject': {
            'Passed': 'T',
            'MaterialInfo': {
              'faceAttack': 'T',
              'facialPictureFront': {'verifyScore': 90},
            },
          },
        },
        latency: Duration.zero,
        certifyId: 'cert-3',
      );

      expect(result.isLive, isFalse);
      expect(result.isMatch, isFalse);
    });

    test('parseH5SessionReady succeeds with CertifyId only', () {
      final result = parser.parseH5SessionReady(
        latency: Duration.zero,
        certifyId: 'sha4b81c02e58744efc063af2042f0c7',
        requestId: 'req-init',
      );

      expect(result.success, isTrue);
      expect(result.sdkToken, 'sha4b81c02e58744efc063af2042f0c7');
      expect(result.verificationUrl, isNull);
      expect(result.description, contains('CertifyId only'));
    });

    test('parseH5SessionReady includes CertifyUrl when present', () {
      final result = parser.parseH5SessionReady(
        latency: Duration.zero,
        certifyId: 'cert-1',
        certifyUrl: 'https://t.aliyun.com/abc',
        requestId: 'req-init',
      );

      expect(result.success, isTrue);
      expect(result.verificationUrl, 'https://t.aliyun.com/abc');
      expect(result.description, contains('CertifyUrl'));
    });

    test('failure enriches Aliyun error codes', () {
      final result = parser.failure(
        latency: const Duration(milliseconds: 100),
        message: 'Specified scene is not found',
        errorCode: '404',
        requestId: 'req-404',
        apiAction: AliyunFaceVerificationResponseParser.initFaceVerifyAction,
      );

      expect(result.success, isFalse);
      expect(result.errorCode, '404');
      expect(result.errorExplanationZh, '认证场景配置不存在');
      expect(result.errorSuggestedFix, isNotEmpty);
      expect(result.requestId, 'req-404');
    });
  });
}
