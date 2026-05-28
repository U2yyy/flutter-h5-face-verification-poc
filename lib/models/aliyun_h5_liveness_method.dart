import '../utils/app_config.dart';

/// Aliyun CloudAuth PV_FV H5 liveness model variants (InitFaceVerify Model param).
class AliyunH5LivenessMethod {
  const AliyunH5LivenessMethod({
    required this.id,
    required this.label,
    required this.tabLabel,
    required this.model,
  });

  final String id;
  final String label;
  final String tabLabel;
  final String model;

  static const silent = AliyunH5LivenessMethod(
    id: 'silent',
    label: 'H5静默活体',
    tabLabel: '静默',
    model: 'SILENT_LIVENESS',
  );

  static const blink = AliyunH5LivenessMethod(
    id: 'blink',
    label: 'H5眨眼活体',
    tabLabel: '眨眼',
    model: 'LIVENESS',
  );

  static const photinus = AliyunH5LivenessMethod(
    id: 'photinus',
    label: 'H5眨眼炫彩活体',
    tabLabel: '炫彩',
    model: 'PHOTINUS_LIVENESS',
  );

  static const multiAction = AliyunH5LivenessMethod(
    id: 'multi_action',
    label: 'H5眨眼摇头活体',
    tabLabel: '动作',
    model: 'MULTI_ACTION',
  );

  static const moveAction = AliyunH5LivenessMethod(
    id: 'move_action',
    label: 'H5远近眨眼活体',
    tabLabel: '远近',
    model: 'MOVE_ACTION',
  );

  static const multiPhotinus = AliyunH5LivenessMethod(
    id: 'multi_photinus',
    label: 'H5眨眼摇头炫彩活体',
    tabLabel: '多炫彩',
    model: 'MULTI_PHOTINUS',
  );

  static List<AliyunH5LivenessMethod> get all => [
        silent,
        blink,
        photinus,
        multiAction,
        moveAction,
        multiPhotinus,
      ];

  static AliyunH5LivenessMethod get defaultMethod {
    final configured = AppConfig.aliyunCloudAuthModel.trim();
    if (configured.isEmpty) return moveAction;
    for (final method in all) {
      if (method.model == configured) return method;
    }
    return moveAction;
  }

  static AliyunH5LivenessMethod? byId(String id) {
    for (final method in all) {
      if (method.id == id) return method;
    }
    return null;
  }
}
