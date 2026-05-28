import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/provider_trace.dart';
import 'baidu_auth_client.dart';

class BaiduApiException implements Exception {
  BaiduApiException(this.code, this.message, {this.logId});

  final int code;
  final String message;
  final int? logId;

  @override
  String toString() => 'BaiduApiException($code): $message';
}

class BaiduVideoLivenessResult {
  const BaiduVideoLivenessResult({
    required this.score,
    required this.thresholds,
    required this.bestImageBase64,
    this.bestImageLivenessScore,
    this.logId,
  });

  final double score;
  final Map<String, dynamic> thresholds;
  final String bestImageBase64;
  final double? bestImageLivenessScore;
  final int? logId;
}

/// Low-level HTTP client for Baidu AI Face Recognition APIs.
class BaiduApiClient {
  BaiduApiClient({
    required BaiduAuthClient authClient,
    http.Client? httpClient,
  })  : _authClient = authClient,
        _httpClient = httpClient ?? http.Client();

  static const _tracePrefix = '[BaiduTrace]';

  static const _matchPath = '/rest/2.0/face/v3/match';
  static const _videoLivenessPath = '/rest/2.0/face/v1/faceliveness/verify';
  static const _verifyTokenPath =
      '/rpc/2.0/brain/solution/faceprint/verifyToken/generate';
  static const _uploadMatchImagePath =
      '/rpc/2.0/brain/solution/faceprint/uploadMatchImage';
  static const _resultDetailPath =
      '/rpc/2.0/brain/solution/faceprint/result/detail';

  final BaiduAuthClient _authClient;
  final http.Client _httpClient;

  Future<Map<String, dynamic>> matchFaces(List<Map<String, dynamic>> images) {
    return _postJsonArray(_matchPath, 'match', images);
  }

  Future<Map<String, dynamic>> generateVerifyToken({
    required String planId,
    String? successUrl,
    String? failedUrl,
  }) {
    final body = <String, dynamic>{'plan_id': planId};
    if (successUrl != null || failedUrl != null) {
      body['redirect_config'] = {
        if (successUrl != null) 'success_url': successUrl,
        if (failedUrl != null) 'failed_url': failedUrl,
      };
    }
    return _postFaceprintJson(_verifyTokenPath, 'verifyToken/generate', body);
  }

  Future<Map<String, dynamic>> uploadMatchImage({
    required String verifyToken,
    required String imageBase64,
    String qualityControl = 'NORMAL',
    String livenessControl = 'NONE',
  }) {
    return _postFaceprintJson(_uploadMatchImagePath, 'uploadMatchImage', {
      'verify_token': verifyToken,
      'image': imageBase64,
      'quality_control': qualityControl,
      'liveness_control': livenessControl,
    });
  }

  Future<Map<String, dynamic>> fetchVerificationDetail({
    required String verifyToken,
  }) {
    return _postFaceprintJson(_resultDetailPath, 'result/detail', {
      'verify_token': verifyToken,
    });
  }

