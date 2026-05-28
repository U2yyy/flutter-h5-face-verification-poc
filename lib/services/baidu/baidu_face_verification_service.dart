import 'dart:convert';
import 'dart:typed_data';

import '../../models/face_verification_result.dart';
import '../../utils/app_config.dart';
import '../../utils/media_utils.dart';
import '../face_verification_provider.dart';
import 'baidu_api_client.dart';
import 'baidu_auth_client.dart';
import 'baidu_face_verification_response_parser.dart';
import 'baidu_h5_service.dart';

/// Baidu Pure-API verification: silent video liveness + face 1:1 match.
class BaiduFaceVerificationService implements FaceVerificationProvider {
  BaiduFaceVerificationService({
    BaiduApiClient? client,
    BaiduAuthClient? authClient,
    BaiduFaceVerificationResponseParser? parser,
  })  : _parser = parser ??
            BaiduFaceVerificationResponseParser(
              providerId: _id,
              providerName: _displayName,
              matchThreshold: AppConfig.baiduMatchThreshold,
              livenessThresholdKey: AppConfig.baiduLivenessThresholdKey,
            ),
        _client = client ??
            BaiduApiClient(
              authClient: authClient ??
                  BaiduAuthClient(
                    apiKey: AppConfig.baiduApiKey,
                    secretKey: AppConfig.baiduSecretKey,
                  ),
            );

  static const _id = 'baidu';
  static const _displayName = 'Baidu AI';

  final BaiduApiClient _client;
  final BaiduFaceVerificationResponseParser _parser;

  @override
  String get id => _id;

  @override
  String get displayName => _displayName;

  @override
  bool get isConfigured => AppConfig.hasBaiduCredentials;

  /// Baidu supports Pure API and faceprint H5 SaaS (not native SDK).
  bool get supportsH5Flow => AppConfig.hasBaiduH5Config;

  bool get supportsNativeSdk => false;

