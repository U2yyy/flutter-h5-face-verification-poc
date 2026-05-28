import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Builds TC3-HMAC-SHA256 signatures for Tencent Cloud API v3.
class Tc3Signer {
  Tc3Signer({
    required this.secretId,
    required this.secretKey,
    required this.service,
    required this.host,
  });

  final String secretId;
  final String secretKey;
  final String service;
  final String host;

  static const _algorithm = 'TC3-HMAC-SHA256';

  Map<String, String> buildHeaders({
    required String action,
    required String version,
    required String payload,
    required String region,
    int? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final date = _formatDate(ts);
    const contentType = 'application/json; charset=utf-8';

    final canonicalHeaders = 'content-type:$contentType\nhost:$host\n';
    const signedHeaders = 'content-type;host';
    final hashedPayload = _sha256Hex(payload);

    final canonicalRequest = [
      'POST',
      '/',
      '',
      canonicalHeaders,
      signedHeaders,
      hashedPayload,
    ].join('\n');

    final credentialScope = '$date/$service/tc3_request';
    final stringToSign = [
      _algorithm,
      ts.toString(),
      credentialScope,
      _sha256Hex(canonicalRequest),
    ].join('\n');

    final signature = _sign(stringToSign, date);

    final authorization =
        '$_algorithm Credential=$secretId/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    final headers = <String, String>{
      'Authorization': authorization,
      'Content-Type': contentType,
      'Host': host,
      'X-TC-Action': action,
      'X-TC-Timestamp': ts.toString(),
      'X-TC-Version': version,
    };
    if (region.isNotEmpty) {
      headers['X-TC-Region'] = region;
    }
    return headers;
  }

  String _sign(String stringToSign, String date) {
    final secretDate = _hmac(utf8.encode('TC3$secretKey'), date);
    final secretService = _hmac(secretDate, service);
    final secretSigning = _hmac(secretService, 'tc3_request');
    return _hmacHex(secretSigning, stringToSign);
  }

  static String _formatDate(int timestamp) {
    final utc = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  static String _sha256Hex(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  static List<int> _hmac(List<int> key, String message) {
    return Hmac(sha256, key).convert(utf8.encode(message)).bytes;
  }

  static String _hmacHex(List<int> key, String message) {
    return Hmac(sha256, key).convert(utf8.encode(message)).toString();
  }
}
