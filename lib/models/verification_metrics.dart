class VerificationMetrics {
  const VerificationMetrics({
    required this.providerId,
    required this.providerName,
    required this.latency,
    required this.success,
    required this.isMatch,
    required this.isLive,
    required this.timestamp,
    this.similarity,
    this.errorMessage,
    this.apiAction,
  });

  final String providerId;
  final String providerName;
  final Duration latency;
  final bool success;
  final bool isMatch;
  final bool isLive;
  final double? similarity;
  final DateTime timestamp;
  final String? errorMessage;
  final String? apiAction;

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'providerName': providerName,
        'latencyMs': latency.inMilliseconds,
        'success': success,
        'isMatch': isMatch,
        'isLive': isLive,
        'similarity': similarity,
        'timestamp': timestamp.toIso8601String(),
        'errorMessage': errorMessage,
        'apiAction': apiAction,
      };
}

/// In-memory store for benchmark metrics across providers.
class MetricsRecorder {
  MetricsRecorder._();

  static final MetricsRecorder instance = MetricsRecorder._();

  final List<VerificationMetrics> _records = [];

  List<VerificationMetrics> get records => List.unmodifiable(_records);

  void record(VerificationMetrics metrics) {
    _records.insert(0, metrics);
  }

  void clear() => _records.clear();

  List<VerificationMetrics> forProvider(String providerId) {
    return _records.where((m) => m.providerId == providerId).toList();
  }
}
