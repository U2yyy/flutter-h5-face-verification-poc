import 'package:facedetection/services/aliyun/aliyun_h5_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AliyunH5CallbackParser', () {
    test('extractCertifyId from response JSON query param', () {
      const responseJson =
          '{"code":1000,"subCode":"Z5050","reason":"success","extInfo":{"certifyId":"abc123certify"}}';
      final url =
          'https://facedetection.local/aliyun/h5/callback?response=${Uri.encodeComponent(responseJson)}';

      expect(AliyunH5CallbackParser.extractCertifyId(url), 'abc123certify');
    });

    test('extractCertifyId from direct certifyId query param', () {
      expect(
        AliyunH5CallbackParser.extractCertifyId(
          'https://facedetection.local/aliyun/h5/callback?certifyId=direct-id',
        ),
        'direct-id',
      );
    });

    test('isCompletionRedirect matches configured ReturnUrl base', () {
      const redirect = 'https://facedetection.local/aliyun/h5/callback';
      const responseJson =
          '{"extInfo":{"certifyId":"cid-999"}}';
      final url =
          '$redirect?response=${Uri.encodeComponent(responseJson)}';

      expect(
        AliyunH5CallbackParser.isCompletionRedirect(url, redirect),
        isTrue,
      );
      expect(
        AliyunH5CallbackParser.isCompletionRedirect(
          'https://other.example/callback?certifyId=x',
          redirect,
        ),
        isFalse,
      );
    });
  });
}
