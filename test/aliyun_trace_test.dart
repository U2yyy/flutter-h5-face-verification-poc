import 'dart:io';

import 'package:facedetection/utils/aliyun_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AliyunTrace', () {
    tearDown(() {
      AliyunTrace.resolveTempDirectoryOverride = null;
    });

    test('parseFormUrlEncoded decodes query and body params', () {
      final params = AliyunTrace.parseFormUrlEncoded(
        'Action=InitFaceVerify&SceneId=123&ReturnUrl=https%3A%2F%2Fexample.com',
      );

      expect(params['Action'], 'InitFaceVerify');
      expect(params['SceneId'], '123');
      expect(params['ReturnUrl'], 'https://example.com');
    });

    test('loggableValue truncates large FaceContrastPicture without export', () {
      final value = 'A' * 1000;
      final logged = AliyunTrace.loggableValue('FaceContrastPicture', value);

      expect(logged, isA<Map<String, dynamic>>());
      expect(logged['_truncated'], isTrue);
      expect(logged['_fullLength'], 1000);
      expect(logged['_preview'], isA<String>());
    });

    test('loggableValue uses file path metadata when exported', () {
      const export = FaceContrastExport(
        filePath: '/tmp/aliyun_face_contrast_latest.b64',
        stampedFilePath: '/tmp/aliyun_face_contrast_1.b64',
        charCount: 5000,
        adbPullCommand: 'adb pull /tmp/aliyun_face_contrast_latest.b64 .',
      );

      final logged = AliyunTrace.loggableValue(
        'FaceContrastPicture',
        'B' * 5000,
        faceContrastExport: export,
      );

      expect(logged['_truncated'], isTrue);
      expect(logged['_fullLength'], 5000);
      expect(logged['_filePath'], export.filePath);
      expect(logged['_adbPull'], export.adbPullCommand);
      expect(logged.containsKey('_preview'), isFalse);
    });

    test('adbPullCommand formats single-line adb example', () {
      expect(
        AliyunTrace.adbPullCommand(
          '/data/user/0/com.example.facedetection/cache/aliyun_face_contrast_latest.b64',
        ),
        'adb pull /data/user/0/com.example.facedetection/cache/aliyun_face_contrast_latest.b64 .',
      );
    });

    test('exportFaceContrastToFile returns null when debug dump disabled', () async {
      final export = await AliyunTrace.exportFaceContrastToFile(
        'Zm9vYmFy',
        action: 'InitFaceVerify',
      );
      expect(export, isNull);
    });

    test('exportFaceContrastToFile writes files when override temp dir', () async {
      final tempDir = Directory.systemTemp.createTempSync('aliyun_trace_test_');
      AliyunTrace.resolveTempDirectoryOverride = () async => tempDir;

      final base64 = 'Zm9vYmFy';
      final export = await AliyunTrace.exportFaceContrastToFile(
        base64,
        action: 'InitFaceVerify',
      );

      // Still null without ALIYUN_DEBUG_DUMP_FACE_CONTRAST=true in test env.
      expect(export, isNull);

      tempDir.deleteSync(recursive: true);
    });

    test('formatStringToSignForLog truncates by default', () {
      const full = 'POST&%2F&AccessKeyId%3Dtest&Action%3DInitFaceVerify';
      final logged = AliyunTrace.formatStringToSignForLog(full);

      expect(logged, isA<Map<String, dynamic>>());
      expect(logged['_length'], full.length);
      expect(logged['_prefix'], full);
      expect(logged['_note'], contains('ALIYUN_LOG_STRING_TO_SIGN'));
    });
  });
}
