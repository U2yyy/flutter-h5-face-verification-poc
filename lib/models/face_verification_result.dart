class FaceVerificationResult {
  const FaceVerificationResult({
    required this.providerId,
    required this.providerName,
    required this.latency,
    required this.success,
    required this.isMatch,
    required this.isLive,
    this.similarity,
    this.livenessScore,
    this.resultCode,
    this.description,
    this.errorMessage,
    this.errorCode,
    this.errorExplanationZh,
    this.errorSuggestedFix,
    this.requestId,
    this.sdkToken,
    this.verificationUrl,
    this.apiAction,
  });

  final String providerId;
  final String providerName;
  final Duration latency;
  final bool success;
  final bool isMatch;
  final bool isLive;
  final double? similarity;
  final double? livenessScore;
  final String? resultCode;
  final String? description;
  final String? errorMessage;
  /// Aliyun/API error code (e.g. 404, SignatureDoesNotMatch).
  final String? errorCode;
  /// Human-readable Chinese explanation for [errorCode].
  final String? errorExplanationZh;
  /// Actionable fix hint for operators.
  final String? errorSuggestedFix;
  final String? requestId;
  final String? sdkToken;
  final String? verificationUrl;
  final String? apiAction;
}
