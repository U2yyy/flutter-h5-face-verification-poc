/// Aliyun CloudAuth PV_FV H5 liveness helpers.
///
/// Flow: getMetaInfo() → InitFaceVerify → open CertifyUrl in WebView →
/// redirect to ReturnUrl with ?response= JSON → DescribeFaceVerify.
library;

import 'dart:convert';

import 'package:facedetection/services/tencent/tencent_h5_service.dart';

/// Session returned by InitFaceVerify.
class AliyunH5Session {
  const AliyunH5Session({
    required this.certifyId,
    this.certifyUrl,
    required this.returnUrl,
    this.requestId,
  });

  final String certifyId;
  final String? certifyUrl;
  final String returnUrl;
  final String? requestId;
}

/// Parses Aliyun H5 ReturnUrl redirects (`?response=` JSON payload).
class AliyunH5CallbackParser {
  static String redirectBase(String redirectUrl) =>
      TencentH5CallbackParser.redirectBase(redirectUrl);

  static bool isCompletionRedirect(String url, String redirectUrl) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return false;

    final certifyId = extractCertifyId(url);
    if (certifyId == null || certifyId.isEmpty) return false;

    final currentBase = redirectBase(url);
    final expectedBase = redirectBase(redirectUrl);
    return currentBase == expectedBase ||
        currentBase.startsWith(expectedBase) ||
        expectedBase.startsWith(currentBase);
  }

  /// Extracts CertifyId from ReturnUrl `response` JSON or direct query param.
  static String? extractCertifyId(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return null;

    final direct = parsed.queryParameters['certifyId'];
    if (direct != null && direct.isNotEmpty) return direct;

    final responseRaw = parsed.queryParameters['response'];
    if (responseRaw == null || responseRaw.isEmpty) return null;

    try {
      final decoded = jsonDecode(Uri.decodeComponent(responseRaw));
      if (decoded is Map<String, dynamic>) {
        final extInfo = decoded['extInfo'];
        if (extInfo is Map<String, dynamic>) {
          final fromExt = extInfo['certifyId'] as String?;
          if (fromExt != null && fromExt.isNotEmpty) return fromExt;
        }
        final top = decoded['certifyId'] as String?;
        if (top != null && top.isNotEmpty) return top;
      }
    } catch (_) {
      // Fall through — response may be partially encoded.
    }

    return null;
  }
}
