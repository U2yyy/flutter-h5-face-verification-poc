import '../utils/app_config.dart';

/// Baidu faceprint H5 real-time liveness variants (plan_id differs per method).
class BaiduH5LivenessMethod {
  const BaiduH5LivenessMethod({
    required this.id,
    required this.label,
    required this.tabLabel,
    required this.envKey,
    required this.defaultPlanId,
  });

  final String id;
  final String label;
  final String tabLabel;
  final String envKey;
  final String defaultPlanId;

  String get planId => AppConfig.envValue(envKey, defaultPlanId).trim();

  bool get isConfigured => planId.isNotEmpty;

  static const dazzlePupil = BaiduH5LivenessMethod(
    id: 'dazzle_pupil',
    label: 'H5实时炫瞳活体',
    tabLabel: '炫瞳',
    envKey: 'BAIDU_FACEPRINT_PLAN_ID_DAZZLE',
    defaultPlanId: '26109',
  );

  static const nearFar = BaiduH5LivenessMethod(
    id: 'near_far',
    label: 'H5远近活体',
    tabLabel: '远近',
    envKey: 'BAIDU_FACEPRINT_PLAN_ID_NEAR_FAR',
    defaultPlanId: '26110',
  );

  static const action = BaiduH5LivenessMethod(
    id: 'action',
    label: 'H5实时动作活体',
    tabLabel: '动作',
    envKey: 'BAIDU_FACEPRINT_PLAN_ID_ACTION',
    defaultPlanId: '26111',
  );

  static const silent = BaiduH5LivenessMethod(
    id: 'silent',
    label: 'H5实时静默活体',
    tabLabel: '静默',
    envKey: 'BAIDU_FACEPRINT_PLAN_ID_SILENT',
    defaultPlanId: '26112',
  );

  /// Console order bottom → top: 炫瞳, 远近, 动作, 静默.
  static const List<BaiduH5LivenessMethod> all = [
    dazzlePupil,
    nearFar,
    action,
    silent,
  ];

  static BaiduH5LivenessMethod? byId(String id) {
    for (final method in all) {
      if (method.id == id) return method;
    }
    return null;
  }
}
