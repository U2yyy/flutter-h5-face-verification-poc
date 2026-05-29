import '../../models/face_verification_result.dart';

/// Parses FinAuth get_token / get_result responses into [FaceVerificationResult].
class FinAuthFaceVerificationResponseParser {
  const FinAuthFaceVerificationResponseParser({
    required this.providerId,
    required this.providerName,
    this.matchThresholdKey = '1e-4',
  });

  final String providerId;
  final String providerName;
  final String matchThresholdKey;

  static const getTokenAction = 'finauth/lite/get_token';
  static const getResultAction = 'finauth/lite/get_result';

  FaceVerificationResult parseH5SessionReady({
    required Duration latency,
    required String token,
    required String bizId,
    required String verificationUrl,
    String? requestId,
  }) {
    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: true,
      isMatch: false,
      isLive: false,
      sdkToken: bizId,
      verificationUrl: verificationUrl,
      requestId: requestId,
      apiAction: getTokenAction,
      description:
          'H5 session ready (token issued). Open DoVerification URL in WebView, '
          'then poll get_result with biz_id.',
      resultCode: token,
    );
  }

  FaceVerificationResult parseGetResultResponse({
    required Map<String, dynamic> response,
    required Duration latency,
    required String bizId,
  }) {
    final requestId = response['request_id'] as String?;
    final status = response['status'] as String?;
    final failReason = response['fail_reason'] as String?;

    if (status != 'OK') {
      return FaceVerificationResult(
        providerId: providerId,
        providerName: providerName,
        latency: latency,
        success: true,
        isMatch: false,
        isLive: false,
        resultCode: status,
        description: failReason != null
            ? 'FinAuth flow status=$status ($failReason)'
            : 'FinAuth flow status=$status',
        requestId: requestId,
        sdkToken: bizId,
        apiAction: getResultAction,
      );
    }

    final liveness = response['liveness_result'] as Map<String, dynamic>?;
    final verify = response['verify_result'] as Map<String, dynamic>?;

    final livenessResult = liveness?['result'] as String?;
    final isLive = livenessResult == 'PASS';

    final ref1 = verify?['result_ref1'] as Map<String, dynamic>?;
    final confidence = (ref1?['confidence'] as num?)?.toDouble();
    final thresholds = ref1?['thresholds'] as Map<String, dynamic>?;
    final threshold = (thresholds?[matchThresholdKey] as num?)?.toDouble();
    final isMatch = confidence != null &&
        threshold != null &&
        confidence >= threshold;

    final verifyError = verify?['error_message'] as String?;

    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: true,
      isMatch: isMatch,
      isLive: isLive,
      similarity: confidence,
      livenessScore: isLive ? 100 : 0,
      resultCode: status,
      description: _buildDescription(
        isMatch: isMatch,
        isLive: isLive,
        confidence: confidence,
        threshold: threshold,
        verifyError: verifyError,
        procedureType: liveness?['procedure_type'] as String?,
      ),
      requestId: requestId,
      sdkToken: bizId,
      apiAction: getResultAction,
      errorMessage: verifyError,
    );
  }

  FaceVerificationResult failure({
    required Duration latency,
    required String message,
    String? requestId,
    String? errorCode,
    String? apiAction,
    String? errorExplanationZh,
    String? errorSuggestedFix,
  }) {
    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: false,
      isMatch: false,
      isLive: false,
      errorMessage: errorCode != null ? '$errorCode: $message' : message,
      errorCode: errorCode,
      errorExplanationZh: errorExplanationZh,
      errorSuggestedFix: errorSuggestedFix,
      requestId: requestId,
      apiAction: apiAction,
    );
  }

  FaceVerificationResult unsupportedFlow({required String flowName}) {
    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: Duration.zero,
      success: false,
      isMatch: false,
      isLive: false,
      errorMessage: '$flowName is not supported by FinAuth H5 Lite.',
    );
  }

  String _buildDescription({
    required bool isMatch,
    required bool isLive,
    required double? confidence,
    required double? threshold,
    required String? verifyError,
    required String? procedureType,
  }) {
    final parts = <String>[
      if (procedureType != null) 'Procedure: $procedureType',
      'Liveness: ${isLive ? 'PASS' : 'FAIL'}',
      if (confidence != null && threshold != null)
        'Match: ${isMatch ? 'pass' : 'fail'} '
            '(confidence ${confidence.toStringAsFixed(2)}, '
            'threshold $matchThresholdKey=${threshold.toStringAsFixed(1)})',
      if (verifyError != null && verifyError.isNotEmpty)
        'Verify error: $verifyError',
    ];
    return parts.join('; ');
  }
}
