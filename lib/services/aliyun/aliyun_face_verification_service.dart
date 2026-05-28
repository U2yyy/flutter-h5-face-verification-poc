import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../models/face_verification_result.dart';
import '../../utils/aliyun_trace.dart';
import '../../utils/app_config.dart';
import '../../utils/media_utils.dart';
import '../face_verification_provider.dart';
import 'aliyun_cloudauth_api_client.dart';
import 'aliyun_face_verification_response_parser.dart';

/// Aliyun CloudAuth PV_FV H5 liveness + face contrast verification.
class AliyunFaceVerificationService implements FaceVerificationProvider {
  AliyunFaceVerificationService({
    AliyunCloudAuthApiClient? client,
    AliyunFaceVerificationResponseParser? parser,
  })  : _parser = parser ??
            AliyunFaceVerificationResponseParser(
              providerId: _id,
              providerName: _displayName,
              matchThreshold: AppConfig.aliyunMatchThreshold,
            ),
        _client = client ??
            AliyunCloudAuthApiClient(
              accessKeyId: AppConfig.aliyunAccessKeyId,
              accessKeySecret: AppConfig.aliyunAccessKeySecret,
              regionId: AppConfig.aliyunCloudAuthRegionId,
            );

  static const _id = 'aliyun_cloudauth';
  static const _displayName = 'Aliyun CloudAuth';

  final AliyunCloudAuthApiClient _client;
  final AliyunFaceVerificationResponseParser _parser;

  @override
  String get id => _id;

  @override
  String get displayName => _displayName;

  @override
  bool get isConfigured => AppConfig.hasAliyunCredentials;

  bool get supportsH5Flow => AppConfig.hasAliyunH5Config;

  bool get supportsNativeSdk => false;

  @override
  Future<FaceVerificationResult> verifyWithReferenceAndVideo({
    required Uint8List referenceImageBytes,
    required Uint8List liveVideoBytes,
  }) async {
    return _parser.unsupportedFlow(flowName: 'Pure API');
  }

  static const _initFaceVerifyTimeout = Duration(seconds: 60);
  static const _describeFaceVerifyTimeout = Duration(seconds: 60);

