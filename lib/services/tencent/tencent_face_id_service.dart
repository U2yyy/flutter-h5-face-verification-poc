import 'dart:convert';
import 'dart:typed_data';

import '../../models/ekyc_launch_result.dart';
import '../../models/face_verification_result.dart';
import '../../utils/app_config.dart';
import '../../utils/media_utils.dart';
import '../face_verification_provider.dart';
import 'tencent_api_client.dart';
import 'tencent_ekyc_bridge.dart';
import 'tencent_face_id_response_parser.dart';
import 'tencent_h5_service.dart';

class TencentFaceIdService implements FaceVerificationProvider {
  TencentFaceIdService({
    TencentApiClient? client,
    TencentFaceIdResponseParser? parser,
  })  : _client = client ??
            TencentApiClient(
              secretId: AppConfig.tencentSecretId,
              secretKey: AppConfig.tencentSecretKey,
              region: AppConfig.tencentRegion,
              host: AppConfig.tencentFaceIdHost,
            ),
        _parser = parser ??
            const TencentFaceIdResponseParser(
              providerId: 'tencent_faceid',
              providerName: 'Tencent FaceID',
            );

  final TencentApiClient _client;
  final TencentFaceIdResponseParser _parser;

  bool get _isIntlHost => _client.host.contains('.intl.');

  @override
  String get id => 'tencent_faceid';

  @override
  String get displayName => 'Tencent FaceID';

  @override
  bool get isConfigured => AppConfig.hasTencentCredentials;

