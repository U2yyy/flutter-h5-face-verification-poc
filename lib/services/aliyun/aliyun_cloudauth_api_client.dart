import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../utils/aliyun_rpc_signer.dart';
import '../../utils/aliyun_trace.dart';
import 'aliyun_rpc_isolate.dart';

class AliyunCloudAuthException implements Exception {
  AliyunCloudAuthException(this.code, this.message, {this.requestId});

  final String code;
  final String message;
  final String? requestId;

  @override
  String toString() => 'AliyunCloudAuthException($code): $message';
}

/// OpenAPI `in` positions for InitFaceVerify (cloudauth 2019-03-07).
abstract final class AliyunInitFaceVerifyParams {
  static const formDataKeys = {
    'FaceContrastPicture',
    'FaceContrastPictureUrl',
    'Model',
    'Crop',
    'AuthId',
  };
}

/// Low-level HTTP client for Aliyun CloudAuth (InitFaceVerify / DescribeFaceVerify).
class AliyunCloudAuthApiClient {
  /// Bodies larger than this skip full [jsonDecode] on the error path.
  static const maxErrorBodyJsonDecodeLen = 16384;

  /// Max length for API error messages in logs and thrown exceptions.
  static const maxErrorMessageLen = 500;

  AliyunCloudAuthApiClient({
    required this.accessKeyId,
    required this.accessKeySecret,
    this.host = 'cloudauth.aliyuncs.com',
    this.apiVersion = '2019-03-07',
    this.regionId = 'cn-shanghai',
    http.Client? httpClient,
    AliyunRpcSigner? signer,
    this.requestTimeout = const Duration(seconds: 60),
  })  : _httpClient = httpClient ?? http.Client(),
        _signer = signer ??
            AliyunRpcSigner(
              accessKeyId: accessKeyId,
              accessKeySecret: accessKeySecret,
            );

  final String accessKeyId;
  final String accessKeySecret;
  final String host;
  final String apiVersion;
  final String regionId;
  final Duration requestTimeout;
  http.Client _httpClient;
  final AliyunRpcSigner _signer;

  /// Closes the in-flight HTTP client (if any) so a long POST can be aborted.
  void cancelInflightRequest() {
    AliyunTrace.log('http_cancel', component: 'API', detail: 'closing client');
    _httpClient.close();
    _httpClient = http.Client();
  }

  Future<Map<String, dynamic>> initFaceVerify({
    required String sceneId,
    required String outerOrderNo,
    required String userId,
    required String metaInfo,
    required String returnUrl,
    required String model,
    Uint8List? faceContrastPictureBytes,
    String? faceContrastPictureUrl,
    String productCode = 'PV_FV',
    String crop = 'T',
    String? callbackUrl,
    String? voluntaryCustomizedContent,
    String? sourceIp,
    String? certifyUrlType,
    String? certifyUrlStyle,
    String? procedurePriority,
  }) async {
    final trimmedUrl = faceContrastPictureUrl?.trim() ?? '';
    final hasBytes =
        faceContrastPictureBytes != null && faceContrastPictureBytes.isNotEmpty;
    if (trimmedUrl.isEmpty && !hasBytes) {
      throw ArgumentError(
        'Either faceContrastPictureBytes or faceContrastPictureUrl is required.',
      );
    }
    if (trimmedUrl.isNotEmpty && hasBytes) {
      throw ArgumentError(
        'FaceContrastPicture and FaceContrastPictureUrl are mutually exclusive.',
      );
    }

    final queryParams = <String, String>{
      'SceneId': sceneId,
      'OuterOrderNo': outerOrderNo,
      'ProductCode': productCode,
      'UserId': userId,
      'MetaInfo': metaInfo,
      'ReturnUrl': returnUrl,
      if (callbackUrl != null && callbackUrl.isNotEmpty)
        'CallbackUrl': callbackUrl,
      if (voluntaryCustomizedContent != null &&
          voluntaryCustomizedContent.isNotEmpty)
        'VoluntaryCustomizedContent': voluntaryCustomizedContent,
      if (sourceIp != null && sourceIp.isNotEmpty) 'SourceIp': sourceIp,
      if (certifyUrlType != null && certifyUrlType.isNotEmpty)
        'CertifyUrlType': certifyUrlType,
      if (certifyUrlStyle != null && certifyUrlStyle.isNotEmpty)
        'CertifyUrlStyle': certifyUrlStyle,
      if (procedurePriority != null && procedurePriority.isNotEmpty)
        'ProcedurePriority': procedurePriority,
    };

    return _call(
      action: 'InitFaceVerify',
      queryParams: queryParams,
      formDataParams: {
        'Model': model,
        'Crop': crop,
        if (trimmedUrl.isNotEmpty) 'FaceContrastPictureUrl': trimmedUrl,
      },
      faceContrastPictureBytes:
          trimmedUrl.isEmpty ? faceContrastPictureBytes : null,
    );
  }

