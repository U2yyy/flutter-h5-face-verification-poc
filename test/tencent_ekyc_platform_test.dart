import 'package:facedetection/models/ekyc_launch_result.dart';
import 'package:facedetection/platform/tencent_ekyc_method_channel.dart';
import 'package:facedetection/platform/tencent_ekyc_platform.dart';
import 'package:facedetection/services/tencent/tencent_ekyc_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTencentEkycPlatform extends TencentEkycPlatform {
  FakeTencentEkycPlatform({
    this.available = true,
    this.launchResult = const EkycLaunchResult(success: true),
  });

  bool available;
  EkycLaunchResult launchResult;
  String? lastSdkToken;

  @override
  Future<bool> checkAvailable() async => available;

  @override
  Future<EkycLaunchResult> launchLiveness({required String sdkToken}) async {
    lastSdkToken = sdkToken;
    return launchResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EkycLaunchResult', () {
    test('fromMap parses success payload', () {
      final result = EkycLaunchResult.fromMap({
        'success': true,
        'extra': {'faceToken': 'abc'},
      });

      expect(result.success, isTrue);
      expect(result.extra?['faceToken'], 'abc');
    });

    test('fromMap handles null map', () {
      final result = EkycLaunchResult.fromMap(null);
      expect(result.success, isFalse);
      expect(result.errorCode, 'INVALID_RESPONSE');
    });
  });

  group('TencentEkycBridge', () {
    tearDown(() {
      TencentEkycPlatform.instance = MethodChannelTencentEkycPlatform();
    });

    test('rejects empty sdkToken without calling platform', () async {
      final fake = FakeTencentEkycPlatform();
      TencentEkycPlatform.instance = fake;

      final result = await TencentEkycBridge.startLiveness(sdkToken: '  ');

      expect(result.success, isFalse);
      expect(result.errorCode, 'INVALID_TOKEN');
      expect(fake.lastSdkToken, isNull);
    });

    test('delegates to platform implementation', () async {
      final fake = FakeTencentEkycPlatform(
        launchResult: const EkycLaunchResult(success: true),
      );
      TencentEkycPlatform.instance = fake;

      final result =
          await TencentEkycBridge.startLiveness(sdkToken: 'token-123');

      expect(result.success, isTrue);
      expect(fake.lastSdkToken, 'token-123');
    });
  });

  group('MethodChannelTencentEkycPlatform', () {
    const channel = MethodChannel('com.facedetection/tencent_ekyc');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('checkAvailable returns false when channel missing', () async {
      final platform = MethodChannelTencentEkycPlatform();
      expect(await platform.checkAvailable(), isFalse);
    });

    test('launchLiveness maps platform exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'SDK_NOT_CONFIGURED', message: 'No SDK');
      });

      final platform = MethodChannelTencentEkycPlatform();
      final result = await platform.launchLiveness(sdkToken: 't');

      expect(result.success, isFalse);
      expect(result.errorCode, 'SDK_NOT_CONFIGURED');
    });
  });
}
