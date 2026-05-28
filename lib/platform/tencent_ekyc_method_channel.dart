import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/ekyc_launch_result.dart';
import 'tencent_ekyc_platform.dart';

class MethodChannelTencentEkycPlatform extends TencentEkycPlatform {
  static const MethodChannel _channel =
      MethodChannel('com.facedetection/tencent_ekyc');

  @visibleForTesting
  static MethodChannel get channel => _channel;

  @override
  Future<bool> checkAvailable() async {
    try {
      final available = await _channel.invokeMethod<bool>('isAvailable');
      return available ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<EkycLaunchResult> launchLiveness({required String sdkToken}) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startLiveness',
        {'sdkToken': sdkToken},
      );
      return EkycLaunchResult.fromMap(result);
    } on PlatformException catch (e) {
      return EkycLaunchResult(
        success: false,
        errorCode: e.code,
        errorMessage: e.message ?? e.details?.toString(),
      );
    } on MissingPluginException {
      return const EkycLaunchResult(
        success: false,
        errorCode: 'SDK_NOT_CONFIGURED',
        errorMessage:
            'Tencent eKYC Platform Channel is not registered on this platform.',
      );
    }
  }
}
