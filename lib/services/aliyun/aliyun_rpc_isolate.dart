import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../utils/aliyun_rpc_signer.dart';

/// Input for building a signed Aliyun RPC POST request off the UI isolate.
class AliyunRpcPostBodyInput {
  const AliyunRpcPostBodyInput({
    required this.accessKeyId,
    required this.accessKeySecret,
    required this.apiVersion,
    required this.regionId,
    required this.action,
    required this.queryParams,
    this.formDataParams = const {},
    this.faceContrastPictureBytes,
    this.faceContrastPictureUrl,
  });

  final String accessKeyId;
  final String accessKeySecret;
  final String apiVersion;
  final String regionId;
  final String action;
  final Map<String, String> queryParams;
  final Map<String, String> formDataParams;
  final Uint8List? faceContrastPictureBytes;
  final String? faceContrastPictureUrl;
}

/// Signed RPC POST pieces. InitFaceVerify: [queryString] empty, all params in [formBody].
class AliyunRpcSignedRequest {
  const AliyunRpcSignedRequest({
    required this.queryString,
    required this.formBody,
    required this.stringToSign,
  });

  final String queryString;
  final String formBody;
  final String stringToSign;
}

/// Builds signed query + body. Must remain a top-level function for [compute].
AliyunRpcSignedRequest buildAliyunRpcPostBody(AliyunRpcPostBodyInput input) {
  final formData = Map<String, String>.from(input.formDataParams);
  final pictureUrl = input.faceContrastPictureUrl?.trim();
  final pictureBytes = input.faceContrastPictureBytes;
  if (pictureUrl != null && pictureUrl.isNotEmpty) {
    formData['FaceContrastPictureUrl'] = pictureUrl;
  } else if (pictureBytes != null) {
    // Raw base64 string — signer percentEncodes once for sign + wire.
    formData['FaceContrastPicture'] = base64Encode(pictureBytes);
  }

  final signer = AliyunRpcSigner(
    accessKeyId: input.accessKeyId,
    accessKeySecret: input.accessKeySecret,
  );
  final signed = signer.signRequest(
    action: input.action,
    version: input.apiVersion,
    regionId: input.regionId,
    queryParams: input.queryParams,
    formDataParams: formData,
  );

  return AliyunRpcSignedRequest(
    queryString: signed.queryString,
    formBody: signed.formBody,
    stringToSign: signed.stringToSign,
  );
}
