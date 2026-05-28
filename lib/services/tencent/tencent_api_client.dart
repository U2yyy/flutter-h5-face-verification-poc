import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/provider_trace.dart';
import '../../utils/tc3_signer.dart';

class TencentApiException implements Exception {
  TencentApiException(this.code, this.message, {this.requestId});

  final String code;
  final String message;
  final String? requestId;

  @override
  String toString() => 'TencentApiException($code): $message';
}

/// Low-level HTTP client for Tencent Cloud FaceID (product 1061) APIs.
class TencentApiClient {
  TencentApiClient({
    required this.secretId,
    required this.secretKey,
    required this.region,
    required this.host,
    this.service = 'faceid',
    this.apiVersion = '2018-03-01',
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _signer = Tc3Signer(
          secretId: secretId,
          secretKey: secretKey,
          service: service,
          host: host,
        );

  static const _tracePrefix = '[TencentTrace]';

  final String secretId;
  final String secretKey;
  final String region;
  final String host;
  final String service;
  final String apiVersion;
  final http.Client _httpClient;
  final Tc3Signer _signer;

  Future<Map<String, dynamic>> callAction({
    required String action,
    required Map<String, dynamic> payload,
    String? region,
  }) async {
    final sw = ProviderTrace.start();
    final body = jsonEncode(payload);
    final headers = _signer.buildHeaders(
      action: action,
      version: apiVersion,
      payload: body,
      region: region ?? this.region,
    );

    final uri = Uri.https(host, '/');
    await ProviderTrace.logRequest(
      prefix: _tracePrefix,
      action: action,
      method: 'POST',
      url: uri.toString(),
      headers: headers,
      body: payload,
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    final response = await _httpClient.post(uri, headers: headers, body: body);

    ProviderTrace.logResponse(
      prefix: _tracePrefix,
      action: action,
      statusCode: response.statusCode,
      body: response.body,
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final responseBody = decoded['Response'] as Map<String, dynamic>?;

    if (responseBody == null) {
      throw TencentApiException(
        'InvalidResponse',
        'Unexpected API response: ${response.body}',
      );
    }

    if (responseBody.containsKey('Error')) {
      final error = responseBody['Error'] as Map<String, dynamic>;
      throw TencentApiException(
        error['Code'] as String? ?? 'UnknownError',
        error['Message'] as String? ?? 'Unknown error',
        requestId: responseBody['RequestId'] as String?,
      );
    }

    return responseBody;
  }

  void dispose() => _httpClient.close();
}
