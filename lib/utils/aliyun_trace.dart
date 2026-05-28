import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';
import 'provider_trace.dart';

/// Structured debug logging for the Aliyun H5 verification flow.
///
/// Grep logcat with: `adb logcat -s flutter | grep AliyunTrace`
class AliyunTrace {
  AliyunTrace._();

  static const prefix = '[AliyunTrace]';

  static const faceContrastLatestFileName = 'aliyun_face_contrast_latest.b64';

  /// Override temp directory root in tests.
  @visibleForTesting
  static Future<Directory> Function()? resolveTempDirectoryOverride;

  static void log(
    String phase, {
    String component = 'core',
    String? detail,
    int? elapsedMs,
  }) {
    ProviderTrace.log(prefix, phase, component: component, detail: detail, elapsedMs: elapsedMs);
  }

  static Future<void> logRequest({
    required String action,
    required String method,
    required String url,
    required Map<String, String> queryParams,
    Map<String, String> bodyParams = const {},
    Map<String, String>? headers,
    int? wireFormBodyBytes,
    String? stringToSign,
    int? elapsedMs,
  }) async {
    FaceContrastExport? faceExport;
    final faceContrast = bodyParams['FaceContrastPicture'];
    if (faceContrast != null &&
        faceContrast.isNotEmpty &&
        AppConfig.aliyunDebugDumpFaceContrastBase64) {
      faceExport = await exportFaceContrastToFile(faceContrast, action: action);
    }

    final bodyForLog = <String, dynamic>{
      ...toLoggableMap(
        bodyParams,
        faceContrastExport: faceExport,
      ),
    };

    ProviderTrace.logJson(
      prefix,
      'request',
      component: 'API',
      elapsedMs: elapsedMs,
      data: {
        'action': action,
        'method': method,
        'url': url,
        if (headers != null && headers.isNotEmpty)
          'headers': ProviderTrace.sanitizeHeaders(headers),
        'queryParams': toLoggableMap(queryParams),
        if (bodyForLog.isNotEmpty) 'bodyParams': bodyForLog,
        if (wireFormBodyBytes != null) 'wireFormBodyBytes': wireFormBodyBytes,
        if (stringToSign != null && stringToSign.isNotEmpty)
          'stringToSign': formatStringToSignForLog(stringToSign),
      },
    );
  }

  static void logResponse({
    required String action,
    required int statusCode,
    required String body,
    int? elapsedMs,
  }) {
    ProviderTrace.logResponse(
      prefix: prefix,
      action: action,
      statusCode: statusCode,
      body: body,
      elapsedMs: elapsedMs,
    );
  }

  @visibleForTesting
  static dynamic formatStringToSignForLog(String stringToSign) {
    if (AppConfig.aliyunLogStringToSign) return stringToSign;
    return {
      '_length': stringToSign.length,
      '_prefix': ProviderTrace.truncate(stringToSign, maxLen: 200),
      '_note':
          'Set ALIYUN_LOG_STRING_TO_SIGN=true for full stringToSign. '
          'Compare prefix with Aliyun SignatureDoesNotMatch server string.',
    };
  }

  static Map<String, String> parseFormUrlEncoded(String encoded) {
    if (encoded.isEmpty) return {};
    return Uri.splitQueryString(encoded, encoding: utf8);
  }

  @visibleForTesting
  static Map<String, dynamic> toLoggableMap(
    Map<String, String> params, {
    FaceContrastExport? faceContrastExport,
  }) {
    final sortedKeys = params.keys.toList()..sort();
    return {
      for (final key in sortedKeys)
        key: loggableValue(
          key,
          params[key] ?? '',
          faceContrastExport:
              key == 'FaceContrastPicture' ? faceContrastExport : null,
        ),
    };
  }

  @visibleForTesting
  static dynamic loggableValue(
    String key,
    String value, {
    FaceContrastExport? faceContrastExport,
  }) {
    if (key == 'FaceContrastPicture' && faceContrastExport != null) {
      return {
        '_truncated': true,
        '_fullLength': value.length,
        '_filePath': faceContrastExport.filePath,
        '_adbPull': faceContrastExport.adbPullCommand,
      };
    }
    return ProviderTrace.loggableValue(key, value);
  }

  /// Writes FaceContrastPicture base64 to temp when [AppConfig.aliyunDebugDumpFaceContrastBase64].
  static Future<FaceContrastExport?> exportFaceContrastToFile(
    String base64Value, {
    required String action,
  }) async {
    if (kIsWeb || base64Value.isEmpty) return null;
    if (!AppConfig.aliyunDebugDumpFaceContrastBase64) return null;

    try {
      final dir = await _resolveTempDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final latestPath = '${dir.path}/$faceContrastLatestFileName';
      final stampedPath = '${dir.path}/aliyun_face_contrast_$timestamp.b64';

      await File(latestPath).writeAsString(base64Value);
      await File(stampedPath).writeAsString(base64Value);

      final adbPull = adbPullCommand(latestPath);
      log(
        'face_contrast_export',
        component: 'API',
        detail: 'action=$action path=$latestPath chars=${base64Value.length} adb_pull=$adbPull',
      );

      return FaceContrastExport(
        filePath: latestPath,
        stampedFilePath: stampedPath,
        charCount: base64Value.length,
        adbPullCommand: adbPull,
      );
    } catch (e) {
      log('face_contrast_export_failed', component: 'API', detail: '$e');
      return null;
    }
  }

  @visibleForTesting
  static String adbPullCommand(String devicePath) => 'adb pull $devicePath .';

  static Future<Directory> _resolveTempDirectory() async {
    final override = resolveTempDirectoryOverride;
    if (override != null) return override();
    return getTemporaryDirectory();
  }

  static String truncate(String text, {int maxLen = 200}) =>
      ProviderTrace.truncate(text, maxLen: maxLen);

  static Stopwatch start() => ProviderTrace.start();

  static int elapsed(Stopwatch? sw) => ProviderTrace.elapsed(sw);
}

@visibleForTesting
class FaceContrastExport {
  const FaceContrastExport({
    required this.filePath,
    required this.stampedFilePath,
    required this.charCount,
    required this.adbPullCommand,
  });

  final String filePath;
  final String stampedFilePath;
  final int charCount;
  final String adbPullCommand;
}