  @override
  Future<FaceVerificationResult> verifyWithReferenceAndVideo({
    required Uint8List referenceImageBytes,
    required Uint8List liveVideoBytes,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      if (!isConfigured) {
        throw BaiduAuthException(
          'Set BAIDU_API_KEY and BAIDU_SECRET_KEY in .env',
        );
      }

      final imageError = MediaUtils.validateImageForApi(referenceImageBytes);
      if (imageError != null) {
        stopwatch.stop();
        return _parser.failure(
          latency: stopwatch.elapsed,
          message: imageError,
          apiAction: BaiduFaceVerificationResponseParser.matchAction,
        );
      }

      final videoError = MediaUtils.validateVideoForBaiduApi(liveVideoBytes);
      if (videoError != null) {
        stopwatch.stop();
        return _parser.failure(
          latency: stopwatch.elapsed,
          message: videoError,
          apiAction: BaiduFaceVerificationResponseParser.videoLivenessAction,
        );
      }

      final liveness = await _client.verifyVideoLiveness(
        videoBase64: base64Encode(liveVideoBytes),
      );

      final matchResponse = await _client.matchFaces([
        {
          'image': base64Encode(referenceImageBytes),
          'image_type': 'BASE64',
          'face_type': 'CERT',
          'quality_control': AppConfig.baiduQualityControl,
          'liveness_control': 'NONE',
        },
        {
          'image': liveness.bestImageBase64,
          'image_type': 'BASE64',
          'face_type': 'LIVE',
          'quality_control': AppConfig.baiduQualityControl,
          'liveness_control': AppConfig.baiduLivenessControl,
        },
      ]);

      stopwatch.stop();
      return _parser.parseCombined(
        liveness: liveness,
        matchResponse: matchResponse,
        latency: stopwatch.elapsed,
      );
    } on BaiduApiException catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.message,
        requestId: e.logId?.toString(),
        errorCode: e.code,
      );
    } on BaiduAuthException catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.message,
      );
    } catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.toString(),
      );
    }
  }

  /// H5 flow step 1: verifyToken/generate + uploadMatchImage → verify_token + URL.
  Future<FaceVerificationResult> requestH5Session({
    required Uint8List referenceImageBytes,
    required String planId,
  }) async {
    final stopwatch = Stopwatch()..start();
    const action = BaiduFaceVerificationResponseParser.h5VerifyTokenAction;

    try {
      if (!isConfigured) {
        throw BaiduAuthException(
          'Set BAIDU_API_KEY and BAIDU_SECRET_KEY in .env',
        );
      }

      final trimmedPlanId = planId.trim();
      if (trimmedPlanId.isEmpty) {
        throw BaiduAuthException(
          'Select a Baidu H5 liveness method with a configured plan_id.',
        );
      }

      final imageError = MediaUtils.validateImageForApi(referenceImageBytes);
      if (imageError != null) {
        stopwatch.stop();
        return _parser.failure(
          latency: stopwatch.elapsed,
          message: imageError,
          apiAction: action,
        );
      }

      final callbackBase = AppConfig.baiduFaceprintH5CallbackUrl.trim();
      if (callbackBase.isEmpty) {
        stopwatch.stop();
        return _parser.failure(
          latency: stopwatch.elapsed,
          message:
              'Set BAIDU_FACEPRINT_H5_CALLBACK_URL in .env for H5 redirect.',
          apiAction: action,
        );
      }

      final tokenResponse =
          await _client.generateVerifyToken(planId: trimmedPlanId);
      final verifyToken = (tokenResponse['result']
              as Map<String, dynamic>?)?['verify_token'] as String? ??
          tokenResponse['verify_token'] as String?;

      if (verifyToken == null || verifyToken.isEmpty) {
        stopwatch.stop();
        return _parser.failure(
          latency: stopwatch.elapsed,
          message: 'Missing verify_token in generate response',
          requestId: tokenResponse['log_id']?.toString(),
          apiAction: action,
        );
      }

      final session = BaiduH5UrlBuilder.buildSession(
        verifyToken: verifyToken,
        requestId: tokenResponse['log_id']?.toString(),
        callbackBase: callbackBase,
      );

      await _client.uploadMatchImage(
        verifyToken: verifyToken,
        imageBase64: base64Encode(referenceImageBytes),
        qualityControl: AppConfig.baiduQualityControl,
        livenessControl: 'NONE',
      );

      stopwatch.stop();
      return _parser.parseH5SessionReady(
        latency: stopwatch.elapsed,
        verifyToken: verifyToken,
        verificationUrl: session.verificationUrl,
        requestId: tokenResponse['log_id']?.toString(),
      );
    } on BaiduApiException catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.message,
        requestId: e.logId?.toString(),
        errorCode: e.code,
        apiAction: action,
      );
    } on BaiduAuthException catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.message,
        apiAction: action,
      );
    } catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.toString(),
        apiAction: action,
      );
    }
  }

  /// H5 flow step 2: poll result/detail after WebView redirect.
  Future<FaceVerificationResult> fetchH5VerificationResult({
    required String verifyToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    const action = BaiduFaceVerificationResponseParser.h5ResultAction;

    try {
      if (!isConfigured) {
        throw BaiduAuthException(
          'Set BAIDU_API_KEY and BAIDU_SECRET_KEY in .env',
        );
      }

      final response = await _client.fetchVerificationDetail(
        verifyToken: verifyToken,
      );

      stopwatch.stop();
      return _parser.parseH5DetailResponse(
        response: response,
        latency: stopwatch.elapsed,
        verifyToken: verifyToken,
      );
    } on BaiduApiException catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.message,
        requestId: e.logId?.toString(),
        errorCode: e.code,
        apiAction: action,
      );
    } on BaiduAuthException catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.message,
        apiAction: action,
      );
    } catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.toString(),
        apiAction: action,
      );
    }
  }

  @override
  Future<FaceVerificationResult> requestSdkToken({
    required Uint8List referenceImageBytes,
  }) async {
    return _parser.unsupportedFlow(flowName: 'SaaS SDK');
  }

  @override
  Future<FaceVerificationResult> fetchSdkVerificationResult({
    required String sdkToken,
  }) async {
    return _parser.unsupportedFlow(flowName: 'SaaS SDK result polling');
  }
}