  /// H5 flow step 1: InitFaceVerify with reference photo + MetaInfo from WebView JS.
  ///
  /// When [AppConfig.aliyunUsesFaceContrastPictureUrl] is true, [referenceImageBytes]
  /// is ignored and InitFaceVerify sends FaceContrastPictureUrl only.
  Future<FaceVerificationResult> requestH5Session({
    Uint8List? referenceImageBytes,
    required String metaInfo,
    required String model,
  }) async {
    final stopwatch = AliyunTrace.start();
    const action = AliyunFaceVerificationResponseParser.initFaceVerifyAction;
    final usesPictureUrl = AppConfig.aliyunUsesFaceContrastPictureUrl;

    try {
      _ensureConfigured();

      final trimmedModel = model.trim();
      if (trimmedModel.isEmpty) {
        throw AliyunCloudAuthException(
          '400',
          'Select an Aliyun H5 liveness model.',
        );
      }

      final metaOverride = AppConfig.aliyunCloudAuthMetaInfoOverride.trim();
      final trimmedMeta =
          metaOverride.isNotEmpty ? metaOverride : metaInfo.trim();
      if (trimmedMeta.isEmpty) {
        throw AliyunCloudAuthException(
          '400',
          'MetaInfo is required. Load Aliyun jsvm_all.js getMetaInfo() first, '
          'or set ALIYUN_CLOUDAUTH_METAINFO_OVERRIDE for Explorer-style testing.',
        );
      }

      if (!usesPictureUrl) {
        if (referenceImageBytes == null || referenceImageBytes.isEmpty) {
          stopwatch.stop();
          return _parser.failure(
            latency: stopwatch.elapsed,
            message:
                'Reference photo is required when ALIYUN_CLOUDAUTH_FACE_CONTRAST_PICTURE_URL is not set.',
            apiAction: action,
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
      }

      final returnUrl = AppConfig.aliyunCloudAuthReturnUrl.trim();
      if (returnUrl.isEmpty) {
        stopwatch.stop();
        return _parser.failure(
          latency: stopwatch.elapsed,
          message:
              'Set ALIYUN_CLOUDAUTH_RETURN_URL in .env for H5 redirect detection.',
          apiAction: action,
        );
      }

      final sceneId = AppConfig.aliyunCloudAuthSceneId.trim();
      if (sceneId.isEmpty) {
        stopwatch.stop();
        return _parser.failure(
          latency: stopwatch.elapsed,
          message: 'Set ALIYUN_CLOUDAUTH_SCENE_ID in .env.',
          apiAction: action,
        );
      }

      final certifyUrlType = AppConfig.aliyunCloudAuthCertifyUrlType.trim();
      final certifyUrlStyle = AppConfig.aliyunCloudAuthCertifyUrlStyle.trim();
      final procedurePriority =
          AppConfig.aliyunCloudAuthProcedurePriority.trim();
      final callbackUrl = AppConfig.aliyunCloudAuthCallbackUrl.trim();
      final voluntaryContent =
          AppConfig.aliyunCloudAuthVoluntaryCustomizedContent.trim();
      final sourceIp = AppConfig.aliyunCloudAuthSourceIp.trim();

      final response = await _client
          .initFaceVerify(
            sceneId: sceneId,
            outerOrderNo: _outerOrderNo(),
            userId: AppConfig.aliyunCloudAuthUserId,
            metaInfo: trimmedMeta,
            returnUrl: returnUrl,
            faceContrastPictureBytes:
                usesPictureUrl ? null : referenceImageBytes,
            faceContrastPictureUrl: usesPictureUrl
                ? AppConfig.aliyunCloudAuthFaceContrastPictureUrl.trim()
                : null,
            model: trimmedModel,
            crop: AppConfig.aliyunCloudAuthCrop,
            callbackUrl: callbackUrl.isEmpty ? null : callbackUrl,
            voluntaryCustomizedContent:
                voluntaryContent.isEmpty ? null : voluntaryContent,
            sourceIp: sourceIp.isEmpty ? null : sourceIp,
            certifyUrlType:
                certifyUrlType.isEmpty ? null : certifyUrlType,
            certifyUrlStyle:
                certifyUrlStyle.isEmpty ? null : certifyUrlStyle,
            procedurePriority:
                procedurePriority.isEmpty ? null : procedurePriority,
          )
          .timeout(_initFaceVerifyTimeout);

      final resultObject =
          response['ResultObject'] as Map<String, dynamic>? ?? {};
      final certifyId = resultObject['CertifyId'] as String?;
      final certifyUrl = resultObject['CertifyUrl'] as String?;

      if (certifyId == null || certifyId.isEmpty) {
        stopwatch.stop();
        return _parser.failure(
          latency: stopwatch.elapsed,
          message: 'Missing CertifyId in InitFaceVerify response',
          requestId: response['RequestId'] as String?,
          apiAction: action,
        );
      }

      stopwatch.stop();
      return _parser.parseH5SessionReady(
        latency: stopwatch.elapsed,
        certifyId: certifyId,
        certifyUrl: certifyUrl,
        requestId: response['RequestId'] as String?,
      );
    } on TimeoutException {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message:
            'InitFaceVerify timed out after ${_initFaceVerifyTimeout.inSeconds}s.',
        apiAction: action,
      );
    } on AliyunCloudAuthException catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.message,
        requestId: e.requestId,
        errorCode: e.code,
        apiAction: action,
      );
    } catch (e) {
      stopwatch.stop();
      final message = e.toString().contains('ClientException')
          ? 'InitFaceVerify request cancelled or connection closed.'
          : e.toString();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: message,
        apiAction: action,
      );
    }
  }

  /// H5 flow step 2: DescribeFaceVerify after WebView ReturnUrl redirect.
  Future<FaceVerificationResult> fetchH5VerificationResult({
    required String certifyId,
  }) async {
    final stopwatch = AliyunTrace.start();
    const action = AliyunFaceVerificationResponseParser.describeFaceVerifyAction;

    try {
      _ensureConfigured();

      final sceneId = AppConfig.aliyunCloudAuthSceneId.trim();
      if (sceneId.isEmpty) {
        throw AliyunCloudAuthException('400', 'Missing ALIYUN_CLOUDAUTH_SCENE_ID');
      }

      final response = await _client
          .describeFaceVerify(
            sceneId: sceneId,
            certifyId: certifyId,
          )
          .timeout(_describeFaceVerifyTimeout);

      stopwatch.stop();
      return _parser.parseDescribeResponse(
        response: response,
        latency: stopwatch.elapsed,
        certifyId: certifyId,
      );
    } on TimeoutException {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message:
            'DescribeFaceVerify timed out after ${_describeFaceVerifyTimeout.inSeconds}s.',
        apiAction: action,
      );
    } on AliyunCloudAuthException catch (e) {
      stopwatch.stop();
      return _parser.failure(
        latency: stopwatch.elapsed,
        message: e.message,
        requestId: e.requestId,
        errorCode: e.code,
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

  /// Aborts an in-flight InitFaceVerify/DescribeFaceVerify HTTP request.
  void cancelInflightRequest() => _client.cancelInflightRequest();

  void _ensureConfigured() {
    if (!isConfigured) {
      throw AliyunCloudAuthException(
        '401',
        'Set ALIYUN_ACCESS_KEY_ID and ALIYUN_ACCESS_KEY_SECRET in .env',
      );
    }
  }

  static String _outerOrderNo() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

}
