import 'package:facedetection/utils/aliyun_metainfo_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('unwrapAliyunMetaInfoFromJsResult', () {
    test('decodes Android JSON-encoded MetaInfo string', () {
      const input = r'"{\"bioMetaInfo\":\"4.1.0\"}"';
      expect(
        unwrapAliyunMetaInfoFromJsResult(input),
        '{"bioMetaInfo":"4.1.0"}',
      );
    });

    test('returns plain JSON object unchanged', () {
      const input = '{"bioMetaInfo":"4.1.0","deviceType":"phone"}';
      expect(unwrapAliyunMetaInfoFromJsResult(input), input);
    });

    test('returns empty string for null', () {
      expect(unwrapAliyunMetaInfoFromJsResult(null), '');
    });

    test('passes through ERROR prefix payloads', () {
      const input = '"ERROR:SDK failed"';
      expect(unwrapAliyunMetaInfoFromJsResult(input), 'ERROR:SDK failed');
    });
  });
}
