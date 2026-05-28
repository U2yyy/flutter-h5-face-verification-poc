import 'dart:convert';

import 'package:facedetection/services/aliyun/aliyun_cloudauth_api_client.dart';
import 'package:facedetection/utils/aliyun_rpc_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AliyunCloudAuthApiClient RPC POST wire format', () {
    test('buildSignedRpcPostRequest sends InitFaceVerify all-in-body', () {
      const slashyBase64 = '/9j/4AAQ+SkZJRg==';
      final signer = AliyunRpcSigner(
        accessKeyId: 'test-key',
        accessKeySecret: 'test-secret',
      );
      final signed = signer.signRequest(
        action: 'InitFaceVerify',
        version: '2019-03-07',
        regionId: 'cn-shanghai',
        queryParams: {'SceneId': '1'},
        formDataParams: {
          'FaceContrastPicture': slashyBase64,
          'Model': 'MOVE_ACTION',
          'Crop': 'T',
        },
        signatureNonce: 'fixed-nonce-1234567890123456',
        timestamp: DateTime.utc(2020, 1, 2, 3, 4, 5),
      );

      final request = AliyunCloudAuthApiClient.buildSignedRpcPostRequest(
        host: 'cloudauth.aliyuncs.com',
        queryString: signed.queryString,
        formBody: signed.formBody,
      );

      expect(request.method, 'POST');
      expect(request.url.query, isEmpty);
      expect(request.url.path, '/');
      expect(utf8.decode(request.bodyBytes), signed.formBody);
      expect(signed.formBody, contains('FaceContrastPicture=%2F9j%2F'));
      expect(signed.formBody, contains('Signature='));
      expect(signed.formBody, isNot(contains('%252F')));
      expect(
        request.headers['Content-Type'],
        'application/x-www-form-urlencoded; charset=utf-8',
      );
    });

    test('buildSignedRpcPostRequest keeps DescribeFaceVerify query-only', () {
      final signer = AliyunRpcSigner(
        accessKeyId: 'test-key',
        accessKeySecret: 'test-secret',
      );
      final signed = signer.signRequest(
        action: 'DescribeFaceVerify',
        version: '2019-03-07',
        regionId: 'cn-shanghai',
        queryParams: {
          'SceneId': '1',
          'CertifyId': 'cert-1',
        },
        signatureNonce: 'fixed-nonce-1234567890123456',
        timestamp: DateTime.utc(2020, 1, 2, 3, 4, 5),
      );

      final request = AliyunCloudAuthApiClient.buildSignedRpcPostRequest(
        host: 'cloudauth.aliyuncs.com',
        queryString: signed.queryString,
        formBody: signed.formBody,
      );

      expect(request.url.query, isNotEmpty);
      expect(request.url.query, contains('DescribeFaceVerify'));
      expect(request.bodyBytes, isEmpty);
    });

    test('rejects double-encoded form bodies before send', () {
      expect(
        () => AliyunCloudAuthApiClient.buildSignedRpcPostRequest(
          host: 'cloudauth.aliyuncs.com',
          queryString: 'Action=InitFaceVerify',
          formBody: 'FaceContrastPicture=%252F9j',
        ),
        throwsStateError,
      );
    });
  });

  group('AliyunCloudAuthApiClient error parsing', () {
    test('extracts Code and RequestId from HTTP 400 JSON body', () {
      final client = AliyunCloudAuthApiClient(
        accessKeyId: 'test-key',
        accessKeySecret: 'test-secret',
      );

      final exception = client.buildApiExceptionForTest(
        httpStatus: 400,
        rawBody: '''
{
  "RequestId": "8906582E-6722-409A-A6C4-0E7863B733A5",
  "HostId": "cloudauth.aliyuncs.com",
  "Code": "SignatureDoesNotMatch",
  "Message": "Specified signature is not matched with our calculation."
}
''',
      );

      expect(exception.code, 'SignatureDoesNotMatch');
      expect(exception.requestId, '8906582E-6722-409A-A6C4-0E7863B733A5');
      expect(exception.message, contains('signature is not matched'));
    });

    test('extracts Code and RequestId from HTTP 400 XML body', () {
      final client = AliyunCloudAuthApiClient(
        accessKeyId: 'test-key',
        accessKeySecret: 'test-secret',
      );

      final exception = client.buildApiExceptionForTest(
        httpStatus: 400,
        rawBody: '''
<?xml version='1.0' encoding='UTF-8'?>
<Error>
  <RequestId>ABC-123-XYZ</RequestId>
  <HostId>cloudauth.aliyuncs.com</HostId>
  <Code>SignatureDoesNotMatch</Code>
  <Message>Specified signature is not matched with our calculation.</Message>
</Error>
''',
      );

      expect(exception.code, 'SignatureDoesNotMatch');
      expect(exception.requestId, 'ABC-123-XYZ');
    });

    test('extracts SignatureDoesNotMatch from plain text body', () {
      final client = AliyunCloudAuthApiClient(
        accessKeyId: 'test-key',
        accessKeySecret: 'test-secret',
      );

      final exception = client.buildApiExceptionForTest(
        httpStatus: 400,
        rawBody:
            'SignatureDoesNotMatch\nserver string to sign is:POST&%2F&AccessKeyId%3Dtest',
      );

      expect(exception.code, 'SignatureDoesNotMatch');
      expect(exception.message, contains('server string to sign is:'));
      expect(exception.message, contains('omitted'));
      expect(exception.message.length, lessThan(200));
    });

    test('extracts fields from large JSON without full body decode', () {
      final client = AliyunCloudAuthApiClient(
        accessKeyId: 'test-key',
        accessKeySecret: 'test-secret',
      );

      final hugePayload = 'A' * 600000;
      final rawBody =
          '{"RequestId":"REQ-LARGE-1","Code":"SignatureDoesNotMatch",'
          '"Message":"Specified signature is not matched. server string to sign is:$hugePayload"}';

      final fields = client.extractErrorFieldsForTest(rawBody);
      expect(fields?['Code'], 'SignatureDoesNotMatch');
      expect(fields?['RequestId'], 'REQ-LARGE-1');
      expect(fields?['Message'], contains('server string to sign is:'));
      expect(fields?['Message'], contains('omitted'));
      expect(fields?['Message']!.length,
          lessThanOrEqualTo(AliyunCloudAuthApiClient.maxErrorMessageLen + 40));

      final exception = client.buildApiExceptionForTest(
        httpStatus: 400,
        rawBody: rawBody,
      );
      expect(exception.code, 'SignatureDoesNotMatch');
      expect(exception.message.length,
          lessThanOrEqualTo(AliyunCloudAuthApiClient.maxErrorMessageLen + 40));
      expect(exception.message, isNot(contains(hugePayload.substring(0, 100))));
    });
  });
}
