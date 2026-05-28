import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Tencent CompareFaceLiveness payload limits (Base64-encoded size).
class MediaLimits {
  static const int maxImageBase64Bytes = 3 * 1024 * 1024;
  /// Aliyun InitFaceVerify rejects FaceContrastPicture payloads over 1 MB.
  static const int maxAliyunFaceContrastBase64Bytes = 1024 * 1024;
  static const int maxVideoBase64Bytes = 8 * 1024 * 1024;
  static const int maxBaiduVideoBase64Bytes = 20 * 1024 * 1024;
}

class MediaUtils {
  /// Exact Base64 output length without encoding (avoids main-thread work).
  static int base64EncodedLength(Uint8List bytes) =>
      estimatedBase64EncodedLength(bytes.length);

  static int estimatedBase64EncodedLength(int byteLength) {
    if (byteLength <= 0) return 0;
    return ((byteLength + 2) ~/ 3) * 4;
  }

  /// Base64-encodes large payloads off the UI isolate to avoid ANR.
  static Future<String> encodeBase64Async(Uint8List bytes) {
    if (bytes.length <= 256 * 1024) {
      return Future.value(base64Encode(bytes));
    }
    return compute(_encodeBase64Isolate, bytes);
  }

  static String? validateVideoForBaiduApi(Uint8List videoBytes) {
    final encodedLen = base64EncodedLength(videoBytes);
    if (encodedLen > MediaLimits.maxBaiduVideoBase64Bytes) {
      final mb = (encodedLen / (1024 * 1024)).toStringAsFixed(1);
      return 'Video is too large after encoding ($mb MB). '
          'Baidu allows max 20 MB. Record a shorter clip.';
    }
    if (videoBytes.isEmpty) {
      return 'Video file is empty. Please record again.';
    }
    return null;
  }

  static String? validateVideoForApi(Uint8List videoBytes) {
    final encodedLen = base64EncodedLength(videoBytes);
    if (encodedLen > MediaLimits.maxVideoBase64Bytes) {
      final mb = (encodedLen / (1024 * 1024)).toStringAsFixed(1);
      return 'Video is too large after encoding ($mb MB). '
          'Tencent allows max 8 MB. Record a shorter clip (2–6 seconds).';
    }
    if (videoBytes.isEmpty) {
      return 'Video file is empty. Please record again.';
    }
    return null;
  }

  static String? validateImageForApi(Uint8List imageBytes) {
    if (imageBytes.isEmpty) {
      return 'Reference image is empty.';
    }
    if (base64EncodedLength(imageBytes) > MediaLimits.maxImageBase64Bytes) {
      return 'Reference image still exceeds 3 MB after compression. '
          'Choose a smaller photo.';
    }
    return null;
  }

  /// Compress reference photo for Aliyun FaceContrastPicture (&lt;1 MB Base64).
  static Future<Uint8List> prepareReferenceImageForAliyun(Uint8List bytes) async {
    final prepared = await prepareReferenceImage(bytes);
    if (base64EncodedLength(prepared) <= MediaLimits.maxAliyunFaceContrastBase64Bytes) {
      return prepared;
    }

    return compute(
      _prepareReferenceImageForAliyunIsolate,
      prepared,
    );
  }

  /// Resize/compress reference photo to stay within Tencent's 3 MB Base64 limit.
  static Future<Uint8List> prepareReferenceImage(Uint8List bytes) async {
    if (base64EncodedLength(bytes) <= MediaLimits.maxImageBase64Bytes) {
      return bytes;
    }

    return compute(_prepareReferenceImageIsolate, bytes);
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

String _encodeBase64Isolate(Uint8List bytes) => base64Encode(bytes);

Uint8List _prepareReferenceImageForAliyunIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return bytes;
  }

  img.Image current = decoded;
  for (final maxWidth in [1280, 960, 640, 480, 360]) {
    if (current.width > maxWidth) {
      current = img.copyResize(current, width: maxWidth);
    }
    for (final quality in [85, 75, 65, 55, 45, 35]) {
      final jpg = Uint8List.fromList(img.encodeJpg(current, quality: quality));
      if (MediaUtils.base64EncodedLength(jpg) <=
          MediaLimits.maxAliyunFaceContrastBase64Bytes) {
        return jpg;
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(current, quality: 30));
}

Uint8List _prepareReferenceImageIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return bytes;
  }

  img.Image current = decoded;
  for (final maxWidth in [1920, 1280, 960, 640, 480]) {
    if (current.width > maxWidth) {
      current = img.copyResize(current, width: maxWidth);
    }
    for (final quality in [90, 80, 70, 60]) {
      final jpg = Uint8List.fromList(img.encodeJpg(current, quality: quality));
      if (MediaUtils.base64EncodedLength(jpg) <= MediaLimits.maxImageBase64Bytes) {
        return jpg;
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(current, quality: 55));
}
