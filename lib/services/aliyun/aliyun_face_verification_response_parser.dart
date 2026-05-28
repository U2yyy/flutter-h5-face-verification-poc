import 'dart:convert';

import '../../models/face_verification_result.dart';
import '../../utils/aliyun_error_codes.dart';

/// Parses Aliyun DescribeFaceVerify responses for PV_FV H5 flow.
class AliyunFaceVerificationResponseParser {
  const AliyunFaceVerificationResponseParser({
    required this.providerId,
    required this.providerName,
    this.matchThreshold = 70,
  });

  final String providerId;
  final String providerName;
  final double matchThreshold;

  static const initFaceVerifyAction = 'InitFaceVerify';
  static const describeFaceVerifyAction = 'DescribeFaceVerify';

  FaceVerificationResult parseH5SessionReady({
    required Duration latency,
    required String certifyId,
    String? certifyUrl,
    String? requestId,
  }) {
    final trimmedUrl = certifyUrl?.trim();
    final hasCertifyUrl = trimmedUrl != null && trimmedUrl.isNotEmpty;

    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: true,
      isMatch: false,
      isLive: false,
      sdkToken: certifyId,
      verificationUrl: hasCertifyUrl ? trimmedUrl : null,
      requestId: requestId,
      apiAction: initFaceVerifyAction,
      description: hasCertifyUrl
          ? 'H5 session ready. Open CertifyUrl in WebView, then poll DescribeFaceVerify.'
          : 'InitFaceVerify returned CertifyId only (no CertifyUrl). '
              'Set ALIYUN_CLOUDAUTH_CERTIFY_URL_TYPE=H5 with real device MetaInfo '
              'for in-app WebView liveness, or poll DescribeFaceVerify after CallbackUrl.',
    );
  }

  FaceVerificationResult parseDescribeResponse({
    required Map<String, dynamic> response,
    required Duration latency,
    required String certifyId,
  }) {
    final resultObject =
        response['ResultObject'] as Map<String, dynamic>? ?? {};
    final passed = resultObject['Passed'] as String? ?? '';
    final materialRaw = resultObject['MaterialInfo'];

    Map<String, dynamic> material = {};
    if (materialRaw is String && materialRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(materialRaw);
        if (decoded is Map<String, dynamic>) material = decoded;
      } catch (_) {}
    } else if (materialRaw is Map<String, dynamic>) {
      material = materialRaw;
    }

    final facial = material['facialPictureFront'] as Map<String, dynamic>? ?? {};
    final verifyScore = (facial['verifyScore'] as num?)?.toDouble();
    final faceAttack = material['faceAttack'] as String? ??
        facial['faceAttack'] as String?;
    final qualityScore = (facial['qualityScore'] as num?)?.toDouble();

    final isLive = passed == 'T' && faceAttack != 'T';
    final isMatch = passed == 'T' &&
        verifyScore != null &&
        verifyScore >= matchThreshold &&
        isLive;

    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: true,
      isMatch: isMatch,
      isLive: isLive,
      similarity: verifyScore,
      livenessScore: qualityScore,
      resultCode: passed == 'T' ? 'Passed' : 'Failed',
      description: _buildDescription(
        passed: passed,
        isMatch: isMatch,
        isLive: isLive,
        verifyScore: verifyScore,
        faceAttack: faceAttack,
      ),
      requestId: response['RequestId'] as String?,
      sdkToken: certifyId,
      apiAction: describeFaceVerifyAction,
    );
  }

  FaceVerificationResult failure({
    required Duration latency,
    required String message,
    String? requestId,
    String? errorCode,
    String? apiAction,
    String? subCode,
  }) {
    final info = AliyunErrorCodes.resolve(
      code: errorCode,
      subCode: subCode,
      apiMessage: message,
    );
    final codeLabel = errorCode ?? info.code;
    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: false,
      isMatch: false,
      isLive: false,
      errorMessage: codeLabel != 'Unknown' && codeLabel.isNotEmpty
          ? '$codeLabel: $message'
          : message,
      errorCode: codeLabel != 'Unknown' ? codeLabel : errorCode,
      errorExplanationZh: info.chineseExplanation,
      errorSuggestedFix: info.suggestedFix,
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
      errorMessage: '$flowName is not supported by Aliyun CloudAuth.',
    );
  }

  String _buildDescription({
    required String passed,
    required bool isMatch,
    required bool isLive,
    required double? verifyScore,
    required String? faceAttack,
  }) {
    final parts = <String>[
      'Passed: $passed',
      'Match: ${isMatch ? 'pass' : 'fail'}'
          '${verifyScore != null ? ' (verifyScore ${verifyScore.toStringAsFixed(1)}, threshold $matchThreshold)' : ''}',
      'Liveness: ${isLive ? 'pass' : 'fail'}'
          '${faceAttack != null ? ' (faceAttack=$faceAttack)' : ''}',
    ];
    return parts.join('; ');
  }
}
