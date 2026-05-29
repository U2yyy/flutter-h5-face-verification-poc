import '../utils/app_config.dart';

/// FinAuth H5 Lite overseas procedure types (get_token `procedure_type`).
enum FinAuthH5LivenessMethod {
  flash(
    tabLabel: '炫彩',
    label: 'Flash liveness (炫彩活体)',
    procedureType: 'flash',
  ),
  distance(
    tabLabel: '距离',
    label: 'Distance liveness (距离活体)',
    procedureType: 'distance',
  ),
  still(
    tabLabel: '静默',
    label: 'Still video liveness (静默活体)',
    procedureType: 'still',
  );

  const FinAuthH5LivenessMethod({
    required this.tabLabel,
    required this.label,
    required this.procedureType,
  });

  final String tabLabel;
  final String label;
  final String procedureType;

  static const all = FinAuthH5LivenessMethod.values;

  static FinAuthH5LivenessMethod fromEnv() {
    final configured = AppConfig.finauthProcedureType.trim().toLowerCase();
    for (final method in all) {
      if (method.procedureType == configured) return method;
    }
    return flash;
  }
}
