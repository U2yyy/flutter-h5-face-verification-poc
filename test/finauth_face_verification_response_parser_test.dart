import 'package:facedetection/services/finauth/finauth_face_verification_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = FinAuthFaceVerificationResponseParser(
    providerId: 'finauth',
    providerName: 'Megvii FinAuth',
    matchThresholdKey: '1e-4',
  );

  group('FinAuthFaceVerificationResponseParser', () {
    test('parseGetResultResponse passes when status OK, liveness PASS, match above threshold',
        () {
      final result = parser.parseGetResultResponse(
        bizId: 'biz-1',
        latency: const Duration(milliseconds: 120),
        response: {
          'request_id': 'req-1',
          'status': 'OK',
          'liveness_result': {
            'result': 'PASS',
            'procedure_type': 'flash',
          },
          'verify_result': {
            'result_ref1': {
              'confidence': 72.5,
              'thresholds': {
                '1e-3': 64,
                '1e-4': 69,
                '1e-5': 74,
                '1e-6': 79.9,
              },
            },
          },
        },
      );

      expect(result.success, isTrue);
      expect(result.isLive, isTrue);
      expect(result.isMatch, isTrue);
      expect(result.similarity, 72.5);
      expect(result.sdkToken, 'biz-1');
      expect(result.apiAction, FinAuthFaceVerificationResponseParser.getResultAction);
    });

    test('parseGetResultResponse fails match when confidence below threshold', () {
      final result = parser.parseGetResultResponse(
        bizId: 'biz-2',
        latency: Duration.zero,
        response: {
          'status': 'OK',
          'liveness_result': {'result': 'PASS', 'procedure_type': 'still'},
          'verify_result': {
            'result_ref1': {
              'confidence': 60,
              'thresholds': {'1e-4': 69},
            },
          },
        },
      );

      expect(result.isLive, isTrue);
      expect(result.isMatch, isFalse);
    });

    test('parseGetResultResponse handles non-OK status without throwing', () {
      final result = parser.parseGetResultResponse(
        bizId: 'biz-3',
        latency: Duration.zero,
        response: {
          'status': 'FAILED',
          'fail_reason': 'TIMEOUT',
        },
      );

      expect(result.success, isTrue);
      expect(result.isMatch, isFalse);
      expect(result.isLive, isFalse);
      expect(result.resultCode, 'FAILED');
    });

    test('parseH5SessionReady stores biz_id as sdkToken', () {
      final result = parser.parseH5SessionReady(
        latency: const Duration(milliseconds: 50),
        token: 'session-token',
        bizId: 'biz-session',
        verificationUrl: 'https://api-global.yljz.com/finauth/lite/do?token=session-token',
      );

      expect(result.success, isTrue);
      expect(result.sdkToken, 'biz-session');
      expect(result.verificationUrl, contains('token=session-token'));
      expect(result.resultCode, 'session-token');
    });
  });
}
