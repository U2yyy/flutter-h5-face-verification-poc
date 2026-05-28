import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:facedetection/services/aliyun/aliyun_rpc_isolate.dart';
import 'package:facedetection/utils/aliyun_rpc_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AliyunRpcSigner', () {
    const accessKeyId = 'test-access-key-id';
    const accessKeySecret = 'test-access-key-secret';
    final fixedTime = DateTime.utc(2020, 1, 2, 3, 4, 5);
    const fixedNonce = 'fixed-signature-nonce';

    AliyunRpcSigner signer() => AliyunRpcSigner(
          accessKeyId: accessKeyId,
          accessKeySecret: accessKeySecret,
        );

    test('hasDoublePercentEncoding detects %252F-style bodies', () {
      expect(AliyunRpcSigner.hasDoublePercentEncoding('FaceContrastPicture=%2F9j'), isFalse);
      expect(AliyunRpcSigner.hasDoublePercentEncoding('FaceContrastPicture=%252F9j'), isTrue);
    });

    test('percentEncode uses single-pass Aliyun rules', () {
      expect(AliyunRpcSigner.percentEncode('/9j/+AB/='), '%2F9j%2F%2BAB%2F%3D');
      expect(AliyunRpcSigner.percentEncode('a b*c~d'), 'a%20b%2Ac~d');
      expect(
        AliyunRpcSigner.percentEncode('/9j/+AB/='),
        isNot(contains('%252F')),
      );
    });

    test('percentEncode matches Java URLEncoder for parentheses and apostrophe', () {
      expect(AliyunRpcSigner.percentEncode('('), '%28');
      expect(AliyunRpcSigner.percentEncode(')'), '%29');
      expect(AliyunRpcSigner.percentEncode("'"), '%27');
      expect(
        AliyunRpcSigner.percentEncode(
          'Mozilla/5.0 (Linux; Android 15; Pixel 7 Build/AP3A.241105.007; wv) AppleWebKit',
        ),
        'Mozilla%2F5.0%20%28Linux%3B%20Android%2015%3B%20Pixel%207%20Build%2FAP3A.241105.007%3B%20wv%29%20AppleWebKit',
      );
    });

    test('MetaInfo ua parentheses produce server-matching stringToSign prefix', () {
      const ua =
          'Mozilla/5.0 (Linux; Android 15; Pixel 7 Build/AP3A.241105.007; wv) AppleWebKit';
      const metaInfo = '{"zimVer":"3.0.0","ua":"$ua"}';

      final result = signer().signRequest(
        action: 'InitFaceVerify',
        version: '2019-03-07',
        regionId: 'cn-shanghai',
        queryParams: {
          'SceneId': '1000018821',
          'OuterOrderNo': 'order-ua-parens',
          'ProductCode': 'PV_FV',
          'UserId': 'user-1',
          'MetaInfo': metaInfo,
          'ReturnUrl': 'https://facedetection.local/aliyun/h5/callback',
          'CertifyUrlType': 'H5',
        },
        formDataParams: {
          'Model': 'MOVE_ACTION',
          'Crop': 'T',
          'FaceContrastPictureUrl': 'https://example.com/face.jpg',
        },
        timestamp: fixedTime,
        signatureNonce: fixedNonce,
      );

      expect(
        result.stringToSign,
        contains('Mozilla%252F5.0%2520%2528Linux%253B%2520Android%252015'),
      );
      expect(result.stringToSign, isNot(contains('(Linux')));
      expect(result.stringToSign, isNot(contains('wv)')));
      expect(result.stringToSign, contains('%2529%2520AppleWebKit'));
    });

    test('official DescribeVerifyToken GET example produces expected signature', () {
      const officialSecret = 'testsecret';
      final params = {
        'AccessKeyId': 'testid',
        'Action': 'DescribeVerifyToken',
        'BizId': 'abc1234',
        'BizType': 'testforRPBioOnly',
        'Format': 'XML',
        'IdCardNumber': '33010320191201****',
        'Name': '张三',
        'SignatureMethod': 'HMAC-SHA1',
        'SignatureNonce': '3ee8c1b8-83d3-44af-a94f-4e0ad82fd6cf',
        'SignatureVersion': '1.0',
        'Timestamp': '2016-02-23T12:46:24Z',
        'Version': '2019-03-07',
      };
      final canonical = AliyunRpcSigner.canonicalizedQueryString(params);
      final stringToSign = 'GET&${AliyunRpcSigner.percentEncode('/')}&'
          '${AliyunRpcSigner.percentEncode(canonical)}';
      final signature = base64Encode(
        Hmac(sha1, utf8.encode('$officialSecret&'))
            .convert(utf8.encode(stringToSign))
            .bytes,
      );

      expect(signature, 'hcG5rZI5AHbprhcja7t6N7h4Viw=');
    });

    test('official DirectMail POST example produces expected signature', () {
      const officialSecret = 'testsecret';
      final params = {
        'AccessKeyId': 'testid',
        'AccountName': "<a%b'>",
        'Action': 'SingleSendMail',
        'AddressType': '1',
        'Format': 'XML',
        'HtmlBody': '4',
        'RegionId': 'cn-hangzhou',
        'ReplyToAddress': 'true',
        'SignatureMethod': 'HMAC-SHA1',
        'SignatureNonce': 'c1b2c332-4cfb-4a0f-b8cc-ebe622aa0a5c',
        'SignatureVersion': '1.0',
        'Subject': '3',
        'TagName': '2',
        'Timestamp': '2016-10-20T06:27:56Z',
        'ToAddress': '1@test.com',
        'Version': '2015-11-23',
      };
      final canonical = AliyunRpcSigner.canonicalizedQueryString(params);
      final stringToSign = 'POST&${AliyunRpcSigner.percentEncode('/')}&'
          '${AliyunRpcSigner.percentEncode(canonical)}';
      final signature = base64Encode(
        Hmac(sha1, utf8.encode('$officialSecret&'))
            .convert(utf8.encode(stringToSign))
            .bytes,
      );

      expect(signature, 'llJfXJjBW3OacrVgxxsITgYaYm0=');
    });

    test('InitFaceVerify uses all-in-body transport (empty query)', () {
      const slashyBase64 = '/9j/4AAQ+SkZJRg==';
      const metaInfo = '{"deviceType":"phone","note":"a b"}';

      final result = signer().signRequest(
        action: 'InitFaceVerify',
        version: '2019-03-07',
        regionId: 'cn-shanghai',
        queryParams: {
          'SceneId': '1000018821',
          'OuterOrderNo': 'e95f753f1d09ae385964b9aab39c2890',
          'ProductCode': 'PV_FV',
          'UserId': 'facedetection-demo-user',
          'MetaInfo': metaInfo,
          'ReturnUrl': 'https://facedetection.local/aliyun/h5/callback',
          'CertifyUrlType': 'H5',
        },
        formDataParams: {
          'Model': 'MOVE_ACTION',
          'Crop': 'T',
          'FaceContrastPicture': slashyBase64,
        },
        timestamp: fixedTime,
        signatureNonce: fixedNonce,
      );

      expect(result.queryString, isEmpty);
      expect(result.formBody, isNotEmpty);
      expect(result.formBody, contains('Action=InitFaceVerify'));
      expect(result.formBody, contains('Signature='));
      expect(result.formBody, contains('MetaInfo='));
      expect(result.formBody, contains('CertifyUrlType=H5'));
      expect(result.formBody, isNot(contains('CallbackUrl=')));
      expect(result.formBody, isNot(contains('SourceIp=')));
      expect(result.formBody, isNot(contains('VoluntaryCustomizedContent=')));
      expect(result.formBody, isNot(contains('CertType=')));
      expect(result.formBody, contains('Model=MOVE_ACTION'));
      expect(result.formBody, contains('Crop=T'));
      expect(result.formBody, contains('FaceContrastPicture=%2F9j%2F'));
      expect(result.formBody, isNot(contains('%252F')));

      expect(result.stringToSign, startsWith('POST&%2F&'));
      // Canonical values like %2F are encoded again inside stringToSign → %252F.
      expect(result.stringToSign, contains('%252F9j'));

      final mergedForSign = AliyunRpcSigner.canonicalizedQueryString({
        for (final entry in result.parameters.entries)
          if (entry.key != 'Signature') entry.key: entry.value,
      });
      final expectedStringToSign = 'POST&${AliyunRpcSigner.percentEncode('/')}&'
          '${AliyunRpcSigner.percentEncode(mergedForSign)}';
      expect(result.stringToSign, expectedStringToSign);

      final expectedSignature = base64Encode(
        Hmac(sha1, utf8.encode('$accessKeySecret&'))
            .convert(utf8.encode(expectedStringToSign))
            .bytes,
      );
      expect(result.parameters['Signature'], expectedSignature);
    });

    test('FaceContrastPictureUrl is mutually exclusive with base64 picture', () {
      final result = signer().signRequest(
        action: 'InitFaceVerify',
        version: '2019-03-07',
        regionId: 'cn-shanghai',
        queryParams: {
          'SceneId': '1',
          'OuterOrderNo': 'order-1',
          'ProductCode': 'PV_FV',
          'UserId': 'user-1',
          'MetaInfo': '{}',
          'ReturnUrl': 'https://example.com/cb',
          'CertifyUrlType': 'H5',
        },
        formDataParams: {
          'Model': 'MOVE_ACTION',
          'Crop': 'T',
          'FaceContrastPictureUrl': 'https://example.com/face.jpg',
        },
        timestamp: fixedTime,
        signatureNonce: fixedNonce,
      );

      expect(result.formBody, contains('FaceContrastPictureUrl='));
      expect(result.formBody, isNot(contains('FaceContrastPicture=')));
    });

    test('split query+body wire reproduces server %252F canonical mismatch', () {
      const slashyBase64 = '/9j/4AAQ+SkZJRg==';
      final signed = signer().signRequest(
        action: 'InitFaceVerify',
        version: '2019-03-07',
        regionId: 'cn-shanghai',
        queryParams: {'SceneId': '1', 'MetaInfo': '{}'},
        formDataParams: {
          'FaceContrastPicture': slashyBase64,
          'Model': 'MOVE_ACTION',
          'Crop': 'T',
        },
        timestamp: fixedTime,
        signatureNonce: fixedNonce,
      );

      final oldQuery = AliyunRpcSigner.canonicalizedQueryString({
        for (final e in signed.parameters.entries)
          if (!aliyunInitFaceVerifyFormDataKeys.contains(e.key)) e.key: e.value,
      });
      final oldBody = AliyunRpcSigner.formUrlEncodedBody({
        for (final e in signed.parameters.entries)
          if (aliyunInitFaceVerifyFormDataKeys.contains(e.key)) e.key: e.value,
      });

      final clientCanonical = AliyunRpcSigner.canonicalizedQueryString({
        for (final e in signed.parameters.entries)
          if (e.key != 'Signature') e.key: e.value,
      });
      final serverCanonical = AliyunRpcSigner.canonicalizedQueryStringFromSplitWire(
        queryString: oldQuery,
        formBody: oldBody,
      );

      expect(clientCanonical, contains('FaceContrastPicture=%2F9j'));
      expect(clientCanonical, isNot(contains('%252F')));
      expect(serverCanonical, contains('FaceContrastPicture=%252F9j'));
      expect(serverCanonical, isNot(equals(clientCanonical)));
    });

    test('all-in-body wire matches client canonical after server form decode', () {
      const slashyBase64 = '/9j/4AAQ+SkZJRg==';
      final signed = signer().signRequest(
        action: 'InitFaceVerify',
        version: '2019-03-07',
        regionId: 'cn-shanghai',
        queryParams: {'SceneId': '1'},
        formDataParams: {
          'FaceContrastPicture': slashyBase64,
          'Model': 'MOVE_ACTION',
        },
        timestamp: fixedTime,
        signatureNonce: fixedNonce,
      );

      final clientCanonical = AliyunRpcSigner.canonicalizedQueryString({
        for (final e in signed.parameters.entries)
          if (e.key != 'Signature') e.key: e.value,
      });
      final decodedBodyParams = Uri.splitQueryString(signed.formBody, encoding: utf8)
        ..remove('Signature');
      final serverCanonical = AliyunRpcSigner.canonicalizedQueryString(
        decodedBodyParams,
      );

      expect(signed.queryString, isEmpty);
      expect(serverCanonical, equals(clientCanonical));
      expect(serverCanonical, isNot(contains('%252F')));
    });

    test('DescribeFaceVerify keeps all params in query string', () {
      final result = signer().signRequest(
        action: 'DescribeFaceVerify',
        version: '2019-03-07',
        regionId: 'cn-shanghai',
        queryParams: {
          'SceneId': '1000000000',
          'CertifyId': 'certify-abc',
        },
        timestamp: fixedTime,
        signatureNonce: fixedNonce,
      );

      expect(result.queryString, isNotEmpty);
      expect(result.formBody, isEmpty);
      expect(result.queryString, contains('Action=DescribeFaceVerify'));
      expect(result.queryString, contains('CertifyId=certify-abc'));
      expect(result.queryString, contains('Signature='));
    });

    test('optional CertifyUrlType is included when set', () {
      final result = signer().signRequest(
        action: 'InitFaceVerify',
        version: '2019-03-07',
        regionId: 'cn-shanghai',
        queryParams: {
          'SceneId': '1000018821',
          'CertifyUrlType': 'H5',
          'CertifyUrlStyle': 'S',
          'ProcedurePriority': 'url',
        },
        formDataParams: {
          'Model': 'MOVE_ACTION',
          'Crop': 'T',
        },
        timestamp: fixedTime,
        signatureNonce: fixedNonce,
      );

      expect(result.formBody, contains('CertifyUrlType=H5'));
      expect(result.formBody, contains('CertifyUrlStyle=S'));
      expect(result.formBody, contains('ProcedurePriority=url'));
    });

    test('does not double-encode percent signs in encoded values', () {
      const slashyBase64 = '/9j/4AAQ+SkZJRg==';
      final result = signer().signRequest(
        action: 'InitFaceVerify',
        version: '2019-03-07',
        regionId: 'cn-shanghai',
        queryParams: {
          'SceneId': '1000000000',
        },
        formDataParams: {
          'FaceContrastPicture': slashyBase64,
          'Model': 'MOVE_ACTION',
        },
      );

      expect(result.formBody, contains('FaceContrastPicture=%2F9j%2F'));
      expect(result.formBody, isNot(contains('%252F')));
    });
  });

  group('buildAliyunRpcPostBody', () {
    test('single-encodes jpeg base64 slashes in FaceContrastPicture body', () {
      final jpegLike = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 74, 70]);
      final signed = buildAliyunRpcPostBody(
        AliyunRpcPostBodyInput(
          accessKeyId: 'test-key',
          accessKeySecret: 'test-secret',
          apiVersion: '2019-03-07',
          regionId: 'cn-shanghai',
          action: 'InitFaceVerify',
          queryParams: {
            'SceneId': 'scene-1',
            'OuterOrderNo': 'order-1',
            'ProductCode': 'PV_FV',
            'UserId': 'user-1',
            'MetaInfo': '{"deviceType":"phone"}',
            'ReturnUrl': 'https://example.com/cb',
            'CertifyUrlType': 'H5',
          },
          formDataParams: {
            'Model': 'MOVE_ACTION',
            'Crop': 'T',
          },
          faceContrastPictureBytes: jpegLike,
        ),
      );

      expect(signed.queryString, isEmpty);
      expect(signed.formBody, isNotEmpty);
      expect(signed.stringToSign, startsWith('POST&%2F&'));
      expect(signed.formBody, contains('Action=InitFaceVerify'));
      expect(signed.formBody, contains('Version=2019-03-07'));
      expect(signed.formBody, contains('RegionId=cn-shanghai'));
      expect(signed.formBody, contains('Format=JSON'));
      expect(signed.formBody, contains('Signature='));
      expect(signed.formBody, contains('MetaInfo='));
      expect(signed.formBody, contains('CertifyUrlType=H5'));
      expect(signed.formBody, isNot(contains('CallbackUrl=')));
      expect(signed.formBody, contains('FaceContrastPicture=%2F9j%2F'));
      expect(signed.formBody, contains('Model=MOVE_ACTION'));
      expect(signed.formBody, contains('Crop=T'));
      expect(signed.formBody, isNot(contains('%252F')));
    });

    test('buildAliyunRpcPostBody uses FaceContrastPictureUrl when provided', () {
      const pictureUrl = 'https://example.com/reference.jpg';
      final signed = buildAliyunRpcPostBody(
        AliyunRpcPostBodyInput(
          accessKeyId: 'test-key',
          accessKeySecret: 'test-secret',
          apiVersion: '2019-03-07',
          regionId: 'cn-shanghai',
          action: 'InitFaceVerify',
          queryParams: {
            'SceneId': 'scene-1',
            'MetaInfo': '{}',
            'ReturnUrl': 'https://example.com/cb',
          },
          formDataParams: {
            'Model': 'MOVE_ACTION',
            'Crop': 'T',
          },
          faceContrastPictureUrl: pictureUrl,
        ),
      );

      expect(signed.formBody, contains('FaceContrastPictureUrl='));
      expect(signed.formBody, isNot(contains('FaceContrastPicture=')));
      expect(
        signed.formBody,
        contains(
          'FaceContrastPictureUrl=${Uri.encodeComponent(pictureUrl)}',
        ),
      );
    });
  });
}
