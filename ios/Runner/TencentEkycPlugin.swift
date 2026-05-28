import Flutter
import UIKit

/// Platform Channel bridge for Tencent eKYC (HuiYan Overseas) SDK.
///
/// Compiles without the SDK framework. When `HuiYanOverseasSDK.xcframework` is added
/// and `TENCENT_EKYC_SDK_ENABLED` is set, real SDK calls are used.
///
/// SDK docs: https://www.tencentcloud.com/document/product/1061/46853
final class TencentEkycPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.facedetection/tencent_ekyc"

  // Set to true after integrating HuiYanOverseasSDK.xcframework (see README).
  private static let sdkIntegrationEnabled = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = TencentEkycPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(Self.isSdkAvailable())
    case "startLiveness":
      guard let args = call.arguments as? [String: Any],
            let sdkToken = args["sdkToken"] as? String,
            !sdkToken.isEmpty
      else {
        result([
          "success": false,
          "errorCode": "INVALID_TOKEN",
          "errorMessage": "sdkToken is required",
        ])
        return
      }
      startLiveness(sdkToken: sdkToken, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func isSdkAvailable() -> Bool {
    #if canImport(HuiYanOverseasSDK)
    return sdkIntegrationEnabled
    #else
    return false
    #endif
  }

  private func startLiveness(sdkToken: String, result: @escaping FlutterResult) {
    #if canImport(HuiYanOverseasSDK)
    guard Self.sdkIntegrationEnabled else {
      result(sdkNotConfiguredPayload())
      return
    }

    // TODO: Uncomment after adding HuiYanOverseasSDK.xcframework and license files.
    /*
    let config = HuiYanOsConfig()
    config.authLicense = Bundle.main.path(forResource: "YTFaceSDK", ofType: "license")
    config.prepareTimeoutMs = 20000
    config.actionTimeoutMs = 20000
    config.isDeleteVideoCache = true

    HuiYanOSKit.sharedInstance().startHuiYaneKYC(
      sdkToken,
      withConfig: config,
      witSuccCallback: { authResult, _ in
        result([
          "success": true,
          "extra": [
            "faceToken": authResult.faceToken ?? "",
          ],
        ])
      },
      withFailCallback: { errCode, errMsg, _ in
        result([
          "success": false,
          "errorCode": String(errCode),
          "errorMessage": errMsg,
        ])
      }
    )
    */
    result(sdkNotConfiguredPayload())
    #else
    result(sdkNotConfiguredPayload())
    #endif
  }

  private func sdkNotConfiguredPayload() -> [String: Any] {
    [
      "success": false,
      "errorCode": "SDK_NOT_CONFIGURED",
      "errorMessage":
        "Tencent eKYC SDK not integrated. Add HuiYanOverseasSDK.xcframework, " +
        "license files, and set sdkIntegrationEnabled = true (see README).",
    ]
  }
}
