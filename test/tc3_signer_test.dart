import 'package:facedetection/utils/tc3_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tc3Signer', () {
    test('buildHeaders produces TC3 authorization for faceid service', () {
      final signer = Tc3Signer(
        secretId: 'test-secret-id',
        secretKey: 'test-secret-key',
        service: 'faceid',
        host: 'faceid.intl.tencentcloudapi.com',
      );

      const payload =
          '{"LivenessType":"SILENT","ImageBase64":"abc","VideoBase64":"def"}';
      final headers = signer.buildHeaders(
        action: 'CompareFaceLiveness',
        version: '2018-03-01',
        payload: payload,
        region: 'ap-singapore',
        timestamp: 1700000000,
      );

      expect(headers['Authorization'],
          startsWith('TC3-HMAC-SHA256 Credential=test-secret-id/'));
      expect(headers['Content-Type'], 'application/json; charset=utf-8');
      expect(headers['Host'], 'faceid.intl.tencentcloudapi.com');
      expect(headers['X-TC-Action'], 'CompareFaceLiveness');
      expect(headers['X-TC-Version'], '2018-03-01');
      expect(headers['X-TC-Region'], 'ap-singapore');
      expect(headers['X-TC-Timestamp'], '1700000000');
    });
  });
}
