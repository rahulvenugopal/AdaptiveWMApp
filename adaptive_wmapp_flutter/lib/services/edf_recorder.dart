import 'dart:ffi';
import 'dart:io';
import 'dart:collection';
import 'package:path_provider/path_provider.dart';

import '../models/eeg_sample.dart';
import 'native_core.dart';

/// Records EEG samples into EDF+ files via the native NativeCore FFI.
///
/// Supports:
/// - Dynamic channel counts (fixes the former hard-coded 2-channel bug)
/// - Custom per-channel EEG labels (calls [NativeCore.openEdfWithLabels])
/// - Multi-segment recording: segment 0 captures a session timestamp that all
///   subsequent segments reuse, so files sort together in the filesystem.
class EdfRecorder {
  Pointer<Void> _writer = nullptr;
  String? _path;
  int _channelCount = 2; // EEG channels + 1 Marker channel
  int _sampleRate = 100;
  List<String> _channelLabels = [];
  List<bool>? _enabledChannels;
  /// Shared timestamp captured at segment 0, reused for all subsequent segments.
  String? _sessionTimestamp;
  final Queue<int> _markerQueue = Queue<int>();

  bool get isRecording => _writer != nullptr;
  String? get path => _path;
  String? get sessionTimestamp => _sessionTimestamp;

  void setMarker(int markerCode) {
    _markerQueue.add(markerCode);
  }

  /// Returns the next segment index.  Call from SetupScreen on reconnect.
  int nextSegment() {
    // Caller holds _segmentIndex; this is a convenience helper.
    // The actual tracking lives in SetupScreen._edfSegmentIndex.
    return 0; // placeholder – real counting is done externally
  }

  /// Starts a new EDF recording.
  ///
  /// [channelCount]   – Number of EEG channels (a Marker channel is appended).
  /// [sampleRate]     – Sample rate in Hz.
  /// [channelLabels]  – Optional list of electrode label strings.  When supplied,
  ///                    [NativeCore.openEdfWithLabels] is used; otherwise the
  ///                    simpler [NativeCore.openEdf] is used.
  /// [enabledChannels]– List of booleans indicating which channels are enabled.
  /// [segment]        – 0 for a fresh session (captures timestamp), >0 to append
  ///                    a new segment file with the same session timestamp.
  Future<String> start({
    required String subject,
    required int channelCount,
    required int sampleRate,
    List<String>? channelLabels,
    List<bool>? enabledChannels,
    int segment = 0,
  }) async {
    await stop();

    // We always append a dedicated Marker channel.
    _channelCount = (channelCount + 1).clamp(2, 33);
    _sampleRate = sampleRate.clamp(50, 1000);
    _channelLabels = channelLabels ?? [];
    _enabledChannels = enabledChannels;
    _markerQueue.clear();

    // ── Resolve output directory ───────────────────────────────────────────
    final dir = await getApplicationDocumentsDirectory();
    final rootDir = Directory('${dir.path}/data');
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }

    // ── Build filename ─────────────────────────────────────────────────────
    final cleanSubject = subject.trim().isEmpty
        ? 'unknown'
        : subject.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

    // Capture or reuse session timestamp.
    if (segment == 0 || _sessionTimestamp == null) {
      _sessionTimestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
    }

    final segmentSuffix = segment > 0 ? '_part$segment' : '';
    _path = '${rootDir.path}/${cleanSubject}_$_sessionTimestamp$segmentSuffix.edf';

    // ── Open EDF file ──────────────────────────────────────────────────────
    final eegChannelCount = _channelCount - 1; // channels excluding Marker

    if (_channelLabels.isNotEmpty) {
      // Build per-channel metadata arrays.
      final labels = List<String>.generate(eegChannelCount, (i) {
        if (i < _channelLabels.length) return _channelLabels[i];
        return 'Ch ${i + 1}';
      })..add('Marker'); // Marker always last

      final physDims = List<String>.generate(
          eegChannelCount, (_) => 'uV')
        ..add('code');

      final prefilters = List<String>.filled(_channelCount, 'None');

      final transducers = List<String>.generate(
          eegChannelCount, (_) => 'EEG electrode')
        ..add('Event marker');

      _writer = NativeCore.instance.openEdfWithLabels(
        path: _path!,
        subject: cleanSubject,
        channelNames: labels,
        physicalDims: physDims,
        prefilters: prefilters,
        transducers: transducers,
        sampleRate: _sampleRate,
      );
    } else {
      // Fallback: no label information available.
      _writer = NativeCore.instance.openEdf(
        path: _path!,
        subject: cleanSubject,
        channelCount: _channelCount,
        sampleRate: _sampleRate,
      );
    }

    if (_writer == nullptr) {
      throw StateError('Could not open EDF file at $_path');
    }
    return _path!;
  }

  /// Writes one [EegSample] to the open EDF file.
  void push(EegSample sample) {
    if (_writer == nullptr) return;
    final values = List<double>.filled(_channelCount, 0.0);
    int writeIdx = 0;
    
    for (var i = 0; i < sample.channels.length; i++) {
      final isEnabled = _enabledChannels == null ||
          i >= _enabledChannels!.length ||
          _enabledChannels![i];
      if (isEnabled && writeIdx < _channelCount - 1) {
        values[writeIdx++] = sample.channels[i];
      }
    }
    
    int markerToPush = 0;
    if (_markerQueue.isNotEmpty) {
      markerToPush = _markerQueue.removeFirst();
    }
    values[_channelCount - 1] = markerToPush.toDouble();
    NativeCore.instance.pushEdfSample(_writer, values);
  }

  /// Closes and finalises the current EDF file.  Returns the file path.
  Future<String?> stop() async {
    if (_writer == nullptr) return _path;
    final writer = _writer;
    _writer = nullptr;
    NativeCore.instance.closeEdf(writer);
    return _path;
  }
}
