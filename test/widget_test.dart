import 'package:facedetection/main.dart';
import 'package:facedetection/services/face_verification_provider.dart';
import 'package:facedetection/utils/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppConfig.load();
  });

  testWidgets('App loads verification screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FaceDetectionApp());
    await tester.pumpAndSettle();

    expect(find.text('Face Verification'), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Tencent FaceID'), findsOneWidget);
    expect(find.text('Pure API'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<FaceVerificationProvider>));
    await tester.pumpAndSettle();
    expect(find.text('Aliyun CloudAuth'), findsOneWidget);
    expect(find.text('Baidu AI'), findsOneWidget);
  });

  testWidgets('Baidu SaaS H5 shows four liveness method tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FaceDetectionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<FaceVerificationProvider>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Baidu AI').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('SaaS H5'));
    await tester.pumpAndSettle();

    expect(find.text('炫瞳'), findsOneWidget);
    expect(find.text('远近'), findsOneWidget);
    expect(find.text('动作'), findsOneWidget);
    expect(find.text('静默'), findsOneWidget);
    expect(find.text('26109'), findsOneWidget);
    expect(find.text('26112'), findsOneWidget);
  });

  testWidgets('Aliyun SaaS H5 shows liveness model tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FaceDetectionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<FaceVerificationProvider>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aliyun CloudAuth').last);
    await tester.pumpAndSettle();

    expect(find.text('SaaS H5'), findsOneWidget);
    expect(find.text('静默'), findsOneWidget);
    expect(find.text('MOVE_ACTION'), findsOneWidget);
    expect(find.text('Pure API'), findsNothing);
  });
}
