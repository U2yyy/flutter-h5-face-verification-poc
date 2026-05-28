import '../../models/ekyc_launch_result.dart';
import '../../platform/tencent_ekyc_platform.dart';

/// High-level bridge from Flutter business code to the native Tencent eKYC SDK.
class TencentEkycBridge {
  const TencentEkycBridge._();

  /// Whether the native SDK binaries are present on this platform.
  static Future<bool> isAvailable() => TencentEkycPlatform.isAvailable();

  /// Runs liveness capture in the Tencent eKYC SDK.
  ///
  /// [sdkToken] must come from [TencentFaceIdService.requestSdkToken].
  static Future<EkycLaunchResult> startLiveness({
    required String sdkToken,
  }) {
    if (sdkToken.trim().isEmpty) {
      return Future.value(
        const EkycLaunchResult(
          success: false,
          errorCode: 'INVALID_TOKEN',
          errorMessage: 'SdkToken is empty',
        ),
      );
    }
    return TencentEkycPlatform.startLiveness(sdkToken: sdkToken);
  }
}
