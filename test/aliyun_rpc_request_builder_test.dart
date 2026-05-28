import 'dart:typed_data';

import 'package:facedetection/services/aliyun/aliyun_rpc_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildAliyunRpcPostBody', () {
    test('places all signed params in POST body for InitFaceVerify', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final signed = buildAliyunRpcPostBody(
        AliyunRpcPostBodyInput(
          accessKeyId: 'test-key',
          accessKeySecret: 'test-secret',
          apiVersion: '2019-03-07',
          regionId: 'cn-shanghai',
          action: 'InitFaceVerify',
          queryParams: {
            'SceneId': 'scene-1',
            'MetaInfo': '{"deviceType":"phone"}',
            'ReturnUrl': 'https://example.com/cb',
            'CertifyUrlType': 'H5',
          },
          formDataParams: {
            'Model': 'MOVE_ACTION',
            'Crop': 'T',
          },
          faceContrastPictureBytes: bytes,
        ),
      );

      expect(signed.queryString, isEmpty);
      expect(signed.formBody, isNotEmpty);
      expect(signed.formBody, contains('Action=InitFaceVerify'));
      expect(signed.formBody, contains('SceneId=scene-1'));
      expect(signed.formBody, contains('Signature='));
      expect(signed.formBody, contains('Model=MOVE_ACTION'));
      expect(signed.formBody, contains('FaceContrastPicture='));
      expect(signed.formBody, contains('CertifyUrlType=H5'));
      expect(signed.stringToSign, startsWith('POST&%2F&'));
      expect(signed.formBody, contains('Crop=T'));
      expect(signed.formBody, isNot(contains('%252F')));
    });
  });
}
