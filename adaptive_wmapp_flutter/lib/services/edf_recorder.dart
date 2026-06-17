import 'dart:ffi';
import 'dart:io';

import 'dart:collection';
import 'package:path_provider/path_provider.dart';

import '../models/eeg_sample.dart';
import 'native_core.dart';

class EdfRecorder {
  Pointer<Void> _writer = nullptr;
  String? _path;
  int _channelCount = 2; // EEG + Marker
  int _sampleRate = 100;
  final Queue<int> _markerQueue = Queue<int>();

  bool get isRecording => _writer != nullptr;
  String? get path => _path;

  void setMarker(int markerCode) {
    _markerQueue.add(markerCode);
  }

  Future<String> start({
    required String subject,
    required int channelCount,
    required int sampleRate,
  }) async {
    await stop();
    // We add 1 channel at the end for Markers
    _channelCount = (channelCount + 1).clamp(2, 32);
    _sampleRate = sampleRate.clamp(50, 1000);
    _markerQueue.clear();
    
    Directory rootDir;
    if (Platform.isAndroid) {
      rootDir = Directory('/storage/emulated/0/ACDMT');
    } else {
      final dir = await getApplicationDocumentsDirectory();
      rootDir = Directory('${dir.path}/ACDMT');
    }
    
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    
    final cleanSubject = subject.trim().isEmpty
        ? 'unknown'
        : subject.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    
    _path = '${rootDir.path}/${cleanSubject}_$stamp.edf';
    _writer = NativeCore.instance.openEdf(
      path: _path!,
      subject: cleanSubject,
      channelCount: _channelCount,
      sampleRate: _sampleRate,
    );
    
    if (_writer == nullptr) {
      throw StateError('Could not open EDF file at $_path');
    }
    return _path!;
  }

  void push(EegSample sample) {
    if (_writer == nullptr) return;
    final values = List<double>.filled(_channelCount, 0.0);
    final eegChannels = _channelCount - 1;
    for (var i = 0; i < eegChannels; i++) {
      if (i < sample.channels.length) {
        values[i] = sample.channels[i];
      }
    }
    int markerToPush = 0;
    if (_markerQueue.isNotEmpty) {
      markerToPush = _markerQueue.removeFirst();
    }
    values[_channelCount - 1] = markerToPush.toDouble();
    NativeCore.instance.pushEdfSample(_writer, values);
  }

  Future<String?> stop() async {
    if (_writer == nullptr) return _path;
    final writer = _writer;
    _writer = nullptr;
    NativeCore.instance.closeEdf(writer);
    return _path;
  }
}
