import '../../models/face_verification_result.dart';
import 'baidu_api_client.dart';

/// Parses Baidu video liveness + face match responses.
class BaiduFaceVerificationResponseParser {
  const BaiduFaceVerificationResponseParser({
    required this.providerId,
    required this.providerName,
    this.matchThreshold = 80,
    this.livenessThresholdKey = 'frr_1e-3',
  });

  final String providerId;
  final String providerName;
  final double matchThreshold;
  final String livenessThresholdKey;

  static const videoLivenessAction = 'face/v1/faceliveness/verify';
  static const matchAction = 'face/v3/match';
  static const h5VerifyTokenAction =
      'faceprint/verifyToken/generate+uploadMatchImage';
  static const h5ResultAction = 'faceprint/result/detail';

  FaceVerificationResult parseCombined({
    required BaiduVideoLivenessResult liveness,
    required Map<String, dynamic> matchResponse,
    required Duration latency,
  }) {
    final livenessThreshold =
        (liveness.thresholds[livenessThresholdKey] as num?)?.toDouble() ??
            0.3;
    final isLive = liveness.score >= livenessThreshold;

    final similarity = (matchResponse['score'] as num?)?.toDouble();
    final isMatch = similarity != null && similarity >= matchThreshold;

    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: true,
      isMatch: isMatch,
      isLive: isLive,
      similarity: similarity,
      livenessScore: liveness.score * 100,
      resultCode: isMatch && isLive ? 'Success' : 'Failed',
      description: _buildDescription(
        isMatch: isMatch,
        isLive: isLive,
        similarity: similarity,
        livenessScore: liveness.score,
        livenessThreshold: livenessThreshold,
      ),
      requestId: liveness.logId?.toString(),
      apiAction: '$videoLivenessAction+$matchAction',
    );
  }

  FaceVerificationResult parseH5DetailResponse({
    required Map<String, dynamic> response,
    required Duration latency,
    required String verifyToken,
  }) {
    final result = response['result'] as Map<String, dynamic>? ?? {};
    final verifyResult = result['verify_result'] as Map<String, dynamic>? ?? {};

    final livenessScore =
        (verifyResult['liveness_score'] as num?)?.toDouble() ?? 0;
    final similarity = (verifyResult['score'] as num?)?.toDouble();
    final isLive = livenessScore > 0;
    final isMatch =
        similarity != null && similarity >= matchThreshold && isLive;

    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: true,
      isMatch: isMatch,
      isLive: isLive,
      similarity: similarity,
      livenessScore: livenessScore > 0 ? livenessScore * 100 : 0,
      resultCode: isMatch && isLive ? 'Success' : 'Failed',
      description: _buildH5Description(
        isMatch: isMatch,
        isLive: isLive,
        similarity: similarity,
        livenessScore: livenessScore,
      ),
      requestId: response['log_id']?.toString(),
      sdkToken: verifyToken,
      apiAction: h5ResultAction,
    );
  }

  FaceVerificationResult parseH5SessionReady({
    required Duration latency,
    required String verifyToken,
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
      sdkToken: verifyToken,
      verificationUrl: verificationUrl,
      requestId: requestId,
      apiAction: h5VerifyTokenAction,
      description:
          'H5 session ready. Open verification URL in WebView, then poll results.',
    );
  }

  String _buildH5Description({
    required bool isMatch,
    required bool isLive,
    required double? similarity,
    required double livenessScore,
  }) {
    final parts = <String>[
      'Match: ${isMatch ? 'pass' : 'fail'}'
          '${similarity != null ? ' (score ${similarity.toStringAsFixed(1)}, threshold $matchThreshold)' : ''}',
      'Liveness: ${isLive ? 'pass' : 'fail'}'
          ' (score ${livenessScore.toStringAsFixed(3)})',
    ];
    return parts.join('; ');
  }

  FaceVerificationResult failure({
    required Duration latency,
    required String message,
    String? requestId,
    int? errorCode,
    String? apiAction,
  }) {
    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: latency,
      success: false,
      isMatch: false,
      isLive: false,
      errorMessage: errorCode != null ? '$errorCode: $message' : message,
      requestId: requestId,
      apiAction: apiAction,
    );
  }

  FaceVerificationResult unsupportedFlow({
    required String flowName,
  }) {
    return FaceVerificationResult(
      providerId: providerId,
      providerName: providerName,
      latency: Duration.zero,
      success: false,
      isMatch: false,
      isLive: false,
      errorMessage: '$flowName is not supported by Baidu.',
    );
  }

  String _buildDescription({
    required bool isMatch,
    required bool isLive,
    required double? similarity,
    required double livenessScore,
    required double livenessThreshold,
  }) {
    final parts = <String>[
      'Match: ${isMatch ? 'pass' : 'fail'}'
          '${similarity != null ? ' (score ${similarity.toStringAsFixed(1)}, threshold $matchThreshold)' : ''}',
      'Liveness: ${isLive ? 'pass' : 'fail'}'
          ' (score ${livenessScore.toStringAsFixed(3)}, threshold ${livenessThreshold.toStringAsFixed(3)})',
    ];
    return parts.join('; ');
  }
}