  @override
  Future<FaceVerificationResult> verifyWithReferenceAndVideo({
    required Uint8List referenceImageBytes,
    required Uint8List liveVideoBytes,
  }) async {
    final stopwatch = Stopwatch()..start();
    final action = _isIntlHost ? 'CompareFaceLiveness' : 'LivenessCompare';

    try {
      _ensureConfigured();

      final imageError = MediaUtils.validateImageForApi(referenceImageBytes);
      if (imageError != null) {
        stopwatch.stop();
        return _failureResult(
          action: action,
          latency: stopwatch.elapsed,
          errorMessage: imageError,
        );
      }

      final videoError = MediaUtils.validateVideoForApi(liveVideoBytes);
      if (videoError != null) {
        stopwatch.stop();
        return _failureResult(
          action: action,
          latency: stopwatch.elapsed,
          errorMessage: videoError,
        );
      }

      final response = await _client.callAction(
        action: action,
        payload: {
          'LivenessType': AppConfig.tencentFaceIdLivenessType,
          'ImageBase64': base64Encode(referenceImageBytes),
          'VideoBase64': base64Encode(liveVideoBytes),
          if (AppConfig.tencentFaceIdLivenessType == 'ACTION' &&
              AppConfig.tencentFaceIdValidateData.isNotEmpty)
            'ValidateData': AppConfig.tencentFaceIdValidateData,
        },
      );

      stopwatch.stop();
      return _parser.parsePureApiResponse(
        response: response,
        action: action,
        latency: stopwatch.elapsed,
      );
    } on TencentApiException catch (e) {
      stopwatch.stop();
      return _failureResult(
        action: action,
        latency: stopwatch.elapsed,
        errorMessage: '${e.code}: ${e.message}',
        requestId: e.requestId,
      );
    } catch (e) {
      stopwatch.stop();
      return _failureResult(
        action: action,
        latency: stopwatch.elapsed,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<FaceVerificationResult> requestSdkToken({
    required Uint8List referenceImageBytes,
  }) async {
    final stopwatch = Stopwatch()..start();
    final action = _isIntlHost ? 'GetFaceIdTokenIntl' : 'GetFaceIdToken';

    try {
      _ensureConfigured();

      final Map<String, dynamic> payload;
      if (_isIntlHost) {
        payload = {
          'CheckMode': 'compare',
          'SecureLevel': AppConfig.tencentFaceIdSecureLevel,
          'Image': base64Encode(referenceImageBytes),
          if (AppConfig.tencentFaceIdSdkVersion.isNotEmpty)
            'SdkVersion': AppConfig.tencentFaceIdSdkVersion,
        };
      } else {
        payload = {
          'CompareLib': 'LOCAL',
          'ImageBase64': base64Encode(referenceImageBytes),
          if (AppConfig.tencentFaceIdRuleId.isNotEmpty)
            'RuleId': AppConfig.tencentFaceIdRuleId,
        };
      }

      final response = await _client.callAction(
        action: action,
        payload: payload,
        region: _isIntlHost ? _client.region : '',
      );

      stopwatch.stop();
      final sdkToken = _isIntlHost
          ? response['SdkToken'] as String?
          : response['FaceIdToken'] as String?;

      if (sdkToken == null || sdkToken.isEmpty) {
        return _failureResult(
          action: action,
          latency: stopwatch.elapsed,
          errorMessage: 'Missing SdkToken in response',
          requestId: response['RequestId'] as String?,
        );
      }

      return FaceVerificationResult(
        providerId: id,
        providerName: displayName,
        latency: stopwatch.elapsed,
        success: true,
        isMatch: false,
        isLive: false,
        sdkToken: sdkToken,
        requestId: response['RequestId'] as String?,
        apiAction: action,
        description:
            'SdkToken issued. Pass it to the Tencent eKYC SDK, then poll for results.',
      );
    } on TencentApiException catch (e) {
      stopwatch.stop();
      return _failureResult(
        action: action,
        latency: stopwatch.elapsed,
        errorMessage: '${e.code}: ${e.message}',
        requestId: e.requestId,
      );
    } catch (e) {
      stopwatch.stop();
      return _failureResult(
        action: action,
        latency: stopwatch.elapsed,
        errorMessage: e.toString(),
      );
    }
  }

  /// SaaS SDK flow: launch native Tencent eKYC liveness UI.
  Future<EkycLaunchResult> startEkycLiveness({required String sdkToken}) {
    return TencentEkycBridge.startLiveness(sdkToken: sdkToken);
  }

  /// Whether the native Tencent eKYC SDK is available on this device.
  Future<bool> isEkycSdkAvailable() => TencentEkycBridge.isAvailable();

  /// H5 flow step 1: ApplyWebVerificationBizToken(Intl) → BizToken + URL.
  Future<FaceVerificationResult> requestH5Session({
    required Uint8List referenceImageBytes,
  }) async {
    final stopwatch = Stopwatch()..start();
    final action = _isIntlHost
        ? 'ApplyWebVerificationBizTokenIntl'
        : 'ApplyWebVerificationBizToken';

    try {
      _ensureConfigured();

      final imageError = MediaUtils.validateImageForApi(referenceImageBytes);
      if (imageError != null) {
        stopwatch.stop();
        return _failureResult(
          action: action,
          latency: stopwatch.elapsed,
          errorMessage: imageError,
        );
      }

      final redirectUrl = AppConfig.tencentFaceIdH5RedirectUrl.trim();
      if (redirectUrl.isEmpty) {
        stopwatch.stop();
        return _failureResult(
          action: action,
          latency: stopwatch.elapsed,
          errorMessage:
              'Set TENCENT_FACEID_H5_REDIRECT_URL in .env for H5 callback.',
        );
      }

      final payload = <String, dynamic>{
        'RedirectURL': redirectUrl,
        'CompareImageBase64': base64Encode(referenceImageBytes),
        if (AppConfig.tencentFaceIdRuleId.isNotEmpty)
          'RuleId': AppConfig.tencentFaceIdRuleId,
        if (AppConfig.tencentFaceIdH5AutoSkip)
          'Config': {'AutoSkip': true},
      };

      final response = await _client.callAction(
        action: action,
        payload: payload,
        region: _isIntlHost ? _client.region : '',
      );

      stopwatch.stop();
      final bizToken = response['BizToken'] as String?;
      final verificationUrl = response['VerificationURL'] as String?;

      if (bizToken == null ||
          bizToken.isEmpty ||
          verificationUrl == null ||
          verificationUrl.isEmpty) {
        return _failureResult(
          action: action,
          latency: stopwatch.elapsed,
          errorMessage: 'Missing BizToken or VerificationURL in response',
          requestId: response['RequestId'] as String?,
        );
      }

      return FaceVerificationResult(
        providerId: id,
        providerName: displayName,
        latency: stopwatch.elapsed,
        success: true,
        isMatch: false,
        isLive: false,
        sdkToken: bizToken,
        verificationUrl: verificationUrl,
        requestId: response['RequestId'] as String?,
        apiAction: action,
        description:
            'H5 session ready. Open VerificationURL in WebView, then poll results.',
      );
    } on TencentApiException catch (e) {
      stopwatch.stop();
      return _failureResult(
        action: action,
        latency: stopwatch.elapsed,
        errorMessage: '${e.code}: ${e.message}',
        requestId: e.requestId,
      );
    } catch (e) {
      stopwatch.stop();
      return _failureResult(
        action: action,
        latency: stopwatch.elapsed,
        errorMessage: e.toString(),
      );
    }
  }

  /// Builds an [TencentH5Session] from stored H5 request fields.
  TencentH5Session buildH5Session({
    required String bizToken,
    required String verificationUrl,
  }) {
    return TencentH5Session(
      bizToken: bizToken,
      verificationUrl: verificationUrl,
      redirectUrl: AppConfig.tencentFaceIdH5RedirectUrl,
    );
  }

  /// H5 flow step 2: poll GetWebVerificationResult(Intl) after WebView redirect.
  Future<FaceVerificationResult> fetchH5VerificationResult({
    required String bizToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    final action = _isIntlHost
        ? 'GetWebVerificationResultIntl'
        : 'GetWebVerificationResult';

    try {
      _ensureConfigured();

      final response = await _client.callAction(
        action: action,
        payload: {'BizToken': bizToken},
        region: _isIntlHost ? _client.region : '',
      );

      stopwatch.stop();
      return _parser.parseH5ResultResponse(
        response: response,
        action: action,
        latency: stopwatch.elapsed,
        bizToken: bizToken,
      );
    } on TencentApiException catch (e) {
      stopwatch.stop();
      return _failureResult(
        action: action,
        latency: stopwatch.elapsed,
        errorMessage: '${e.code}: ${e.message}',
        requestId: e.requestId,
        sdkToken: bizToken,
      );
    } catch (e) {
      stopwatch.stop();
      return _failureResult(
        action: action,
        latency: stopwatch.elapsed,
        errorMessage: e.toString(),
        sdkToken: bizToken,
      );
    }
  }

  @override
  Future<FaceVerificationResult> fetchSdkVerificationResult({
    required String sdkToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    final action = _isIntlHost ? 'GetFaceIdResultIntl' : 'GetFaceIdResult';

    try {
      _ensureConfigured();

      final payload = _isIntlHost
          ? {'SdkToken': sdkToken}
          : {'FaceIdToken': sdkToken};

      final response = await _client.callAction(
        action: action,
        payload: payload,
        region: _isIntlHost ? _client.region : '',
      );

      stopwatch.stop();
      return _parser.parseSdkResultResponse(
        response: response,
        action: action,
        latency: stopwatch.elapsed,
        sdkToken: sdkToken,
      );
    } on TencentApiException catch (e) {
      stopwatch.stop();
      return _failureResult(
        action: action,
        latency: stopwatch.elapsed,
        errorMessage: '${e.code}: ${e.message}',
        requestId: e.requestId,
        sdkToken: sdkToken,
      );
    } catch (e) {
      stopwatch.stop();
      return _failureResult(
        action: action,
        latency: stopwatch.elapsed,
        errorMessage: e.toString(),
        sdkToken: sdkToken,
      );
    }
  }

  void _ensureConfigured() {
    if (!isConfigured) {
      throw TencentApiException(
        'MissingCredentials',
        'Set TENCENT_SECRET_ID and TENCENT_SECRET_KEY in .env',
      );
    }
  }

  FaceVerificationResult _failureResult({
    required String action,
    required Duration latency,
    required String errorMessage,
    String? requestId,
    String? sdkToken,
  }) {
    return FaceVerificationResult(
      providerId: id,
      providerName: displayName,
      latency: latency,
      success: false,
      isMatch: false,
      isLive: false,
      errorMessage: errorMessage,
      requestId: requestId,
      sdkToken: sdkToken,
      apiAction: action,
    );
  }
}
