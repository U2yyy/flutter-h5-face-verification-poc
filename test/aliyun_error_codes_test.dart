import 'package:facedetection/utils/aliyun_error_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AliyunErrorCodes', () {
    test('resolves InitFaceVerify code 404', () {
      final info = AliyunErrorCodes.resolve(code: '404');
      expect(info.chineseExplanation, '认证场景配置不存在');
      expect(info.suggestedFix, contains('SCENE_ID'));
    });

    test('resolves SignatureDoesNotMatch', () {
      final info = AliyunErrorCodes.resolve(code: 'SignatureDoesNotMatch');
      expect(info.chineseExplanation, 'RPC 签名不匹配');
      expect(info.suggestedFix, contains('%252F'));
      expect(info.suggestedFix, contains('query'));
    });

    test('DescribeFaceVerify SubCode takes precedence', () {
      final info = AliyunErrorCodes.resolve(
        code: '200',
        subCode: 'Z5059',
      );
      expect(info.code, 'Z5059');
      expect(info.chineseExplanation, contains('比对'));
    });

    test('unknown code falls back to api message', () {
      final info = AliyunErrorCodes.resolve(
        code: '999',
        apiMessage: 'custom server message',
      );
      expect(info.chineseExplanation, 'custom server message');
      expect(info.suggestedFix, contains('999'));
    });
  });
}
