import 'dart:typed_data';

import '../models/face_verification_result.dart';

/// Contract for cloud face verification / liveness providers.
abstract class FaceVerificationProvider {
  String get id;
  String get displayName;
  bool get isConfigured;

  /// Pure-API flow: reference photo + live capture video.
  Future<FaceVerificationResult> verifyWithReferenceAndVideo({
    required Uint8List referenceImageBytes,
    required Uint8List liveVideoBytes,
  });

  /// SaaS SDK flow step 1: obtain SdkToken for Tencent eKYC SDK.
  Future<FaceVerificationResult> requestSdkToken({
    required Uint8List referenceImageBytes,
  });

  /// SaaS SDK flow step 2: poll verification result after SDK completes.
  Future<FaceVerificationResult> fetchSdkVerificationResult({
    required String sdkToken,
  });
}
