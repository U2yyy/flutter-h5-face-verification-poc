import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/provider_trace.dart';

class BaiduAuthException implements Exception {
  BaiduAuthException(this.message, {this.error, this.errorDescription});

  final String message;
  final String? error;
  final String? errorDescription;

  @override
  String toString() => 'BaiduAuthException($error): $message';
}

/// Fetches and caches Baidu AI access_token (OAuth2 client_credentials).
class BaiduAuthClient {
  BaiduAuthClient({
    required this.apiKey,
    required this.secretKey,
    http.Client? httpClient,
    DateTime Function()? clock,
  })  : _httpClient = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  static const _tokenUrl = 'https://aip.baidubce.com/oauth/2.0/token';

  final String apiKey;
  final String secretKey;
  final http.Client _httpClient;
  final DateTime Function() _clock;

  String? _cachedToken;
  DateTime? _expiresAt;

  Future<String> getAccessToken({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedToken != null &&
        _expiresAt != null &&
        _clock().isBefore(_expiresAt!)) {
      return _cachedToken!;
    }

    final sw = ProviderTrace.start();
    const tracePrefix = '[BaiduTrace]';
    await ProviderTrace.logRequest(
      prefix: tracePrefix,
      action: 'oauth/token',
      method: 'POST',
      url: _tokenUrl,
      queryParams: {
        'grant_type': 'client_credentials',
        'client_id': '<redacted>',
        'client_secret': '<redacted>',
      },
      elapsedMs: ProviderTrace.elapsed(sw),
    );

    final uri = Uri.parse(_tokenUrl).replace(
      queryParameters: {
        'grant_type': 'client_credentials',
        'client_id': apiKey,
        'client_secret': secretKey,
      },
    );

    final response = await _httpClient.post(uri);

    ProviderTrace.logResponse(
      prefix: tracePrefix,
      action: 'oauth/token',
      statusCode: response.statusCode,
      body: response.body,
      elapsedMs: ProviderTrace.elapsed(sw),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    if (decoded.containsKey('error')) {
      throw BaiduAuthException(
        decoded['error_description'] as String? ?? 'Auth failed',
        error: decoded['error'] as String?,
        errorDescription: decoded['error_description'] as String?,
      );
    }

    final token = decoded['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw BaiduAuthException('Missing access_token in auth response');
    }

    final expiresIn = decoded['expires_in'] as int? ?? 2592000;
    _cachedToken = token;
    // Refresh 5 minutes before expiry.
    _expiresAt = _clock().add(Duration(seconds: expiresIn - 300));

    return token;
  }

  void clearCache() {
    _cachedToken = null;
    _expiresAt = null;
  }

  void dispose() => _httpClient.close();
}
