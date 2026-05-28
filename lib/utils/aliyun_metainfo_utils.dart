import 'dart:convert';

/// Unwraps MetaInfo from [WebViewController.runJavaScriptReturningResult].
///
/// On Android, JS string results are JSON-encoded (outer quotes + escaped inner
/// quotes), e.g. `"{\"bioMetaInfo\":\"4.1.0\"}"`. This decodes that wrapper so
/// MetaInfo is valid JSON for InitFaceVerify.
String unwrapAliyunMetaInfoFromJsResult(Object? value) {
  if (value == null) return '';
  final text = value.toString();
  if (text.isEmpty) return '';

  try {
    final decoded = jsonDecode(text);
    if (decoded is String) return decoded;
    if (decoded is Map || decoded is List) return jsonEncode(decoded);
  } catch (_) {}

  if (text.length >= 2 &&
      ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith("'") && text.endsWith("'")))) {
    return text.substring(1, text.length - 1);
  }
  return text;
}
