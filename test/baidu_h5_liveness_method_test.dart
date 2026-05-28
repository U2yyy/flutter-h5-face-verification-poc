import 'package:facedetection/models/baidu_h5_liveness_method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all methods listed bottom-to-top with default plan IDs', () {
    expect(BaiduH5LivenessMethod.all.map((m) => m.planId), [
      '26109',
      '26110',
      '26111',
      '26112',
    ]);
  });

  test('byId resolves known method', () {
    expect(
      BaiduH5LivenessMethod.byId('action')?.label,
      'H5实时动作活体',
    );
  });
}