  Future<BaiduVideoLivenessResult> verifyVideoLiveness({
    required String videoBase64,
  }) async {
    final sw = ProviderTrace.start();
    const action = 'faceliveness/verify';
    final token = await _authClient.getAccessToken();
    final uri = Uri.https('aip.baidubce.com', _videoLivenessPath, {
      'access_token': '<redacted>',
    });

    await ProviderTrace.logRequest(
      prefix: _tracePrefix,
      action: action,
      method: 'POST',
      url: uri.toString(),
      body: {'video_base64': videoBase64},
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    final response = await _httpClient.post(
      Uri.https('aip.baidubce.com', _videoLivenessPath, {
        'access_token': token,
      }),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'video_base64': videoBase64},
    );

    ProviderTrace.logResponse(
      prefix: _tracePrefix,
      action: action,
      statusCode: response.statusCode,
      body: response.body,
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    _throwIfStandardError(decoded);

    final errNo = decoded['err_no'] as int? ?? decoded['error_code'] as int? ?? 0;
    if (errNo != 0) {
      throw BaiduApiException(
        errNo,
        decoded['err_msg'] as String? ??
            decoded['error_msg'] as String? ??
            'Video liveness failed',
        logId: decoded['serverlogid'] as int?,
      );
    }

    final result = decoded['result'] as Map<String, dynamic>? ?? {};
    final bestImage = result['best_image'] as Map<String, dynamic>? ?? {};
    final pic = bestImage['pic'] as String? ?? '';

    if (pic.isEmpty) {
      throw BaiduApiException(
        -1,
        'Video liveness did not return best_image',
        logId: decoded['serverlogid'] as int?,
      );
    }

    return BaiduVideoLivenessResult(
      score: (result['score'] as num?)?.toDouble() ?? 0,
      thresholds: (result['thresholds'] as Map<String, dynamic>?) ?? {},
      bestImageBase64: pic,
      bestImageLivenessScore:
          (bestImage['liveness_score'] as num?)?.toDouble(),
      logId: decoded['serverlogid'] as int?,
    );
  }

  Future<Map<String, dynamic>> _postFaceprintJson(
    String path,
    String action,
    Map<String, dynamic> payload,
  ) async {
    var token = await _authClient.getAccessToken();
    var response = await _postObjectWithToken(path, token, payload, action);
    var decoded = jsonDecode(response.body) as Map<String, dynamic>;

    var errorCode = decoded['error_code'] as int? ?? 0;
    if (errorCode == 110 || errorCode == 111) {
      _authClient.clearCache();
      token = await _authClient.getAccessToken(forceRefresh: true);
      response = await _postObjectWithToken(path, token, payload, action);
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
      errorCode = decoded['error_code'] as int? ?? 0;
    }

    _throwIfStandardError(decoded);
    _throwIfFaceprintError(decoded);
    return decoded;
  }

  Future<Map<String, dynamic>> _postJsonArray(
    String path,
    String action,
    List<Map<String, dynamic>> payload,
  ) async {
    var token = await _authClient.getAccessToken();
    var response = await _postJsonWithToken(path, token, payload, action);
    var decoded = jsonDecode(response.body) as Map<String, dynamic>;

    final errorCode = decoded['error_code'] as int? ?? 0;
    if (errorCode == 110 || errorCode == 111) {
      _authClient.clearCache();
      token = await _authClient.getAccessToken(forceRefresh: true);
      response = await _postJsonWithToken(path, token, payload, action);
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    }

    _throwIfStandardError(decoded);
    return decoded;
  }

  Future<http.Response> _postJsonWithToken(
    String path,
    String token,
    List<Map<String, dynamic>> payload,
    String action,
  ) async {
    final sw = ProviderTrace.start();
    final uri = Uri.https('aip.baidubce.com', path, {
      'access_token': '<redacted>',
    });
    await ProviderTrace.logRequest(
      prefix: _tracePrefix,
      action: action,
      method: 'POST',
      url: uri.toString(),
      body: {'_array': payload},
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    final response = await _httpClient.post(
      Uri.https('aip.baidubce.com', path, {'access_token': token}),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    ProviderTrace.logResponse(
      prefix: _tracePrefix,
      action: action,
      statusCode: response.statusCode,
      body: response.body,
      elapsedMs: ProviderTrace.elapsed(sw),
    );
    return response;
  }

  Future<http.Response> _postObjectWithToken(
    String path,
    String token,
    Map<String, dynamic> payload,
    String action,
  ) async {
    final sw = ProviderTrace.start();
    final uri = Uri.https('aip.baidubce.com', path, {
      'access_token': '<redacted>',
    });
    await ProviderTrace.logRequest(
      prefix: _tracePrefix,
      action: action,
      method: 'POST',
      url: uri.toString(),
      body: payload,
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    final response = await _httpClient.post(
      Uri.https('aip.baidubce.com', path, {'access_token': token}),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    ProviderTrace.logResponse(
      prefix: _tracePrefix,
      action: action,
      statusCode: response.statusCode,
      body: response.body,
      elapsedMs: ProviderTrace.elapsed(sw),
    );
    return response;
  }

  void _throwIfFaceprintError(Map<String, dynamic> decoded) {
    final success = decoded['success'] as bool?;
    if (success == false) {
      final code = decoded['code'];
      throw BaiduApiException(
        code is int ? code : int.tryParse(code?.toString() ?? '') ?? -1,
        decoded['message'] as String? ?? 'Faceprint request failed',
        logId: int.tryParse(decoded['log_id']?.toString() ?? ''),
      );
    }
  }

  void _throwIfStandardError(Map<String, dynamic> decoded) {
    final errorCode = decoded['error_code'] as int? ?? 0;
    if (errorCode != 0) {
      throw BaiduApiException(
        errorCode,
        decoded['error_msg'] as String? ?? 'Unknown error',
        logId: decoded['log_id'] as int?,
      );
    }
  }

  void dispose() {
    _httpClient.close();
    _authClient.dispose();
  }
}
