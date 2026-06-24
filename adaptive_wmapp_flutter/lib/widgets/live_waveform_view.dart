import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/eeg_sample.dart';
import '../services/acquisition_service.dart';
import '../services/lsl_eeg_acquisition_service.dart';
import '../services/device_config_service.dart';
import '../services/channel_config_service.dart';
import '../services/display_filter.dart';
import 'waveform_painter.dart';

class LiveWaveformView extends StatefulWidget {
  final DeviceConfig deviceConfig;
  final ChannelConfig channelConfig;
  
  const LiveWaveformView({
    super.key,
    required this.deviceConfig,
    required this.channelConfig,
  });

  @override
  State<LiveWaveformView> createState() => _LiveWaveformViewState();
}

class _LiveWaveformViewState extends State<LiveWaveformView> {
  static const int _channelCount = 16;
  static const int _maxSamples = 1000;

  final List<List<double>> _channelBuffers = List.generate(
    _channelCount,
    (_) => <double>[],
  );
  
  List<DisplayFilter> _displayFilters = [];
  double _sampleRate = 250.0;
  
  StreamSubscription<EegSample>? _sampleSub;
  StreamSubscription<EegSample>? _lslSampleSub;

  @override
  void initState() {
    super.initState();
    _resetDisplayFilters();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final acq = context.read<AcquisitionService>();
      final lsl = context.read<LslEegAcquisitionService>();
      
      _sampleSub = acq.samples.listen(_onSample);
      _lslSampleSub = lsl.samples.listen(_onSample);
    });
  }

  @override
  void dispose() {
    _sampleSub?.cancel();
    _lslSampleSub?.cancel();
    super.dispose();
  }
  
  void _resetDisplayFilters() {
    _displayFilters = List.generate(
      _channelCount,
      (_) => DisplayFilter(_sampleRate),
    );
    for (final buffer in _channelBuffers) {
      buffer.clear();
    }
  }

  void _onSample(EegSample sample) {
    if (!mounted) return;
    if (sample.sampleRate != _sampleRate) {
      _sampleRate = sample.sampleRate;
      _resetDisplayFilters();
    }
    
    setState(() {
      for (var i = 0; i < _channelCount; i++) {
        var value = i < sample.channels.length ? sample.channels[i] : 0.0;
        
        if (i < _displayFilters.length) {
          value = _displayFilters[i].process(
            value,
            notchEnabled: widget.deviceConfig.notchEnabled,
            bandpassEnabled: widget.deviceConfig.bandpassEnabled,
          );
        }
        
        final buffer = _channelBuffers[i];
        buffer.add(value);
        if (buffer.length > _maxSamples) {
          buffer.removeRange(0, buffer.length - _maxSamples);
        }
      }
    });
  }

  List<String> _getEffectiveLabels(int count) {
    final c = count > 0 ? count : 16;
    if (widget.channelConfig.labels.length >= c) {
      return widget.channelConfig.labels.sublist(0, c);
    }
    return [
      ...widget.channelConfig.labels,
      ...List.generate(
        c - widget.channelConfig.labels.length,
        (i) => 'Ch ${widget.channelConfig.labels.length + i + 1}',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Determine which channels are visible based on DeviceConfig
    final visibleChannels = List.filled(_channelCount, false);
    for (var i = 0; i < _channelCount; i++) {
      if (widget.deviceConfig.visibleChannels.isEmpty || 
          widget.deviceConfig.visibleChannels.contains(i)) {
        visibleChannels[i] = true;
      }
    }
    
    final lsl = context.watch<LslEegAcquisitionService>();
    final acq = context.watch<AcquisitionService>();
    final isLsl = widget.deviceConfig.eegSource == 'lsl';
    final activeChannelCount = isLsl ? lsl.channelCount : acq.channelCount;

    return CustomPaint(
      painter: WaveformPainter(
        channels: _channelBuffers,
        visibleChannels: visibleChannels,
        stacked: widget.deviceConfig.stackedChannels,
        selectedChannel: 0, // Simplified for now
        gain: widget.deviceConfig.waveformGain,
        sampleRate: _sampleRate,
        durationSeconds: widget.deviceConfig.eegDisplayDuration,
        autoscale: widget.deviceConfig.autoscaleEnabled,
        channelLabels: _getEffectiveLabels(activeChannelCount),
      ),
      child: const SizedBox.expand(),
    );
  }
}
