import '../../models/face_verification_result.dart';

/// Parses Tencent FaceID (1061) API responses for pure-API and SaaS SDK flows.
class TencentFaceIdResponseParser {
  const TencentFaceIdResponseParser({
    required this.providerId,
    required this.providerName,
  });

  final String providerId;
  final String providerName;

  FaceVerificationResult parsePureApiResponse({
    required Map<String, dynamic> response,
    required String action,
    required Duration latency,
  }) {
    final resultCode = response['Result'] as String? ?? '';
    final similarity = (response['Sim'] as num?)?.toDouble();
    final isMatch = resultCode == 'Success';
    final isLive = resultCode == 'Success' ||
        resultCode == 'FailedOperation.CompareLowSimilarity';

    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: true,
      isMatch: isMatch,
      isLive: isLive,
      similarity: similarity,
      livenessScore: isLive ? 100 : 0,
      resultCode: resultCode,
      description: response['Description'] as String?,
      requestId: response['RequestId'] as String?,
      apiAction: action,
    );
  }

  FaceVerificationResult parseSdkResultResponse({
    required Map<String, dynamic> response,
    required String action,
    required Duration latency,
    required String sdkToken,
  }) {
    final resultCode = response['Result'] as String? ?? '';
    final similarity = (response['Similarity'] as num?)?.toDouble();
    final isComplete = resultCode != '-999';
    final isMatch = resultCode == '0';
    const livenessFailedCodes = {'1004', '1005', '2013', '2014'};
    final isLive = isComplete && !livenessFailedCodes.contains(resultCode);

    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: isComplete,
      isMatch: isMatch,
      isLive: isLive,
      similarity: similarity,
      resultCode: resultCode,
      description: response['Description'] as String?,
      requestId: response['RequestId'] as String?,
      sdkToken: sdkToken,
      apiAction: action,
      errorMessage: isComplete
          ? null
          : response['Description'] as String? ??
              'Verification not finished (Result=$resultCode). '
                  'Complete liveness in the Tencent eKYC SDK first.',
    );
  }

  FaceVerificationResult parseH5ResultResponse({
    required Map<String, dynamic> response,
    required String action,
    required Duration latency,
    required String bizToken,
  }) {
    final rawCode = response['ErrorCode'];
    if (rawCode == null) {
      return FaceVerificationResult(
        providerId: providerId,
        providerName: providerName,
        latency: latency,
        success: false,
        isMatch: false,
        isLive: false,
        sdkToken: bizToken,
        apiAction: action,
        requestId: response['RequestId'] as String?,
        errorMessage:
            'Verification not finished. Complete H5 liveness in WebView first.',
      );
    }

    final errorCode = rawCode is int ? rawCode : int.tryParse('$rawCode') ?? -1;
    final errorMsg = response['ErrorMsg'] as String?;
    final similarity = _extractH5Similarity(response);
    final isMatch = errorCode == 0;
    const livenessFailedCodes = {1004, 1005, 2013, 2014};
    final isLive = isMatch || !livenessFailedCodes.contains(errorCode);

    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: true,
      isMatch: isMatch,
      isLive: isLive,
      similarity: similarity,
      resultCode: '$errorCode',
      description: errorMsg,
      requestId: response['RequestId'] as String?,
      sdkToken: bizToken,
      apiAction: action,
      errorMessage: isMatch ? null : errorMsg,
    );
  }

  double? _extractH5Similarity(Map<String, dynamic> response) {
    final details = response['VerificationDetailList'];
    if (details is! List || details.isEmpty) return null;
    final last = details.last;
    if (last is! Map<String, dynamic>) return null;
    return (last['Similarity'] as num?)?.toDouble();
  }
}
