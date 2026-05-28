import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Output of [AliyunRpcSigner.signRequest] for Aliyun RPC POST transport.
///
/// When [formBody] is non-empty, **all** signed parameters (system, query,
/// formData, and [Signature]) are sent in the POST body only; [queryString] is
/// empty. This matches DirectMail-style RPC POST and avoids cloudauth gateways
/// double-encoding form values when query and body are both present.
///
/// Query-only calls (e.g. DescribeFaceVerify) use [queryString] with an empty
/// [formBody]. All params still participate in signing the same way.
class AliyunRpcSignResult {
  const AliyunRpcSignResult({
    required this.parameters,
    required this.queryString,
    required this.formBody,
    required this.stringToSign,
  });

  final Map<String, String> parameters;

  /// Signed query params (system + query business + Signature).
  final String queryString;

  /// formData business params only (excludes [Signature]).
  final String formBody;

  /// Local `POST&%2F&…` string used for HMAC-SHA1 (compare with Aliyun error).
  final String stringToSign;
}

/// OpenAPI formData parameter names for InitFaceVerify (2019-03-07).
const aliyunInitFaceVerifyFormDataKeys = {
  'FaceContrastPicture',
  'FaceContrastPictureUrl',
  'Model',
  'Crop',
  'AuthId',
};

/// Builds RPC-style HMAC-SHA1 signatures for Aliyun OpenAPI (cloudauth).
class AliyunRpcSigner {
  AliyunRpcSigner({
    required this.accessKeyId,
    required this.accessKeySecret,
  });

  final String accessKeyId;
  final String accessKeySecret;

  static const _signatureMethod = 'HMAC-SHA1';
  static const _signatureVersion = '1.0';

