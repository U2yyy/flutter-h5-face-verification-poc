import '../models/ekyc_launch_result.dart';
import 'tencent_ekyc_method_channel.dart';

/// Platform Channel contract for Tencent eKYC native SDK.
abstract class TencentEkycPlatform {
  static TencentEkycPlatform _instance = MethodChannelTencentEkycPlatform();

  /// Override for tests or alternate implementations.
  static set instance(TencentEkycPlatform platform) {
    _instance = platform;
  }

  /// Whether the native Tencent eKYC SDK is linked on this device.
  static Future<bool> isAvailable() => _instance.checkAvailable();

  /// Launch Tencent eKYC liveness UI with the SdkToken from GetFaceIdTokenIntl.
  static Future<EkycLaunchResult> startLiveness({
    required String sdkToken,
  }) =>
      _instance.launchLiveness(sdkToken: sdkToken);

  Future<bool> checkAvailable();
  Future<EkycLaunchResult> launchLiveness({required String sdkToken});
}
