class EegSample {
  const EegSample({
    required this.channels,
    required this.sampleRate,
    required this.timestamp,
    this.source = 'unknown',
  });

  final List<double> channels;
  final double sampleRate;
  final DateTime timestamp;
  final String source;

  double get frontal => channels.isEmpty ? 0.0 : channels.first;
}