  /// Aliyun RPC percent-encoding (Java `URLEncoder.encode` + Aliyun replacements).
  ///
  /// Dart [Uri.encodeComponent] leaves `(`, `)`, `'`, `*`, and `!` unencoded;
  /// Java encodes all of those except `*`, then Aliyun replaces `+`→`%20`,
  /// `*`→`%2A`, and `%7E`→`~`.
  static String percentEncode(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune <= 0x7F && _isJavaUrlEncoderUnreserved(rune)) {
        buffer.writeCharCode(rune);
      } else if (rune == 0x20) {
        buffer.write('+');
      } else {
        for (final byte in utf8.encode(String.fromCharCode(rune))) {
          buffer.write(
            '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
          );
        }
      }
    }
    return buffer
        .toString()
        .replaceAll('+', '%20')
        .replaceAll('*', '%2A')
        .replaceAll('%7E', '~');
  }

  /// Characters Java [URLEncoder.encode] leaves unescaped before Aliyun tweaks.
  static bool _isJavaUrlEncoderUnreserved(int codeUnit) {
    return (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        codeUnit == 0x2D || // -
        codeUnit == 0x5F || // _
        codeUnit == 0x2E || // .
        codeUnit == 0x2A; // *
  }

  /// Builds the canonicalized query string used for signing (excludes [Signature]).
  static String canonicalizedQueryString(Map<String, String> params) {
    final sortedKeys = params.keys.toList()..sort();
    return sortedKeys
        .map((key) => '${percentEncode(key)}=${percentEncode(params[key]!)}')
        .join('&');
  }

  /// Wire-safe form body: one [percentEncode] pass over raw param values (never pre-encode values).
  static String formUrlEncodedBody(Map<String, String> formDataParams) =>
      canonicalizedQueryString(formDataParams);

  /// True when `%` was encoded twice (e.g. `%2F` → `%252F`). Base64 values never contain `%`.
  static bool hasDoublePercentEncoding(String wireEncoded) =>
      wireEncoded.contains('%25');

  /// Simulates cloudauth gateway canonicalization when POST has **both** URL query
  /// and a form body: query values are URL-decoded, body values are taken as
  /// wire literals (not decoded), then each is [percentEncode]d again — producing
  /// `%252F` for base64 slashes.
  static String canonicalizedQueryStringFromSplitWire({
    required String queryString,
    required String formBody,
  }) {
    final params = <String, String>{};
    if (queryString.isNotEmpty) {
      params.addAll(Uri.splitQueryString(queryString, encoding: utf8));
    }
    if (formBody.isNotEmpty) {
      for (final part in formBody.split('&')) {
        if (part.isEmpty) continue;
        final eq = part.indexOf('=');
        if (eq <= 0) continue;
        params[part.substring(0, eq)] = part.substring(eq + 1);
      }
    }
    return canonicalizedQueryString(params);
  }

  /// Keeps a pre-encoded RPC query string verbatim on the wire (avoids [Uri] re-encoding).
  static Uri buildRpcUri({required String host, required String queryString}) {
    if (queryString.isEmpty) {
      return Uri.parse('https://$host/');
    }
    return Uri.parse('https://$host/?$queryString');
  }

  /// Returns signed parameters, URL query string, and optional form body.
  AliyunRpcSignResult signRequest({
    required String action,
    required String version,
    required Map<String, String> queryParams,
    Map<String, String> formDataParams = const {},
    String format = 'JSON',
    String? regionId,
    DateTime? timestamp,
    String? signatureNonce,
  }) {
    final systemParams = <String, String>{
      'Format': format,
      'Version': version,
      'AccessKeyId': accessKeyId,
      'SignatureMethod': _signatureMethod,
      'SignatureVersion': _signatureVersion,
      'SignatureNonce': signatureNonce ?? _randomNonce(),
      'Timestamp': _formatTimestamp(timestamp ?? DateTime.now().toUtc()),
      'Action': action,
      if (regionId != null && regionId.isNotEmpty) 'RegionId': regionId,
    };

    final paramsForSign = <String, String>{
      ...systemParams,
      ...queryParams,
      ...formDataParams,
    };

    final canonicalized = canonicalizedQueryString(paramsForSign);
    final stringToSign = 'POST&${percentEncode('/')}&'
        '${percentEncode(canonicalized)}';
    final signature = _sign(stringToSign);

    final allWithSignature = <String, String>{
      ...paramsForSign,
      'Signature': signature,
    };

    if (formDataParams.isEmpty) {
      final queryString = canonicalizedQueryString(allWithSignature);
      return AliyunRpcSignResult(
        parameters: allWithSignature,
        queryString: queryString,
        formBody: '',
        stringToSign: stringToSign,
      );
    }

    // InitFaceVerify: entire signed parameter set in POST body (no URL query).
    final formBody = canonicalizedQueryString(allWithSignature);
    return AliyunRpcSignResult(
      parameters: allWithSignature,
      queryString: '',
      formBody: formBody,
      stringToSign: stringToSign,
    );
  }

  /// Returns signed parameters including [Signature].
  Map<String, String> sign({
    required String action,
    required String version,
    required Map<String, String> queryParams,
    Map<String, String> formDataParams = const {},
    String format = 'JSON',
    String? regionId,
    DateTime? timestamp,
    String? signatureNonce,
  }) {
    return signRequest(
      action: action,
      version: version,
      queryParams: queryParams,
      formDataParams: formDataParams,
      format: format,
      regionId: regionId,
      timestamp: timestamp,
      signatureNonce: signatureNonce,
    ).parameters;
  }

  String _sign(String stringToSign) {
    final key = utf8.encode('$accessKeySecret&');
    final digest = Hmac(sha1, key).convert(utf8.encode(stringToSign)).bytes;
    return base64Encode(digest);
  }

  static String _formatTimestamp(DateTime utc) {
    final y = utc.year.toString().padLeft(4, '0');
    final mo = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final h = utc.hour.toString().padLeft(2, '0');
    final mi = utc.minute.toString().padLeft(2, '0');
    final s = utc.second.toString().padLeft(2, '0');
    return '$y-$mo-${d}T$h:$mi:${s}Z';
  }

  static String _randomNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
