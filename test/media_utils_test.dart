import 'dart:convert';
import 'dart:typed_data';

import 'package:facedetection/utils/media_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaUtils', () {
    test('validateVideoForApi rejects oversized payload', () {
      final large = Uint8List(7 * 1024 * 1024);
      final error = MediaUtils.validateVideoForApi(large);
      expect(error, isNotNull);
      expect(error, contains('too large'));
    });

    test('validateVideoForApi accepts small payload', () {
      final small = Uint8List.fromList(List.filled(1024, 1));
      expect(MediaUtils.validateVideoForApi(small), isNull);
    });

    test('base64EncodedLength matches encode length', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(
        MediaUtils.base64EncodedLength(bytes),
        base64Encode(bytes).length,
      );
    });
  });
}
