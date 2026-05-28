import 'package:facedetection/models/face_verification_result.dart';
import 'package:facedetection/services/tencent/tencent_face_id_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TencentFaceIdService', () {
    test('parse pure API success response', () {
      const result = FaceVerificationResult(
        providerId: 'tencent_faceid',
        providerName: 'Tencent FaceID',
        latency: Duration(milliseconds: 120),
        success: true,
        isMatch: true,
        isLive: true,
        similarity: 95.5,
        resultCode: 'Success',
        description: 'Success',
      );

      expect(result.isMatch, isTrue);
      expect(result.isLive, isTrue);
      expect(result.similarity, 95.5);
    });

    test('is not configured without credentials', () {
      final service = TencentFaceIdService();
      expect(service.isConfigured, isFalse);
    });
  });
}
