import 'dart:math';
import 'dart:typed_data';

import '../../models/face_verification_result.dart';
import '../../utils/app_config.dart';
import '../../utils/media_utils.dart';
import '../face_verification_provider.dart';
import 'finauth_api_client.dart';
import 'finauth_face_verification_response_parser.dart';
import 'finauth_h5_service.dart';

/// Megvii FinAuth H5 Lite overseas face verification (liveness + 1:1 compare).
class FinAuthFaceVerificationService implements FaceVerificationProvider {
  FinAuthFaceVerificationService({
    FinAuthApiClient? client,
    FinAuthFaceVerificationResponseParser? parser,
  })  : _parser = parser ??
            FinAuthFaceVerificationResponseParser(
              providerId: _id,
              providerName: _displayName,
              matchThresholdKey: AppConfig.finauthMatchThresholdKey,
            ),
        _client = client ??
            FinAuthApiClient(
              apiKey: AppConfig.finauthApiKey,
              apiSecret: AppConfig.finauthApiSecret,
              apiHost: AppConfig.finauthApiHost,
            );

  static const _id = 'finauth';
  static const _displayName = 'Megvii FinAuth';

  final FinAuthApiClient _client;
  final FinAuthFaceVerificationResponseParser _parser;

  @override
  String get id => _id;

  @override
  String get displayName => _displayName;

  @override
  bool get isConfigured => AppConfig.hasFinAuthCredentials;

  bool get supportsH5Flow => AppConfig.hasFinAuthH5Config;

  bool get supportsNativeSdk => false;

  bool get supportsPureApi => false;

  @override
  Future<FaceVerificationResult> verifyWithReferenceAndVideo({
    required Uint8List referenceImageBytes,
    required Uint8List liveVideoBytes,
  }) async {
    return _parser.unsupportedFlow(flowName: 'Pure API');
  }

  /// H5 flow step 1: get_token with reference photo → token + DoVerification URL.
  Future<FaceVerificationResult> requestH5Session({
    required Uint8List referenceImageBytes,
    String? procedureType,
    String? sceneId,
  }) async {
    final stopwatch = Stopwatch()..start();
    const action = FinAuthFaceVerificationResponseParser.getTokenAction;

    try {
      if (!isConfigured) {
        throw FinAuthApiException(
          'Set FINAUTH_API_KEY and FINAUTH_API_SECRET in .env',
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

      final returnUrl = AppConfig.finauthH5ReturnUrl.trim();
      final notifyUrl = AppConfig.finauthNotifyUrl.trim();
      if (returnUrl.isEmpty || notifyUrl.isEmpty) {
        stopwatch.stop();
        return _parser.failure(
          latency: stopwatch.elapsed,
          message:
              'Set FINAUTH_H5_RETURN_URL and FINAUTH_NOTIFY_URL in .env.',
          apiAction: action,
        );
      }

      final response = await _client.getToken(
        returnUrl: returnUrl,
        notifyUrl: notifyUrl,
        bizNo: _generateBizNo(),
        comparisonType: AppConfig.finauthComparisonType,
        uuid: AppConfig.finauthUserUuid,
        referenceImageBytes: referenceImageBytes,
        sceneId: sceneId ?? AppConfig.finauthSceneId,
        procedureType: procedureType ?? AppConfig.finauthProcedureType,
        procedurePriority: AppConfig.finauthProcedurePriority,
        language: AppConfig.finauthLanguage,
        actionHttpMethod: AppConfig.finauthActionHttpMethod,
        redirectType: AppConfig.finauthRedirectType,
        fmpMode: AppConfig.finauthFmpMode,
      );

      final token = response['token'] as String?;
      final bizId = response['biz_id'] as String?;

      if (token == null || token.isEmpty || bizId == null || bizId.isEmpty) {
        stopwatch.stop();
        return _parser.failure(
          latency: stopwatch.elapsed,
          message: 'Missing token or biz_id in get_token response',
          requestId: response['request_id'] as String?,
          apiAction: action,
        );
      }

      final session = FinAuthH5UrlBuilder.buildSession(
        token: token,
        bizId: bizId,
        requestId: response['request_id'] as String?,
        expiredTime: response['expired_time'] as int?,
        returnUrl: returnUrl,
      );

      stopwatch.stop();
      return _parser.parseH5SessionReady(
        latency: stopwatch.elapsed,
        token: token,
        bizId: bizId,
        verificationUrl: session.verificationUrl,
        requestId: response['request_id'] as String?,
      );
    } on FinAuthApiException catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.message,
        requestId: e.requestId,
        errorCode: e.httpStatus?.toString(),
        apiAction: action,
        errorExplanationZh: 'get_token 失败',
        errorSuggestedFix:
            '检查 FINAUTH_API_KEY/SECRET、return_url/notify_url 及参考图是否含单张正脸。',
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

  /// H5 flow step 2: get_result after return_url callback with biz_id.
  Future<FaceVerificationResult> fetchH5VerificationResult({
    required String bizId,
  }) async {
    final stopwatch = Stopwatch()..start();
    const action = FinAuthFaceVerificationResponseParser.getResultAction;

    try {
      if (!isConfigured) {
        throw FinAuthApiException(
          'Set FINAUTH_API_KEY and FINAUTH_API_SECRET in .env',
        );
      }

      final response = await _client.getResult(bizId: bizId);

      stopwatch.stop();
      return _parser.parseGetResultResponse(
        response: response,
        latency: stopwatch.elapsed,
        bizId: bizId,
      );
    } on FinAuthApiException catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.message,
        requestId: e.requestId,
        errorCode: e.httpStatus?.toString(),
        apiAction: action,
        errorExplanationZh: 'get_result 失败',
        errorSuggestedFix:
            'biz_id 仅可查询 3 次且保留 1 天；确认 H5 流程已完成且 status=OK。',
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

  static String _generateBizNo() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final suffix = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'facedetection-$now-$suffix';
  }
}
