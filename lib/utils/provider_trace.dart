import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Shared HTTP trace logging for cloud API clients (Tencent, Baidu, etc.).
///
/// Grep logcat: `adb logcat -s flutter | grep ProviderTrace`
class ProviderTrace {
  ProviderTrace._();

  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  /// Param keys whose values are truncated in logs (signing/HTTP still use full values).
  static const largeValueKeys = {
    'ImageBase64',
    'CompareImageBase64',
    'LivenessData',
    'video_base64',
    'image',
    'image_ref1',
    'image_ref2',
    'FaceContrastPicture',
    'MetaInfo',
    'api_secret',
  };

  static const largeValuePreviewThreshold = 512;
  static const largeValuePreviewChars = 50;

  static void log(
    String prefix,
    String phase, {
    String component = 'API',
    String? detail,
    int? elapsedMs,
  }) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final buffer = StringBuffer('$prefix ts=$ts [$component] $phase');
    if (elapsedMs != null) buffer.write(' elapsed=${elapsedMs}ms');
    if (detail != null && detail.isNotEmpty) buffer.write(' $detail');
    debugPrint(buffer.toString());
  }

  static void logJson(
    String prefix,
    String phase, {
    String component = 'API',
    required Map<String, dynamic> data,
    int? elapsedMs,
  }) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final header = StringBuffer('$prefix ts=$ts [$component] $phase');
    if (elapsedMs != null) header.write(' elapsed=${elapsedMs}ms');
    debugPrint(header.toString());

    final jsonText = _jsonEncoder.convert(data);
    for (final line in jsonText.split('\n')) {
      debugPrint('$prefix   $line');
    }
  }

  static Future<void> logRequest({
    required String prefix,
    required String action,
    required String method,
    required String url,
    Map<String, dynamic>? queryParams,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    int? elapsedMs,
  }) async {
    logJson(
      prefix,
      'request',
      elapsedMs: elapsedMs,
      data: {
        'action': action,
        'method': method,
        'url': url,
        if (headers != null && headers.isNotEmpty)
          'headers': sanitizeHeaders(headers),
        if (queryParams != null && queryParams.isNotEmpty)
          'queryParams': toLoggableMap(queryParams),
        if (body != null && body.isNotEmpty) 'body': toLoggableMap(body),
      },
    );
  }

  static void logResponse({
    required String prefix,
    required String action,
    required int statusCode,
    required String body,
    int? elapsedMs,
  }) {
    logJson(
      prefix,
      'response',
      elapsedMs: elapsedMs,
      data: {
        'action': action,
        'statusCode': statusCode,
        'body': responseBodyForLog(body),
      },
    );
  }

  static Map<String, String> sanitizeHeaders(Map<String, String> headers) {
    const redactKeys = {
      'authorization',
      'x-tc-authorization',
      'x-tc-token',
    };
    return {
      for (final entry in headers.entries)
        entry.key: redactKeys.contains(entry.key.toLowerCase())
            ? '<redacted>'
            : entry.value,
    };
  }

  @visibleForTesting
  static Map<String, dynamic> toLoggableMap(Map<String, dynamic> params) {
    final sortedKeys = params.keys.toList()..sort();
    return {
      for (final key in sortedKeys)
        key: loggableValue(key, params[key]?.toString() ?? ''),
    };
  }

  static dynamic loggableValue(String key, String value) {
    final shouldPreview = largeValueKeys.contains(key) ||
        value.length > largeValuePreviewThreshold;
    if (!shouldPreview) return value;
    if (value.length <= largeValuePreviewThreshold) return value;

    final head = value.substring(0, largeValuePreviewChars);
    final tail = value.substring(value.length - largeValuePreviewChars);
    return {
      '_truncated': true,
      '_fullLength': value.length,
      '_preview': '$head…$tail',
    };
  }

  @visibleForTesting
  static dynamic responseBodyForLog(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return jsonDecode(trimmed);
      } catch (_) {
        return {'_raw': truncate(trimmed, maxLen: 2000)};
      }
    }

    return truncate(trimmed, maxLen: 2000);
  }

  static String truncate(String text, {int maxLen = 200}) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}…(${text.length} chars total)';
  }

  static Stopwatch start() => Stopwatch()..start();

  static int elapsed(Stopwatch? sw) => sw?.elapsedMilliseconds ?? 0;
}
