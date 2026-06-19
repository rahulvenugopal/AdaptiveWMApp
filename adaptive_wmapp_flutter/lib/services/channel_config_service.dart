import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Default EEG electrode labels for the xAMP-L10 / EpiDome 16-ch headset.
const _xampL10Labels = [
  'Fp1', 'Fp2', 'F3', 'F4', 'C3', 'Cz', 'C4', 'P3',
  'Pz', 'P4', 'O1', 'Oz', 'O2', 'F7', 'F8', 'T3',
];

/// Default EEG electrode labels for the 2-ch Orbit headset.
const _orbitLabels = ['Fp1', 'Fp2'];

/// Holds a list of EEG channel labels used for EDF header metadata and UI.
class ChannelConfig {
  final List<String> labels;
  const ChannelConfig({required this.labels});

  Map<String, dynamic> toJson() => {'labels': labels};

  factory ChannelConfig.fromJson(Map<String, dynamic> j) =>
      ChannelConfig(labels: List<String>.from(j['labels'] as List));

  /// Returns device-appropriate default labels based on [source] string.
  /// Falls back to generic 'Ch N' labels for unknown device types.
  static ChannelConfig defaults(int channelCount, String source) {
    if (source.contains('EpiDome') || source.contains('xAMP')) {
      return ChannelConfig(
        labels: List.generate(
          channelCount,
          (i) => i < _xampL10Labels.length ? _xampL10Labels[i] : 'Ch ${i + 1}',
        ),
      );
    }
    if (source.contains('Orbit')) {
      return ChannelConfig(
        labels: List.generate(
          channelCount,
          (i) => i < _orbitLabels.length ? _orbitLabels[i] : 'Ch ${i + 1}',
        ),
      );
    }
    return ChannelConfig(
      labels: List.generate(channelCount, (i) => 'Ch ${i + 1}'),
    );
  }
}

/// Persists [ChannelConfig] to `channel_config.json` in the app support directory.
class ChannelConfigService {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/channel_config.json');
  }

  static Future<ChannelConfig> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const ChannelConfig(labels: []);
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return ChannelConfig.fromJson(json);
    } catch (_) {
      return const ChannelConfig(labels: []);
    }
  }

  static Future<void> save(ChannelConfig config) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(config.toJson()), flush: true);
  }
}