  Future<Map<String, dynamic>> describeFaceVerify({
    required String sceneId,
    required String certifyId,
  }) async {
    return _call(
      action: 'DescribeFaceVerify',
      queryParams: {
        'SceneId': sceneId,
        'CertifyId': certifyId,
      },
    );
  }

  Future<Map<String, dynamic>> _call({
    required String action,
    required Map<String, String> queryParams,
    Map<String, String> formDataParams = const {},
    Uint8List? faceContrastPictureBytes,
  }) async {
    final sw = AliyunTrace.start();

    late final String queryString;
    late final String formBody;
    late final String stringToSign;
    if (faceContrastPictureBytes != null) {
      // compute() moves base64 + HMAC off the Flutter UI isolate (~600ms for
      // ~2MB images). This reduces Dart frame jank; it does NOT move Android
      // main-thread WebView/platform-view work — see MetaInfo WebView lifecycle.
      final signed = await compute(
        buildAliyunRpcPostBody,
        AliyunRpcPostBodyInput(
          accessKeyId: accessKeyId,
          accessKeySecret: accessKeySecret,
          apiVersion: apiVersion,
          regionId: regionId,
          action: action,
          queryParams: queryParams,
          formDataParams: formDataParams,
          faceContrastPictureBytes: faceContrastPictureBytes,
        ),
      );
      queryString = signed.queryString;
      formBody = signed.formBody;
      stringToSign = signed.stringToSign;
    } else {
      final signed = _signRequest(
        action: action,
        queryParams: queryParams,
        formDataParams: formDataParams,
      );
      queryString = signed.queryString;
      formBody = signed.formBody;
      stringToSign = signed.stringToSign;
    }

    final request = buildSignedRpcPostRequest(
      host: host,
      queryString: queryString,
      formBody: formBody,
    );
    await AliyunTrace.logRequest(
      action: action,
      method: 'POST',
      url: request.url.origin,
      queryParams: AliyunTrace.parseFormUrlEncoded(queryString),
      bodyParams: AliyunTrace.parseFormUrlEncoded(formBody),
      headers: request.headers,
      wireFormBodyBytes: formBody.isEmpty ? null : request.bodyBytes.length,
      stringToSign: stringToSign,
      elapsedMs: AliyunTrace.elapsed(sw),
    );

    late final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _httpClient.send(request).timeout(requestTimeout),
      );
    } on TimeoutException catch (e) {
      AliyunTrace.log(
        'http_timeout',
        component: 'API',
        detail: 'action=$action type=request_timeout '
            'limit=${requestTimeout.inSeconds}s err=$e',
        elapsedMs: AliyunTrace.elapsed(sw),
      );
      rethrow;
    } on SocketException catch (e) {
      AliyunTrace.log(
        'http_connection_error',
        component: 'API',
        detail: 'action=$action type=socket err=$e',
        elapsedMs: AliyunTrace.elapsed(sw),
      );
      throw AliyunCloudAuthException(
        'NetworkError',
        'Connection failed: ${e.message}',
      );
    } on http.ClientException catch (e) {
      AliyunTrace.log(
        'http_connection_error',
        component: 'API',
        detail: 'action=$action type=client_exception err=$e',
        elapsedMs: AliyunTrace.elapsed(sw),
      );
      throw AliyunCloudAuthException(
        'NetworkError',
        'HTTP client error: $e',
      );
    }

    AliyunTrace.logResponse(
      action: action,
      statusCode: response.statusCode,
      body: response.body,
      elapsedMs: AliyunTrace.elapsed(sw),
    );

    final decoded = response.statusCode == 200
        ? _decodeJsonObject(response.body)
        : null;
    final errorFields = response.statusCode != 200
        ? _extractErrorFields(response.body)
        : null;
    final code = errorFields?['Code'] ?? decoded?['Code']?.toString() ?? '';
    final apiMessage =
        errorFields?['Message'] ?? decoded?['Message']?.toString() ?? '';
    final requestId =
        errorFields?['RequestId'] ?? decoded?['RequestId']?.toString();
    final safeMessage = _sanitizeApiMessage(apiMessage, code);

    if (response.statusCode != 200) {
      throw _buildApiException(
        httpStatus: response.statusCode,
        rawBody: response.body,
        code: code,
        apiMessage: safeMessage,
        requestId: requestId,
      );
    }

    if (decoded == null) {
      throw AliyunCloudAuthException(
        'ParseError',
        'Invalid JSON response: ${AliyunTrace.truncate(response.body)}',
      );
    }

    if (code != '200') {
      throw AliyunCloudAuthException(
        code.isEmpty ? 'Unknown' : code,
        safeMessage.isNotEmpty
            ? safeMessage
            : 'API error (code=$code, requestId=$requestId)',
        requestId: requestId,
      );
    }

    return decoded;
  }

  /// Builds a POST whose URL and body match the signed wire format.
  ///
  /// InitFaceVerify uses all-in-body transport ([queryString] empty, full signed
  /// param string in [formBody]). DescribeFaceVerify uses query-only ([formBody] empty).
  ///
  /// [formBody] must be signer output (single [AliyunRpcSigner.percentEncode] pass).
  /// Send as raw UTF-8 bytes — do not pass a [Map] to [http.Client.post].
  @visibleForTesting
  static http.Request buildSignedRpcPostRequest({
    required String host,
    required String queryString,
    required String formBody,
  }) {
    if (formBody.isNotEmpty &&
        AliyunRpcSigner.hasDoublePercentEncoding(formBody)) {
      throw StateError(
        'Aliyun RPC form body contains double percent-encoding (%25). '
        'FaceContrastPicture must be raw base64 in the signer input, not '
        'pre-encoded.',
      );
    }

    final request = http.Request(
      'POST',
      AliyunRpcSigner.buildRpcUri(host: host, queryString: queryString),
    );
    if (formBody.isNotEmpty) {
      request.headers['Content-Type'] =
          'application/x-www-form-urlencoded; charset=utf-8';
      request.bodyBytes = utf8.encode(formBody);
    }
    return request;
  }

  AliyunRpcSignResult _signRequest({
    required String action,
    required Map<String, String> queryParams,
    Map<String, String> formDataParams = const {},
  }) {
    return _signer.signRequest(
      action: action,
      version: apiVersion,
      regionId: regionId,
      queryParams: queryParams,
      formDataParams: formDataParams,
    );
  }

  Map<String, String>? _extractErrorFields(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.length <= maxErrorBodyJsonDecodeLen && trimmed.startsWith('{')) {
      final json = _decodeJsonObject(trimmed);
      if (json != null) {
        return _fieldsFromJsonMap(json);
      }
    }

    final xmlCode = _xmlTag(trimmed, 'Code');
    final xmlMessage = _xmlTag(trimmed, 'Message');
    final xmlRequestId = _xmlTag(trimmed, 'RequestId');
    if (xmlCode != null || xmlMessage != null || xmlRequestId != null) {
      return {
        if (xmlCode != null) 'Code': xmlCode,
        if (xmlMessage != null)
          'Message': _sanitizeApiMessage(xmlMessage, xmlCode ?? ''),
        if (xmlRequestId != null) 'RequestId': xmlRequestId,
      };
    }

    final jsonCode = _regexJsonStringField(trimmed, 'Code');
    final jsonRequestId = _regexJsonStringField(trimmed, 'RequestId');
    var jsonMessage = _regexJsonStringField(trimmed, 'Message');
    jsonMessage ??= _extractJsonMessagePrefix(trimmed);
    if (jsonCode != null || jsonMessage != null || jsonRequestId != null) {
      return {
        if (jsonCode != null) 'Code': jsonCode,
        if (jsonMessage != null)
          'Message': _sanitizeApiMessage(jsonMessage, jsonCode ?? ''),
        if (jsonRequestId != null) 'RequestId': jsonRequestId,
      };
    }

    if (trimmed.contains('SignatureDoesNotMatch')) {
      return {
        'Code': 'SignatureDoesNotMatch',
        'Message': _sanitizeApiMessage(trimmed, 'SignatureDoesNotMatch'),
      };
    }

    return null;
  }

  Map<String, String>? _fieldsFromJsonMap(Map<String, dynamic> json) {
    final code = json['Code']?.toString();
    final message = json['Message']?.toString();
    final requestId = json['RequestId']?.toString();
    if (code == null && message == null && requestId == null) return null;
    return {
      if (code != null) 'Code': code,
      if (message != null) 'Message': _sanitizeApiMessage(message, code ?? ''),
      if (requestId != null) 'RequestId': requestId,
    };
  }

  String? _regexJsonStringField(String body, String field, {int searchLimit = 8192}) {
    final slice = body.length > searchLimit ? body.substring(0, searchLimit) : body;
    final pattern = RegExp('"$field"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"');
    final match = pattern.firstMatch(slice);
    if (match == null) return null;
    try {
      return jsonDecode('"${match.group(1)}"') as String;
    } catch (_) {
      return match.group(1);
    }
  }

  /// Reads the start of a JSON [Message] value when the body is too large to parse.
  String? _extractJsonMessagePrefix(String body, {int searchLimit = 8192}) {
    const marker = '"Message":"';
    final slice = body.length > searchLimit ? body.substring(0, searchLimit) : body;
    final start = slice.indexOf(marker);
    if (start < 0) return null;

    final contentStart = start + marker.length;
    if (contentStart >= slice.length) return null;

    final end = (contentStart + maxErrorMessageLen * 2).clamp(0, slice.length);
    final raw = slice.substring(contentStart, end);
    try {
      return jsonDecode('"$raw"') as String;
    } catch (_) {
      return raw.replaceAll(r'\"', '"');
    }
  }

  String? _xmlTag(String body, String tag) {
    final match = RegExp(
      '<$tag>([^<]*)</$tag>',
      caseSensitive: false,
    ).firstMatch(body.length > 8192 ? body.substring(0, 8192) : body);
    return match?.group(1)?.trim();
  }

  String _sanitizeApiMessage(String message, String code) {
    if (message.isEmpty) return message;

    final isSignatureMismatch = code == 'SignatureDoesNotMatch' ||
        message.contains('SignatureDoesNotMatch');

    if (isSignatureMismatch) {
      const marker = 'server string to sign is:';
      final markerIndex = message.indexOf(marker);
      if (markerIndex >= 0) {
        return _truncateErrorMessage(
          '${message.substring(0, markerIndex)}$marker (omitted — response too large)',
        );
      }
      if (message.contains('string to sign')) {
        return 'Specified signature is not matched with our calculation.';
      }
    }

    return _truncateErrorMessage(message);
  }

  String _truncateErrorMessage(String message) {
    if (message.length <= maxErrorMessageLen) return message;
    return '${message.substring(0, maxErrorMessageLen)}…(${message.length} chars total)';
  }

  @visibleForTesting
  Map<String, String>? extractErrorFieldsForTest(String body) =>
      _extractErrorFields(body);

  @visibleForTesting
  String sanitizeApiMessageForTest(String message, String code) =>
      _sanitizeApiMessage(message, code);

  Map<String, dynamic>? _decodeJsonObject(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return null;
    }
    return null;
  }

  @visibleForTesting
  AliyunCloudAuthException buildApiExceptionForTest({
    required int httpStatus,
    required String rawBody,
  }) {
    final errorFields = _extractErrorFields(rawBody);
    final code = errorFields?['Code'] ?? '';
    final apiMessage = errorFields?['Message'] ?? '';
    return _buildApiException(
      httpStatus: httpStatus,
      rawBody: rawBody,
      code: code,
      apiMessage: apiMessage,
      requestId: errorFields?['RequestId'],
    );
  }

  AliyunCloudAuthException _buildApiException({
    required int httpStatus,
    required String rawBody,
    required String code,
    required String apiMessage,
    String? requestId,
  }) {
    final resolvedCode = code.isNotEmpty
        ? code
        : (apiMessage.contains('SignatureDoesNotMatch')
            ? 'SignatureDoesNotMatch'
            : '$httpStatus');
    final resolvedMessage = apiMessage.isNotEmpty
        ? apiMessage
        : 'HTTP $httpStatus (bodyLen=${rawBody.length})';
    return AliyunCloudAuthException(
      resolvedCode,
      resolvedMessage,
      requestId: requestId,
    );
  }

  void close() => _httpClient.close();
}
