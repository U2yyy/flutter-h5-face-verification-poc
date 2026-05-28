import 'package:facedetection/services/tencent/tencent_face_id_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = TencentFaceIdResponseParser(
    providerId: 'tencent_faceid',
    providerName: 'Tencent FaceID',
  );

  group('TencentFaceIdResponseParser', () {
    test('parsePureApiResponse success', () {
      final result = parser.parsePureApiResponse(
        response: {
          'Result': 'Success',
          'Description': 'Success',
          'Sim': 95.5,
          'RequestId': 'req-1',
        },
        action: 'CompareFaceLiveness',
        latency: const Duration(milliseconds: 200),
      );

      expect(result.success, isTrue);
      expect(result.isMatch, isTrue);
      expect(result.isLive, isTrue);
      expect(result.similarity, 95.5);
      expect(result.resultCode, 'Success');
    });

    test('parsePureApiResponse low similarity means live pass, match fail', () {
      final result = parser.parsePureApiResponse(
        response: {
          'Result': 'FailedOperation.CompareLowSimilarity',
          'Description': 'Low similarity',
          'Sim': 42.0,
        },
        action: 'CompareFaceLiveness',
        latency: const Duration(milliseconds: 150),
      );

      expect(result.success, isTrue);
      expect(result.isMatch, isFalse);
      expect(result.isLive, isTrue);
      expect(result.similarity, 42.0);
    });

    test('parsePureApiResponse liveness action failure', () {
      final result = parser.parsePureApiResponse(
        response: {
          'Result': 'FailedOperation.ActionFirstAction',
          'Description': 'First motion not detected',
          'Sim': 0,
        },
        action: 'CompareFaceLiveness',
        latency: const Duration(milliseconds: 100),
      );

      expect(result.success, isTrue);
      expect(result.isMatch, isFalse);
      expect(result.isLive, isFalse);
    });

    test('parseSdkResultResponse incomplete flow', () {
      final result = parser.parseSdkResultResponse(
        response: {
          'Result': '-999',
          'Description': 'Not finished',
        },
        action: 'GetFaceIdResultIntl',
        latency: const Duration(milliseconds: 80),
        sdkToken: 'token-abc',
      );

      expect(result.success, isFalse);
      expect(result.sdkToken, 'token-abc');
      expect(result.errorMessage, isNotNull);
    });

    test('parseH5ResultResponse success', () {
      final result = parser.parseH5ResultResponse(
        response: {
          'ErrorCode': 0,
          'ErrorMsg': 'Success',
          'VerificationDetailList': [
            {'Similarity': 92.5},
          ],
          'RequestId': 'req-h5',
        },
        action: 'GetWebVerificationResultIntl',
        latency: const Duration(milliseconds: 120),
        bizToken: 'biz-1',
      );

      expect(result.success, isTrue);
      expect(result.isMatch, isTrue);
      expect(result.isLive, isTrue);
      expect(result.similarity, 92.5);
      expect(result.resultCode, '0');
    });

    test('parseH5ResultResponse incomplete when ErrorCode null', () {
      final result = parser.parseH5ResultResponse(
        response: {'RequestId': 'req-h5'},
        action: 'GetWebVerificationResultIntl',
        latency: const Duration(milliseconds: 50),
        bizToken: 'biz-1',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('not finished'));
    });
  });
}
