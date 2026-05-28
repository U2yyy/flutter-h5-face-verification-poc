class EkycLaunchResult {
  const EkycLaunchResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
    this.extra,
  });

  final bool success;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, dynamic>? extra;

  factory EkycLaunchResult.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const EkycLaunchResult(
        success: false,
        errorCode: 'INVALID_RESPONSE',
        errorMessage: 'Native layer returned no data',
      );
    }

    final extraRaw = map['extra'];
    Map<String, dynamic>? extra;
    if (extraRaw is Map) {
      extra = extraRaw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return EkycLaunchResult(
      success: map['success'] == true,
      errorCode: map['errorCode']?.toString(),
      errorMessage: map['errorMessage']?.toString(),
      extra: extra,
    );
  }

  Map<String, dynamic> toMap() => {
        'success': success,
        if (errorCode != null) 'errorCode': errorCode,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (extra != null) 'extra': extra,
      };
}
