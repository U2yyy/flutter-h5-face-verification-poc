import 'package:facedetection/services/baidu/baidu_api_client.dart';
import 'package:facedetection/services/baidu/baidu_face_verification_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = BaiduFaceVerificationResponseParser(
    providerId: 'baidu',
    providerName: 'Baidu AI',
    matchThreshold: 80,
    livenessThresholdKey: 'frr_1e-3',
  );

  test('parseCombined passes when liveness and match exceed thresholds', () {
    final result = parser.parseCombined(
      latency: const Duration(milliseconds: 200),
      liveness: const BaiduVideoLivenessResult(
        score: 0.95,
        thresholds: {'frr_1e-3': 0.3},
        bestImageBase64: 'live_pic_base64',
        bestImageLivenessScore: 0.96,
        logId: 12345,
      ),
      matchResponse: {'score': 88.5},
    );

    expect(result.success, isTrue);
    expect(result.isLive, isTrue);
    expect(result.isMatch, isTrue);
    expect(result.similarity, 88.5);
    expect(result.apiAction, contains('faceliveness/verify'));
    expect(result.apiAction, contains('face/v3/match'));
  });

  test('parseCombined fails match when score below threshold', () {
    final result = parser.parseCombined(
      latency: const Duration(milliseconds: 100),
      liveness: const BaiduVideoLivenessResult(
        score: 0.9,
        thresholds: {'frr_1e-3': 0.3},
        bestImageBase64: 'pic',
      ),
      matchResponse: {'score': 40.0},
    );

    expect(result.isLive, isTrue);
    expect(result.isMatch, isFalse);
  });

  test('failure formats error code', () {
    final result = parser.failure(
      latency: const Duration(milliseconds: 50),
      message: 'pic not has face',
      errorCode: 222202,
    );

    expect(result.success, isFalse);
    expect(result.errorMessage, '222202: pic not has face');
  });

  test('parseH5DetailResponse passes when liveness and match exceed thresholds',
      () {
    final result = parser.parseH5DetailResponse(
      latency: const Duration(milliseconds: 120),
      verifyToken: 'verify-tok',
      response: {
        'success': true,
        'log_id': '999',
        'result': {
          'verify_result': {
            'liveness_score': 0.88,
            'score': 91.2,
            'spoofing': 0.01,
          },
        },
      },
    );

    expect(result.success, isTrue);
    expect(result.isLive, isTrue);
    expect(result.isMatch, isTrue);
    expect(result.similarity, 91.2);
    expect(result.sdkToken, 'verify-tok');
    expect(result.apiAction, contains('result/detail'));
  });

  test('parseH5DetailResponse fails liveness when score is zero', () {
    final result = parser.parseH5DetailResponse(
      latency: const Duration(milliseconds: 80),
      verifyToken: 'verify-tok',
      response: {
        'success': true,
        'result': {
          'verify_result': {
            'liveness_score': 0,
            'score': 0,
            'spoofing': 0,
          },
        },
      },
    );

    expect(result.isLive, isFalse);
    expect(result.isMatch, isFalse);
  });
}
