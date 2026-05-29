import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../utils/provider_trace.dart';

class FinAuthApiException implements Exception {
  FinAuthApiException(this.message, {this.httpStatus, this.requestId});

  final String message;
  final int? httpStatus;
  final String? requestId;

  @override
  String toString() => 'FinAuthApiException($httpStatus): $message';
}

/// Low-level HTTP client for FinAuth H5 Lite overseas APIs.
///
/// Auth: `api_key` + `api_secret` sent directly (no request signing for lite).
class FinAuthApiClient {
  FinAuthApiClient({
    required this.apiKey,
    required this.apiSecret,
    required this.apiHost,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const tracePrefix = '[FinAuthTrace]';

  static const getTokenPath = '/finauth/lite/get_token';
  static const getResultPath = '/finauth/lite/get_result';

  final String apiKey;
  final String apiSecret;
  final String apiHost;
  final http.Client _httpClient;

  Future<Map<String, dynamic>> getToken({
    required String returnUrl,
    required String notifyUrl,
    required String bizNo,
    required String comparisonType,
    required String uuid,
    required Uint8List referenceImageBytes,
    String? sceneId,
    String? procedureType,
    String? procedurePriority,
    String? language,
    String? actionHttpMethod,
    String? redirectType,
    String? fmpMode,
  }) async {
    final sw = ProviderTrace.start();
    const action = 'get_token';
    final uri = Uri.https(apiHost, getTokenPath);

    final fields = <String, String>{
      'api_key': apiKey,
      'api_secret': apiSecret,
      'return_url': returnUrl,
      'notify_url': notifyUrl,
      'biz_no': bizNo,
      'comparison_type': comparisonType,
      'uuid': uuid,
      if (sceneId != null && sceneId.isNotEmpty) 'scene_id': sceneId,
      if (procedureType != null && procedureType.isNotEmpty)
        'procedure_type': procedureType,
      if (procedurePriority != null && procedurePriority.isNotEmpty)
        'procedure_priority': procedurePriority,
      if (language != null && language.isNotEmpty) 'language': language,
      if (actionHttpMethod != null && actionHttpMethod.isNotEmpty)
        'action_http_method': actionHttpMethod,
      if (redirectType != null && redirectType.isNotEmpty)
        'redirect_type': redirectType,
      if (fmpMode != null && fmpMode.isNotEmpty) 'fmp_mode': fmpMode,
    };

    await ProviderTrace.logRequest(
      prefix: tracePrefix,
      action: action,
      method: 'POST',
      url: uri.toString(),
      body: {
        ...fields,
        'api_secret': '<redacted>',
        'image_ref1': '<file ${referenceImageBytes.length} bytes>',
      },
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(
          'image_ref1',
          referenceImageBytes,
          filename: 'reference.jpg',
        ),
      );

    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    final body = response.body;

    ProviderTrace.logResponse(
      prefix: tracePrefix,
      action: action,
      statusCode: response.statusCode,
      body: body,
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    return _parseJsonResponse(
      body: body,
      httpStatus: response.statusCode,
      action: action,
    );
  }

  Future<Map<String, dynamic>> getResult({
    required String bizId,
    String returnVerifyTime = '0',
    String returnImage = '0',
  }) async {
    final sw = ProviderTrace.start();
    const action = 'get_result';
    final query = {
      'api_key': apiKey,
      'api_secret': apiSecret,
      'biz_id': bizId,
      'return_verify_time': returnVerifyTime,
      'return_image': returnImage,
    };
    final uri = Uri.https(apiHost, getResultPath, query);

    await ProviderTrace.logRequest(
      prefix: tracePrefix,
      action: action,
      method: 'GET',
      url: uri.toString().replaceAll(apiSecret, '<redacted>'),
      queryParams: {
        ...query,
        'api_secret': '<redacted>',
      },
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    final response = await _httpClient.get(uri);
    final body = response.body;

    ProviderTrace.logResponse(
      prefix: tracePrefix,
      action: action,
      statusCode: response.statusCode,
      body: body,
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    return _parseJsonResponse(
      body: body,
      httpStatus: response.statusCode,
      action: action,
    );
  }

  Map<String, dynamic> _parseJsonResponse({
    required String body,
    required int httpStatus,
    required String action,
  }) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw FinAuthApiException(
        'Invalid JSON response from $action (HTTP $httpStatus)',
        httpStatus: httpStatus,
      );
    }

    final requestId = decoded['request_id'] as String?;
    final errorMessage = decoded['error_message'] as String? ??
        decoded['error'] as String?;

    if (httpStatus >= 400 || errorMessage != null) {
      throw FinAuthApiException(
        errorMessage ?? 'HTTP $httpStatus',
        httpStatus: httpStatus,
        requestId: requestId,
      );
    }

    return decoded;
  }
}
