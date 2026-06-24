import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/eeg_sample.dart';
import '../models/lsl_config.dart';
import '../services/acquisition_service.dart';
import '../services/lsl_eeg_acquisition_service.dart';
import '../services/device_config_service.dart';
import '../services/channel_config_service.dart';
import '../services/permission_service.dart';
import '../services/edf_recorder.dart';
import '../services/config_sharing_service.dart';
import '../services/display_filter.dart';
import '../widgets/stanford_sleepiness_scale.dart';
import '../widgets/waveform_painter.dart';
import 'config_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const int _channelCount = 16;
  static const int _maxSamples = 1000;

  final _subjectController = TextEditingController(text: 'Subj001');
  final _xampPrefixController = TextEditingController(text: 'AXXSPU00003');
  final List<List<double>> _channelBuffers = List.generate(
    _channelCount,
    (_) => <double>[],
  );
  final List<bool> _visibleChannels = List.filled(_channelCount, true);
  StreamSubscription<EegSample>? _sampleSub;
  StreamSubscription<EegSample>? _lslSampleSub;
  StreamSubscription<AcquisitionState>? _stateSub;
  StreamSubscription<AcquisitionState>? _lslStateSub;
  Timer? _elapsedTimer;
  int _selectedChannel = 0;
  bool _stackedChannels = true;
  double _gain = 1.0;
  double _baseGain = 1.0;
  int _elapsedSeconds = 0;
  bool _activityRunning = false;
  EegDevice? _selectedDevice;
  DeviceKind _selectedDeviceKind = DeviceKind.epidome;

  // Added state variables
  String _eegSource = 'bluetooth'; // 'bluetooth', 'lsl', 'synthetic'
  LslConfig _lslConfig = const LslConfig();
  ChannelConfig _channelConfig = const ChannelConfig(labels: []);
  int _maxReconnectAttempts = 10;
  int _eegDisplayDuration = 10;
  bool _showSleepinessPreSession = false;
  bool _showSleepinessPostSession = false;
  bool _notchEnabled = true;
  bool _bandpassEnabled = false;
  bool _autoscaleEnabled = false;
  String _eegDisplayMode = 'paradigm_only';
  List<DisplayFilter> _displayFilters = [];
  double _sampleRate = 250.0;
  StreamSubscription<void>? _btMaxRetriesSub;
  StreamSubscription<void>? _lslMaxRetriesSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final acq = context.read<AcquisitionService>();
      final lsl = context.read<LslEegAcquisitionService>();
      PermissionService.ensurePermissionsOnFirstLaunch(context);

      DeviceConfigService.load()
          .then((config) {
            if (!mounted) return;
            setState(() {
              _maxReconnectAttempts = config.maxReconnectAttempts;
              _eegDisplayDuration = config.eegDisplayDuration;
              _eegSource = config.eegSource;
              _gain = config.waveformGain;
              _stackedChannels = config.stackedChannels;
              _showSleepinessPreSession = config.showSleepinessPreSession;
              _showSleepinessPostSession = config.showSleepinessPostSession;
              _notchEnabled = config.notchEnabled;
              _bandpassEnabled = config.bandpassEnabled;
              _autoscaleEnabled = config.autoscaleEnabled;
              _eegDisplayMode = config.eegDisplayMode;
              _lslConfig = LslConfig(
                eegStreamType: config.lslStreamType,
                eegStreamName: config.lslStreamName,
                resolveTimeoutSeconds: config.lslTimeout,
              );
              _resetDisplayFilters();
            });

            final prefix = config.xampPrefix.trim().isEmpty
                ? 'AXXSPU00003'
                : config.xampPrefix.trim().toUpperCase();
            _xampPrefixController.text = prefix;
            acq.xampPrefix = prefix;

            acq.reconnectMaxAttempts = _maxReconnectAttempts;
            lsl.reconnectMaxAttempts = _maxReconnectAttempts;

            if (config.visibleChannels.isNotEmpty) {
              for (var i = 0; i < _visibleChannels.length; i++) {
                _visibleChannels[i] = config.visibleChannels.contains(i);
              }
            }
          })
          .then((_) {
            acq.addSyntheticDevice();
            acq.scan();
          });

      _btMaxRetriesSub = acq.maxRetriesReached.listen((_) {
        if (mounted) _showMaxRetriesDialog(acq, lsl);
      });
      _lslMaxRetriesSub = lsl.maxRetriesReached.listen((_) {
        if (mounted) _showMaxRetriesDialog(acq, lsl);
      });
    });

    final acq = context.read<AcquisitionService>();
    final lsl = context.read<LslEegAcquisitionService>();
    _sampleSub = acq.samples.listen(_onSample);
    _lslSampleSub = lsl.samples.listen(_onSample);

    _stateSub = acq.state.listen((state) {
      if (_eegSource != 'lsl') {
        if (mounted) setState(() {});
      }
    });

    _lslStateSub = lsl.state.listen((state) {
      if (_eegSource == 'lsl') {
        if (mounted) setState(() {});
      }
    });

    ChannelConfigService.load().then((c) {
      if (mounted) {
        setState(() {
          _channelConfig = c;
          for (var i = 0; i < _visibleChannels.length; i++) {
            _visibleChannels[i] = c.isChannelEnabled(i);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sampleSub?.cancel();
    _lslSampleSub?.cancel();
    _stateSub?.cancel();
    _lslStateSub?.cancel();
    _btMaxRetriesSub?.cancel();
    _lslMaxRetriesSub?.cancel();
    _elapsedTimer?.cancel();
    _subjectController.dispose();
    _xampPrefixController.dispose();
    super.dispose();
  }

  void _showMaxRetriesDialog(
    AcquisitionService acq,
    LslEegAcquisitionService lsl,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Connection Lost'),
        content: Text(
          'Could not reconnect to the EEG device after $_maxReconnectAttempts attempts.\n'
          'Please check that the device is powered on and in range.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (_eegSource == 'lsl') {
                lsl.connect(_lslConfig);
              } else {
                acq.scan();
              }
            },
            child: const Text('Keep Trying'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (_eegSource == 'lsl') {
                lsl.disconnect();
              } else {
                acq.disconnect();
              }
            },
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  void _updateElapsedTimer(bool active) {
    if (active) {
      if (_elapsedTimer == null) {
        _elapsedSeconds = 0;
        _activityRunning = true;
        _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() => _elapsedSeconds++);
          }
        });
      }
    } else {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      _elapsedSeconds = 0;
      _activityRunning = false;
    }
  }

  String _formatElapsedTime(int totalSeconds) {
    final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSeconds ~/ 60) % 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
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
            notchEnabled: _notchEnabled,
            bandpassEnabled: _bandpassEnabled,
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

  void _resetDisplayFilters() {
    _displayFilters = List.generate(
      _channelCount,
      (_) => DisplayFilter(_sampleRate),
    );
    for (final buffer in _channelBuffers) {
      buffer.clear();
    }
  }

  void _saveCurrentConfig() {
    final prefix = _xampPrefixController.text.trim().isEmpty
        ? 'AXXSPU00003'
        : _xampPrefixController.text.trim().toUpperCase();

    final config = DeviceConfig(
      xampPrefix: prefix,
      waveformGain: _gain,
      stackedChannels: _stackedChannels,
      visibleChannels: _visibleChannels
          .asMap()
          .entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList(),
      maxReconnectAttempts: _maxReconnectAttempts,
      eegDisplayDuration: _eegDisplayDuration,
      eegSource: _eegSource,
      lslStreamType: _lslConfig.eegStreamType,
      lslStreamName: _lslConfig.eegStreamName,
      lslTimeout: _lslConfig.resolveTimeoutSeconds,
      showSleepinessPreSession: _showSleepinessPreSession,
      showSleepinessPostSession: _showSleepinessPostSession,
      notchEnabled: _notchEnabled,
      bandpassEnabled: _bandpassEnabled,
      autoscaleEnabled: _autoscaleEnabled,
      eegDisplayMode: _eegDisplayMode,
    );
    DeviceConfigService.save(config);
  }

  void _saveXampPrefix(String value) {
    final prefix = value.trim().isEmpty
        ? 'AXXSPU00003'
        : value.trim().toUpperCase();
    final acq = context.read<AcquisitionService>();
    acq.xampPrefix = prefix;
    _saveCurrentConfig();
  }

  List<String> _getEffectiveLabels(int count) {
    final c = count > 0 ? count : 16;
    if (_channelConfig.labels.length >= c) {
      return _channelConfig.labels.sublist(0, c);
    }
    return [
      ..._channelConfig.labels,
      ...List.generate(
        c - _channelConfig.labels.length,
        (i) => 'Ch ${_channelConfig.labels.length + i + 1}',
      ),
    ];
  }

  void _startExperiment() async {
    if (_subjectController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a subject ID')),
      );
      return;
    }

    if (_showSleepinessPreSession) {
      if (!mounted) return;
      await StanfordSleepinessScaleDialog.show(
        context,
        'AdaptiveWMApp',
        _subjectController.text,
        'pre-session',
      );
    }

    final edf = context.read<EdfRecorder>();
    final acq = context.read<AcquisitionService>();
    final lsl = context.read<LslEegAcquisitionService>();

    final isLsl = _eegSource == 'lsl';
    final activeChannelCount = isLsl ? lsl.channelCount : acq.channelCount;
    final activeSampleRate = isLsl ? lsl.sampleRate : acq.sampleRate;
    final labels = _getEffectiveLabels(activeChannelCount);

    try {
      if (_eegSource != 'none') {
        final channelCountVal = activeChannelCount > 0 ? activeChannelCount : 16;
        final enabledList = List<bool>.generate(channelCountVal, (i) => _channelConfig.isChannelEnabled(i));
        final filteredLabels = <String>[];
        for (var i = 0; i < channelCountVal; i++) {
          if (enabledList[i]) {
            filteredLabels.add(labels[i]);
          }
        }
        await edf.start(
          subject: _subjectController.text,
          channelCount: filteredLabels.length,
          sampleRate: activeSampleRate > 0 ? activeSampleRate.round() : 250,
          channelLabels: filteredLabels,
          enabledChannels: enabledList,
          segment: 0,
        );
      }
      _updateElapsedTimer(true);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ConfigScreen(
            subjectId: _subjectController.text,
            showSleepinessPostSession: _showSleepinessPostSession,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error starting EDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final acq = context.watch<AcquisitionService>();
    final lsl = context.watch<LslEegAcquisitionService>();
    final isStreaming = _eegSource == 'lsl'
        ? lsl.currentState == AcquisitionState.streaming
        : acq.currentState == AcquisitionState.streaming;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F19),
        appBar: AppBar(
          title: const Text('ACDMT'),
          backgroundColor: const Color(0xFF111827),
          actions: [
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Settings',
                onPressed: () => DefaultTabController.of(context).animateTo(3),
                icon: const Icon(Icons.settings),
              ),
            ),
            if (_eegSource != 'lsl')
              TextButton.icon(
                onPressed: acq.currentState == AcquisitionState.scanning
                    ? null
                    : () => acq.scan(),
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Scan'),
              ),
            IconButton(
              tooltip: 'Exit App',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Exit App'),
                  content: const Text('Are you sure you want to close ACDMT?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        SystemNavigator.pop();
                      },
                      child: const Text('Exit', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF14B8A6),
            labelColor: Color(0xFF14B8A6),
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(icon: Icon(Icons.bluetooth), text: 'Connection'),
              Tab(icon: Icon(Icons.show_chart), text: 'EEG Waveform'),
              Tab(icon: Icon(Icons.play_circle_outline), text: 'Protocol'),
              Tab(icon: Icon(Icons.settings), text: 'Settings'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildGlobalHeader(isStreaming),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildConnectionTab(acq),
                    _buildWaveformTab(acq),
                    _buildProtocolTab(acq),
                    _buildSettingsTab(acq),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlobalHeader(bool isStreaming) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF0F172A),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isStreaming
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isStreaming ? 'STREAMING' : 'DISCONNECTED',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _activityRunning ? 'RECORDING' : 'ACTIVITY IDLE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _activityRunning
                        ? const Color(0xFFF87171)
                        : Colors.grey[500],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _activityRunning
                      ? _formatElapsedTime(_elapsedSeconds)
                      : '00:00',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: Color(0xFF60A5FA),
                  ),
                ),
                const Text(
                  'ACTIVITY ELAPSED',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const Spacer(),
            IconButton.filledTonal(
              tooltip: isStreaming ? 'Stop' : 'Disconnected',
              onPressed: isStreaming ? _stopActiveConnection : null,
              icon: Icon(isStreaming ? Icons.stop : Icons.link_off),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _stopActiveConnection() async {
    if (_eegSource == 'lsl') {
      await context.read<LslEegAcquisitionService>().disconnect();
    } else {
      await context.read<AcquisitionService>().disconnect();
    }
  }

  Widget _buildConnectionTab(AcquisitionService acq) {
    final lsl = context.watch<LslEegAcquisitionService>();
    final isStreaming = _eegSource == 'lsl'
        ? lsl.currentState == AcquisitionState.streaming
        : acq.currentState == AcquisitionState.streaming;

    return StreamBuilder<List<EegDevice>>(
      stream: acq.devices,
      initialData: const [],
      builder: (context, snapshot) {
        final devices = (snapshot.data ?? const <EegDevice>[])
            .where((device) {
              final name = device.name.trim().toUpperCase();
              if (_selectedDeviceKind == DeviceKind.orbit) {
                return device.kind == DeviceKind.orbit &&
                    name.startsWith(acq.orbitPrefix.toUpperCase());
              }
              return device.kind == DeviceKind.epidome &&
                  device.isBle &&
                  name.startsWith(acq.xampPrefix.toUpperCase());
            })
            .toList(growable: false);
        if (_selectedDevice != null && !devices.contains(_selectedDevice)) {
          _selectedDevice = null;
        }
        _selectedDevice ??= devices.isEmpty ? null : devices.first;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'bluetooth',
                                icon: Icon(Icons.bluetooth),
                                label: Text('Bluetooth'),
                              ),
                              ButtonSegment(
                                value: 'lsl',
                                icon: Icon(Icons.wifi),
                                label: Text('LSL'),
                              ),
                              ButtonSegment(
                                value: 'synthetic',
                                icon: Icon(Icons.settings_suggest),
                                label: Text('Synthetic'),
                              ),
                              ButtonSegment(
                                value: 'none',
                                icon: Icon(Icons.videogame_asset_off),
                                label: Text('Paradigm Only'),
                              ),
                            ],
                            selected: {_eegSource},
                            onSelectionChanged: (selection) {
                              setState(() => _eegSource = selection.first);
                              _saveCurrentConfig();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 132,
                          child: TextField(
                            controller: _subjectController,
                            decoration: const InputDecoration(
                              labelText: 'Participant ID',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_eegSource == 'bluetooth') ...[
                      SegmentedButton<DeviceKind>(
                        segments: const [
                          ButtonSegment(
                            value: DeviceKind.epidome,
                            label: Text('xAMP-L10'),
                          ),
                          ButtonSegment(
                            value: DeviceKind.orbit,
                            label: Text('Orbit'),
                          ),
                        ],
                        selected: {_selectedDeviceKind},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _selectedDeviceKind = selection.first;
                            _selectedDevice = null;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_eegSource == 'bluetooth')
                      DropdownButtonFormField<EegDevice>(
                        initialValue: _selectedDevice,
                        decoration: const InputDecoration(
                          labelText: 'Device unit',
                          border: OutlineInputBorder(),
                        ),
                        items: devices
                            .map(
                              (device) => DropdownMenuItem(
                                value: device,
                                child: Text(
                                  '${device.name} (${device.isBle ? 'BLE' : 'Classic'})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (device) =>
                            setState(() => _selectedDevice = device),
                      )
                    else if (_eegSource == 'lsl')
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'LSL EEG stream',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _lslConfig.eegStreamName.isEmpty
                              ? 'Any EEG stream'
                              : _lslConfig.eegStreamName,
                        ),
                      )
                    else if (_eegSource == 'synthetic')
                      const InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Device unit',
                          border: OutlineInputBorder(),
                        ),
                        child: Text('Synthetic EEG generator'),
                      )
                    else
                      const InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Device unit',
                          border: OutlineInputBorder(),
                        ),
                        child: Text('No EEG recording (Behavioral Only)'),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_eegSource == 'bluetooth')
                          FilledButton.icon(
                            onPressed:
                                acq.currentState == AcquisitionState.scanning
                                ? null
                                : acq.scan,
                            icon: const Icon(Icons.radar),
                            label: Text(
                              acq.currentState == AcquisitionState.scanning
                                  ? 'Scanning'
                                  : 'Scan',
                            ),
                          ),
                        if (_eegSource == 'bluetooth') const SizedBox(width: 8),
                        if (_eegSource != 'none')
                          FilledButton.tonalIcon(
                            onPressed: isStreaming
                                ? _stopActiveConnection
                                : () async {
                                  if (_eegSource == 'lsl') {
                                    await lsl.connect(_lslConfig);
                                  } else if (_eegSource == 'synthetic') {
                                    await acq.connect(
                                      const EegDevice(
                                        name: 'Synthetic frontal EEG',
                                        id: 'synthetic',
                                        kind: DeviceKind.synthetic,
                                        isBle: false,
                                      ),
                                    );
                                  } else if (_selectedDevice != null) {
                                    await acq.connect(_selectedDevice!);
                                  }
                                },
                          icon: Icon(
                            isStreaming ? Icons.stop : Icons.play_arrow,
                          ),
                          label: Text(isStreaming ? 'Stop' : 'Stream'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildLegacyConnectionTab(AcquisitionService acq) {
    final lsl = context.watch<LslEegAcquisitionService>();
    final isStreaming = _eegSource == 'lsl'
        ? lsl.currentState == AcquisitionState.streaming
        : acq.currentState == AcquisitionState.streaming;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _subjectController,
            decoration: const InputDecoration(
              labelText: 'Subject ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Bluetooth'),
                selected: _eegSource == 'bluetooth',
                onSelected: (val) {
                  if (val) {
                    setState(() => _eegSource = 'bluetooth');
                    _saveCurrentConfig();
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('LSL'),
                selected: _eegSource == 'lsl',
                onSelected: (val) {
                  if (val) {
                    setState(() => _eegSource = 'lsl');
                    _saveCurrentConfig();
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Synthetic'),
                selected: _eegSource == 'synthetic',
                onSelected: (val) {
                  if (val) {
                    setState(() => _eegSource = 'synthetic');
                    _saveCurrentConfig();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_eegSource == 'bluetooth') ...[
            TextField(
              controller: _xampPrefixController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'xAMP-L10 Auto-connect Prefix',
                border: OutlineInputBorder(),
              ),
              onChanged: _saveXampPrefix,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => acq.scan(),
                  icon: const Icon(Icons.search),
                  label: const Text('Scan Devices'),
                ),
                const SizedBox(width: 8),
                if (acq.currentState == AcquisitionState.scanning)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<EegDevice>>(
                stream: acq.devices,
                initialData: const [],
                builder: (context, snapshot) {
                  final devices = snapshot.data ?? [];
                  final btDevices = devices
                      .where((d) => d.kind != DeviceKind.synthetic)
                      .toList();
                  if (btDevices.isEmpty) {
                    return const Center(child: Text('No devices found'));
                  }
                  return ListView.builder(
                    itemCount: btDevices.length,
                    itemBuilder: (context, index) {
                      final device = btDevices[index];
                      return ListTile(
                        title: Text(device.name),
                        subtitle: Text(device.id),
                        trailing: ElevatedButton(
                          onPressed: () => acq.connect(device),
                          child: const Text('Connect'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ] else if (_eegSource == 'lsl') ...[
            Text(
              'LSL STREAM SETTINGS',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _lslConfig.eegStreamType,
              decoration: const InputDecoration(
                labelText: 'EEG Stream Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) {
                setState(() {
                  _lslConfig = _lslConfig.copyWith(eegStreamType: val.trim());
                });
                _saveCurrentConfig();
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _lslConfig.eegStreamName,
              decoration: const InputDecoration(
                labelText: 'EEG Stream Name Filter',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) {
                setState(() {
                  _lslConfig = _lslConfig.copyWith(eegStreamName: val.trim());
                });
                _saveCurrentConfig();
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => lsl.connect(_lslConfig),
              child: Text(
                lsl.currentState == AcquisitionState.streaming
                    ? 'Disconnect LSL'
                    : 'Connect LSL',
              ),
            ),
            const SizedBox(height: 16),
            if (lsl.currentState == AcquisitionState.streaming) ...[
              Text(
                'Connected to: ${lsl.channelCount}ch @ ${lsl.sampleRate.toStringAsFixed(0)}Hz',
                style: const TextStyle(color: Colors.tealAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            const Spacer(),
          ] else if (_eegSource == 'synthetic') ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Synthetic EEG generator simulates standard brain waves at 250Hz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                const syntheticDevice = EegDevice(
                  name: 'Synthetic Device',
                  id: 'synthetic',
                  kind: DeviceKind.synthetic,
                  isBle: false,
                );
                acq.connect(syntheticDevice);
              },
              child: Text(
                acq.currentState == AcquisitionState.streaming &&
                        acq.connectedDeviceName == 'Synthetic Device'
                    ? 'Disconnect Synthetic'
                    : 'Connect Synthetic',
              ),
            ),
            const Spacer(),
          ],
          const SizedBox(height: 16),
          Text(
            'Status: ${isStreaming ? 'Streaming' : (_eegSource == 'lsl' ? lsl.currentState.name : acq.currentState.name)}',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformTab(AcquisitionService acq) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: _buildSignalPreview(context, acq, height: null),
    );
  }

  Widget _buildProtocolTab(AcquisitionService acq) {
    final lsl = context.watch<LslEegAcquisitionService>();
    final isStreaming = _eegSource == 'lsl'
        ? lsl.currentState == AcquisitionState.streaming
        : acq.currentState == AcquisitionState.streaming;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Status: ${isStreaming ? 'Streaming' : (_eegSource == 'lsl' ? lsl.currentState.name : acq.currentState.name)}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: isStreaming ? _startExperiment : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Start Experiment'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(AcquisitionService acq) {
    final lsl = context.watch<LslEegAcquisitionService>();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // IMPORT / EXPORT CONFIGURATION
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'IMPORT / EXPORT CONFIGURATION',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Import Config'),
                        onPressed: () async {
                          final config = await ConfigSharingService.importConfig(context);
                          if (config != null) {
                            try {
                              final imported = DeviceConfig.fromJson(config);
                              setState(() {
                                _xampPrefixController.text = imported.xampPrefix;
                                _maxReconnectAttempts = imported.maxReconnectAttempts;
                                _stackedChannels = imported.stackedChannels;
                                _gain = imported.waveformGain;
                                _showSleepinessPreSession = imported.showSleepinessPreSession;
                                _showSleepinessPostSession = imported.showSleepinessPostSession;
                                _notchEnabled = imported.notchEnabled;
                                _bandpassEnabled = imported.bandpassEnabled;
                                _eegDisplayMode = imported.eegDisplayMode;
                                acq.reconnectMaxAttempts = _maxReconnectAttempts;
                                lsl.reconnectMaxAttempts = _maxReconnectAttempts;
                                _resetDisplayFilters();
                              });
                              _saveCurrentConfig();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Configuration imported successfully')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Invalid configuration format: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.upload),
                        label: const Text('Export Config'),
                        onPressed: () {
                          // Force a save to ensure config is up to date before exporting
                          _saveCurrentConfig();
                          // Construct the config manually to be safe, or just call toJson on DeviceConfig
                          final prefix = _xampPrefixController.text.trim().isEmpty ? 'AXXSPU00003' : _xampPrefixController.text.trim().toUpperCase();
                          final config = DeviceConfig(
                            xampPrefix: prefix,
                            waveformGain: _gain,
                            stackedChannels: _stackedChannels,
                            visibleChannels: _visibleChannels.asMap().entries.where((e) => e.value).map((e) => e.key).toList(),
                            maxReconnectAttempts: _maxReconnectAttempts,
                            eegDisplayDuration: _eegDisplayDuration,
                            eegSource: _eegSource,
                            lslStreamType: _lslConfig.eegStreamType,
                            lslStreamName: _lslConfig.eegStreamName,
                            lslTimeout: _lslConfig.resolveTimeoutSeconds,
                            showSleepinessPreSession: _showSleepinessPreSession,
                            showSleepinessPostSession: _showSleepinessPostSession,
                            notchEnabled: _notchEnabled,
                            bandpassEnabled: _bandpassEnabled,
                            eegDisplayMode: _eegDisplayMode,
                          );
                          ConfigSharingService.exportConfig(context, 'AdaptiveWMApp', config.toJson());
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // DEVICE CONFIGURATION
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'DEVICE CONFIGURATION',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _xampPrefixController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'xAMP-L10 Auto-connect Prefix',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _saveXampPrefix,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _maxReconnectAttempts,
                  dropdownColor: const Color(0xFF1E293B),
                  decoration: const InputDecoration(
                    labelText: 'Max Reconnect Attempts',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5 attempts')),
                    DropdownMenuItem(value: 10, child: Text('10 attempts')),
                    DropdownMenuItem(value: 15, child: Text('15 attempts')),
                    DropdownMenuItem(value: 20, child: Text('20 attempts')),
                    DropdownMenuItem(value: 0, child: Text('Unlimited')),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _maxReconnectAttempts = val ?? 10;
                      acq.reconnectMaxAttempts = _maxReconnectAttempts;
                      lsl.reconnectMaxAttempts = _maxReconnectAttempts;
                    });
                    _saveCurrentConfig();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // EEG WAVEFORM DISPLAY
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'EEG WAVEFORM DISPLAY',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Stacked EEG Channels'),
                  value: _stackedChannels,
                  onChanged: (value) {
                    setState(() => _stackedChannels = value);
                    _saveCurrentConfig();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoscale Waveform'),
                  value: _autoscaleEnabled,
                  onChanged: (value) {
                    setState(() => _autoscaleEnabled = value);
                    _saveCurrentConfig();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('50Hz Notch Filter'),
                  value: _notchEnabled,
                  onChanged: (value) {
                    setState(() => _notchEnabled = value);
                    _saveCurrentConfig();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('1-30Hz Bandpass Filter'),
                  value: _bandpassEnabled,
                  onChanged: (value) {
                    setState(() => _bandpassEnabled = value);
                    _saveCurrentConfig();
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _eegDisplayMode,
                  dropdownColor: const Color(0xFF1E293B),
                  decoration: const InputDecoration(
                    labelText: 'Experiment Display Mode',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'paradigm_only', child: Text('Paradigm Only')),
                    DropdownMenuItem(value: 'eeg_and_paradigm', child: Text('EEG + Paradigm (Background Recording)')),
                  ],
                  onChanged: (val) {
                    setState(() => _eegDisplayMode = val ?? 'paradigm_only');
                    _saveCurrentConfig();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // ASSESSMENT SETTINGS
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ASSESSMENT SETTINGS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show Sleepiness Scale (Pre-Session)'),
                  value: _showSleepinessPreSession,
                  onChanged: (value) {
                    setState(() => _showSleepinessPreSession = value);
                    _saveCurrentConfig();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show Sleepiness Scale (Post-Session)'),
                  value: _showSleepinessPostSession,
                  onChanged: (value) {
                    setState(() => _showSleepinessPostSession = value);
                    _saveCurrentConfig();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // LSL CONFIGURATION
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'LSL STREAM SETTINGS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _lslConfig.eegStreamType,
                  decoration: const InputDecoration(
                    labelText: 'EEG Stream Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _lslConfig = _lslConfig.copyWith(
                        eegStreamType: val.trim(),
                      );
                    });
                    _saveCurrentConfig();
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _lslConfig.eegStreamName,
                  decoration: const InputDecoration(
                    labelText: 'EEG Stream Name Filter',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _lslConfig = _lslConfig.copyWith(
                        eegStreamName: val.trim(),
                      );
                    });
                    _saveCurrentConfig();
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _lslConfig.resolveTimeoutSeconds.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Resolve Timeout (seconds)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (val) {
                    setState(() {
                      final parsed = double.tryParse(val) ?? 5.0;
                      _lslConfig = _lslConfig.copyWith(
                        resolveTimeoutSeconds: parsed,
                      );
                    });
                    _saveCurrentConfig();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // CHANNEL LABELS
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'CHANNEL LABELS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3B82F6),
                        fontSize: 12,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final def = ChannelConfig.defaults(16, 'xAMP');
                        setState(() {
                          _channelConfig = def;
                        });
                        await ChannelConfigService.save(def);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Labels reset to defaults.'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text(
                        'Reset Defaults',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Edit a label, then press Done to save it.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 2.8,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: List.generate(16, (i) {
                    final currentLabel = _channelConfig.labels.length > i
                        ? _channelConfig.labels[i]
                        : 'Ch ${i + 1}';
                    final isEnabled = _channelConfig.isChannelEnabled(i);
                    return Row(
                      children: [
                        Checkbox(
                          value: isEnabled,
                          onChanged: (val) async {
                            final labels = List<String>.from(_channelConfig.labels);
                            while (labels.length <= i) {
                              labels.add('Ch ${labels.length + 1}');
                            }
                            final enabled = List<bool>.from(_channelConfig.enabled);
                            while (enabled.length <= i) {
                              enabled.add(true);
                            }
                            enabled[i] = val ?? true;
                            final newConfig = ChannelConfig(labels: labels, enabled: enabled);
                            setState(() {
                              _channelConfig = newConfig;
                            });
                            await ChannelConfigService.save(newConfig);
                          },
                        ),
                        Expanded(
                          child: TextFormField(
                            initialValue: currentLabel,
                            key: ValueKey('ch_${i}_$currentLabel'),
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Channel ${i + 1}',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (val) async {
                              final labels = List<String>.from(_channelConfig.labels);
                              while (labels.length <= i) {
                                  labels.add('Ch ${labels.length + 1}');
                              }
                              labels[i] = val.trim();
                              final enabled = List<bool>.from(_channelConfig.enabled);
                              while (enabled.length <= i) {
                                  enabled.add(true);
                              }
                              final newConfig = ChannelConfig(labels: labels, enabled: enabled);
                              setState(() {
                                _channelConfig = newConfig;
                              });
                              await ChannelConfigService.save(newConfig);
                            },
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignalPreview(
    BuildContext context,
    AcquisitionService acq, {
    double? height = 300,
  }) {
    final lsl = context.watch<LslEegAcquisitionService>();
    final isStreaming = _eegSource == 'lsl'
        ? lsl.currentState == AcquisitionState.streaming
        : acq.currentState == AcquisitionState.streaming;

    final hasData = _channelBuffers.any((channel) => channel.isNotEmpty);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Icon(
                  isStreaming ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: isStreaming ? Colors.tealAccent : Colors.white54,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isStreaming
                        ? 'EEG stream preview'
                        : 'Connect a headset to preview EEG',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: _stackedChannels
                      ? 'Single channel'
                      : 'Stacked channels',
                  onPressed: () {
                    setState(() => _stackedChannels = !_stackedChannels);
                    _saveCurrentConfig();
                  },
                  icon: Icon(
                    _stackedChannels ? Icons.view_stream : Icons.show_chart,
                  ),
                ),
                if (!_stackedChannels)
                  DropdownButton<int>(
                    value: _selectedChannel,
                    items: List.generate(
                      _channelCount,
                      (index) => DropdownMenuItem(
                        value: index,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSignalQualityDot(index),
                            const SizedBox(width: 6),
                            Text(_getEffectiveLabels(_channelCount)[index]),
                          ],
                        ),
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _selectedChannel = value ?? 0),
                  ),
              ],
            ),
          ),
          if (_stackedChannels)
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemBuilder: (context, index) => FilterChip(
                  label: Text(_getEffectiveLabels(_channelCount)[index]),
                  selected: _visibleChannels[index],
                  avatar: _buildSignalQualityDot(index),
                  onSelected: (selected) =>
                      setState(() => _visibleChannels[index] = selected),
                ),
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemCount: _channelCount,
              ),
            ),
          Expanded(
            child: GestureDetector(
              onScaleStart: (_) => _baseGain = _gain,
              onScaleUpdate: (details) {
                setState(
                  () => _gain = (_baseGain * details.scale).clamp(0.25, 12.0),
                );
                _saveCurrentConfig();
              },
              onDoubleTap: () {
                setState(() => _gain = 1.0);
                _saveCurrentConfig();
              },
              child: CustomPaint(
                painter: WaveformPainter(
                  channels: _channelBuffers,
                  visibleChannels: _visibleChannels,
                  stacked: _stackedChannels,
                  selectedChannel: _selectedChannel,
                  gain: _gain,
                  sampleRate: _sampleRate,
                  durationSeconds: _eegDisplayDuration,
                  autoscale: _autoscaleEnabled,
                  channelLabels: _getEffectiveLabels(_channelCount),
                ),
                child: Center(
                  child: hasData
                      ? null
                      : Text(
                          (isStreaming ||
                                  (_eegSource == 'lsl'
                                      ? lsl.currentState ==
                                            AcquisitionState.connecting
                                      : acq.currentState ==
                                            AcquisitionState.connecting))
                              ? 'Connecting...'
                              : 'No EEG samples yet',
                          style: const TextStyle(color: Colors.white38),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalQualityDot(int channel) {
    final color = _signalQualityColor(channel);
    return Tooltip(
      message: _signalQualityLabel(channel),
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: WaveformPainter
                .colors[channel % WaveformPainter.colors.length],
            width: 2,
          ),
        ),
      ),
    );
  }

  Color _signalQualityColor(int channel) {
    if (channel < 0 || channel >= _channelBuffers.length) return Colors.grey;
    final data = _channelBuffers[channel];
    if (data.length < 32) return Colors.grey;
    final window = data.sublist(max(0, data.length - 250));
    final mean = window.reduce((a, b) => a + b) / window.length;
    var variance = 0.0;
    var maxAbs = 0.0;
    for (final value in window) {
      final centered = value - mean;
      variance += centered * centered;
      maxAbs = max(maxAbs, value.abs());
    }
    final rms = sqrt(variance / window.length);
    if (rms < 0.5) return const Color(0xFFEF4444);
    if (maxAbs > 500 || rms > 150) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  String _signalQualityLabel(int channel) {
    final color = _signalQualityColor(channel);
    final label = _getEffectiveLabels(_channelCount)[channel];
    if (color == const Color(0xFF10B981)) return '$label: good';
    if (color == const Color(0xFFF59E0B)) {
      return '$label: noisy/high';
    }
    if (color == const Color(0xFFEF4444)) return '$label: flat/low';
    return '$label: waiting for data';
  }
}


