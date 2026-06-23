import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DeviceConfig {
  const DeviceConfig({
    this.xampPrefix = 'AXXSPU00003',
    this.waveformGain = 1.0,
    this.stackedChannels = true,
    this.visibleChannels = const [],
    this.maxReconnectAttempts = 10,
    this.eegDisplayDuration = 10,
    this.eegSource = 'bluetooth',
    this.lslStreamType = 'EEG',
    this.lslStreamName = '',
    this.lslTimeout = 5.0,
    this.showSleepinessPreSession = false,
    this.showSleepinessPostSession = false,
    this.notchEnabled = true,
    this.bandpassEnabled = false,
    this.eegDisplayMode = 'paradigm_only',
  });

  final String xampPrefix;
  final double waveformGain;
  final bool stackedChannels;
  final List<int> visibleChannels;
  final int maxReconnectAttempts;
  final int eegDisplayDuration;
  final String eegSource;
  final String lslStreamType;
  final String lslStreamName;
  final double lslTimeout;
  final bool showSleepinessPreSession;
  final bool showSleepinessPostSession;
  final bool notchEnabled;
  final bool bandpassEnabled;
  final String eegDisplayMode;

  DeviceConfig copyWith({
    String? xampPrefix,
    double? waveformGain,
    bool? stackedChannels,
    List<int>? visibleChannels,
    int? maxReconnectAttempts,
    int? eegDisplayDuration,
    String? eegSource,
    String? lslStreamType,
    String? lslStreamName,
    double? lslTimeout,
    bool? showSleepinessPreSession,
    bool? showSleepinessPostSession,
    bool? notchEnabled,
    bool? bandpassEnabled,
    String? eegDisplayMode,
  }) {
    return DeviceConfig(
      xampPrefix: xampPrefix ?? this.xampPrefix,
      waveformGain: waveformGain ?? this.waveformGain,
      stackedChannels: stackedChannels ?? this.stackedChannels,
      visibleChannels: visibleChannels ?? this.visibleChannels,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      eegDisplayDuration: eegDisplayDuration ?? this.eegDisplayDuration,
      eegSource: eegSource ?? this.eegSource,
      lslStreamType: lslStreamType ?? this.lslStreamType,
      lslStreamName: lslStreamName ?? this.lslStreamName,
      lslTimeout: lslTimeout ?? this.lslTimeout,
      showSleepinessPreSession: showSleepinessPreSession ?? this.showSleepinessPreSession,
      showSleepinessPostSession: showSleepinessPostSession ?? this.showSleepinessPostSession,
      notchEnabled: notchEnabled ?? this.notchEnabled,
      bandpassEnabled: bandpassEnabled ?? this.bandpassEnabled,
      eegDisplayMode: eegDisplayMode ?? this.eegDisplayMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'xampPrefix': xampPrefix,
        'waveformGain': waveformGain,
        'stackedChannels': stackedChannels,
        'visibleChannels': visibleChannels,
        'maxReconnectAttempts': maxReconnectAttempts,
        'eegDisplayDuration': eegDisplayDuration,
        'eegSource': eegSource,
        'lslStreamType': lslStreamType,
        'lslStreamName': lslStreamName,
        'lslTimeout': lslTimeout,
        'showSleepinessPreSession': showSleepinessPreSession,
        'showSleepinessPostSession': showSleepinessPostSession,
        'notchEnabled': notchEnabled,
        'bandpassEnabled': bandpassEnabled,
        'eegDisplayMode': eegDisplayMode,
      };

  factory DeviceConfig.fromJson(Map<String, dynamic> json) {
    final savedPrefix = (json['xampPrefix'] as String? ?? 'AXXSPU00003')
        .trim()
        .toUpperCase();
    return DeviceConfig(
      xampPrefix: savedPrefix == 'AXXSPU' ? 'AXXSPU00003' : savedPrefix,
      waveformGain: (json['waveformGain'] as num?)?.toDouble() ?? 1.0,
      stackedChannels: json['stackedChannels'] as bool? ?? true,
      visibleChannels: (json['visibleChannels'] as List?)?.map((e) => e as int).toList() ?? const [],
      maxReconnectAttempts: json['maxReconnectAttempts'] as int? ?? 10,
      eegDisplayDuration: json['eegDisplayDuration'] as int? ?? 10,
      eegSource: json['eegSource'] as String? ?? 'bluetooth',
      lslStreamType: json['lslStreamType'] as String? ?? 'EEG',
      lslStreamName: json['lslStreamName'] as String? ?? '',
      lslTimeout: (json['lslTimeout'] as num?)?.toDouble() ?? 5.0,
      showSleepinessPreSession: json['showSleepinessPreSession'] as bool? ?? false,
      showSleepinessPostSession: json['showSleepinessPostSession'] as bool? ?? false,
      notchEnabled: json['notchEnabled'] as bool? ?? true,
      bandpassEnabled: json['bandpassEnabled'] as bool? ?? false,
      eegDisplayMode: json['eegDisplayMode'] as String? ?? 'paradigm_only',
    );
  }
}

class DeviceConfigService {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/device_config.json');
  }

  static Future<DeviceConfig> load() async {
    try {
      final configFile = await _file();
      if (!await configFile.exists()) return const DeviceConfig();
      final json = jsonDecode(await configFile.readAsString());
      if (json is Map<String, dynamic>) {
        return DeviceConfig.fromJson(json);
      }
    } catch (error) {
      debugPrint('[DeviceConfig] load failed: $error');
    }
    return const DeviceConfig();
  }

  static Future<void> save(DeviceConfig config) async {
    try {
      final configFile = await _file();
      await configFile.writeAsString(jsonEncode(config.toJson()), flush: true);
    } catch (error) {
      debugPrint('[DeviceConfig] save failed: $error');
    }
  }
}
