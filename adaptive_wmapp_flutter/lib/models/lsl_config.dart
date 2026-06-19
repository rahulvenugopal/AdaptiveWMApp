/// User-editable LSL configuration for EEG stream discovery in ACDMT.
/// Persisted via [DeviceConfigService].
class LslConfig {
  final String eegStreamType;
  final String eegStreamName;
  final List<String> eegKnownPeers;
  final double resolveTimeoutSeconds;

  const LslConfig({
    this.eegStreamType = 'EEG',
    this.eegStreamName = '',
    this.eegKnownPeers = const [],
    this.resolveTimeoutSeconds = 5.0,
  });

  LslConfig copyWith({
    String? eegStreamType,
    String? eegStreamName,
    List<String>? eegKnownPeers,
    double? resolveTimeoutSeconds,
  }) =>
      LslConfig(
        eegStreamType: eegStreamType ?? this.eegStreamType,
        eegStreamName: eegStreamName ?? this.eegStreamName,
        eegKnownPeers: eegKnownPeers ?? this.eegKnownPeers,
        resolveTimeoutSeconds:
            resolveTimeoutSeconds ?? this.resolveTimeoutSeconds,
      );
}
