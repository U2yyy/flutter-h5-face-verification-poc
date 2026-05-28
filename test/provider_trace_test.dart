import 'package:facedetection/utils/provider_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProviderTrace', () {
    test('sanitizeHeaders redacts authorization', () {
      final sanitized = ProviderTrace.sanitizeHeaders({
        'Authorization': 'TC3-HMAC-SHA256 Credential=secret',
        'Content-Type': 'application/json',
      });

      expect(sanitized['Authorization'], '<redacted>');
      expect(sanitized['Content-Type'], 'application/json');
    });

    test('loggableValue truncates large base64 fields', () {
      final logged = ProviderTrace.loggableValue('ImageBase64', 'X' * 600);

      expect(logged, isA<Map<String, dynamic>>());
      expect(logged['_truncated'], isTrue);
      expect(logged['_fullLength'], 600);
    });

    test('responseBodyForLog parses JSON', () {
      final parsed = ProviderTrace.responseBodyForLog(
        '{"RequestId":"abc","ErrorCode":0}',
      );
      expect(parsed, isA<Map<String, dynamic>>());
      expect(parsed['RequestId'], 'abc');
    });
  });
}
