import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/experiment_models.dart';
import '../services/trial_runner.dart';
import '../widgets/stimulus_renderer.dart';
import '../widgets/stanford_sleepiness_scale.dart';
import '../services/device_config_service.dart';
import '../services/channel_config_service.dart';
import '../services/acquisition_service.dart';
import '../services/lsl_eeg_acquisition_service.dart';

class ExperimentScreen extends StatefulWidget {
  final String subjectId;
  final bool showSleepinessPostSession;

  const ExperimentScreen({
    super.key,
    required this.subjectId,
    required this.showSleepinessPostSession,
  });

  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  DeviceConfig? _deviceConfig;
  ChannelConfig? _channelConfig;

  StreamSubscription<AcquisitionState>? _acqSub;
  StreamSubscription<AcquisitionState>? _lslSub;

  @override
  void initState() {
    super.initState();
    DeviceConfigService.load().then((cfg) {
      if (!mounted) return;
      setState(() => _deviceConfig = cfg);
      _setupListeners();
    });
    ChannelConfigService.load().then((cfg) {
      if (!mounted) return;
      setState(() => _channelConfig = cfg);
    });
  }

  void _setupListeners() {
    final acq = context.read<AcquisitionService>();
    final lsl = context.read<LslEegAcquisitionService>();

    _acqSub = acq.state.listen((state) {
      if (!mounted) return;
      if (_deviceConfig?.eegSource != 'bluetooth') return;
      _handleStateChange(state);
    });

    _lslSub = lsl.state.listen((state) {
      if (!mounted) return;
      if (_deviceConfig?.eegSource != 'lsl') return;
      _handleStateChange(state);
    });
  }

  void _handleStateChange(AcquisitionState state) {
    if (_deviceConfig?.eegDisplayMode != 'eeg_and_paradigm') return;
    
    final runner = context.read<TrialRunner>();
    if (state == AcquisitionState.disconnected && !runner.isPaused && runner.isRunning) {
      runner.pause();
    } else if (state == AcquisitionState.streaming && runner.isPaused) {
      runner.resume();
    }
  }

  @override
  void dispose() {
    _acqSub?.cancel();
    _lslSub?.cancel();
    super.dispose();
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Exit Experiment?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to stop the experiment early? Data collected so far will be saved.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(context).pop();
              _exitExperiment();
            },
            child: const Text('Exit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _exitExperiment() async {
    final runner = context.read<TrialRunner>();
    if (runner.isRunning) {
      runner.stop();
      // Wait for CSV and EDF to stop and export
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    if (widget.showSleepinessPostSession && mounted) {
      await StanfordSleepinessScaleDialog.show(
        context,
        'AdaptiveWMApp',
        widget.subjectId,
        'post-session (exited)',
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }



  @override
  Widget build(BuildContext context) {
    if (_deviceConfig == null || _channelConfig == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF020617),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _showExitConfirmation();
      },
      child: Scaffold(
        backgroundColor: StimulusRenderer.backgroundColor,
        body: Stack(
          children: [
            _buildParadigm(context),
            // Top-right exit button available at all times
            Positioned(
              top: 32,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 32),
                tooltip: 'Exit Experiment',
                onPressed: _showExitConfirmation,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParadigm(BuildContext context) {
    return Consumer<TrialRunner>(
      builder: (context, runner, child) {
          if (runner.currentPhase == TrialPhase.idle) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "You will see a fixation cross and then a cue to left or right.\n\n"
                      "Focus only on the cued side.\n\n"
                      "One of the color would change in cued side, position wont change.\n\n"
                      "Press match if the initial array is ditto same as other and press mismatch if there is a mismatch.\n\n"
                      "Tap anywhere to continue.",
                      style: TextStyle(color: Colors.white, fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    Builder(
                      builder: (context) {
                        if (_deviceConfig?.eegDisplayMode == 'eeg_and_paradigm') {
                          final isLsl = _deviceConfig?.eegSource == 'lsl';
                          final state = isLsl
                              ? context.watch<LslEegAcquisitionService>().currentState
                              : context.watch<AcquisitionService>().currentState;
                          
                          if (state != AcquisitionState.streaming) {
                            return ElevatedButton(
                              onPressed: null,
                              style: ElevatedButton.styleFrom(disabledBackgroundColor: Colors.grey[800]),
                              child: const Text("Waiting for EEG Connection...", style: TextStyle(color: Colors.white54)),
                            );
                          }
                        }
                        return ElevatedButton(
                          onPressed: () => runner.start(),
                          child: const Text("Start Experiment"),
                        );
                      }
                    ),
                  ],
                ),
              ),
            );
          }

          if (runner.currentPhase == TrialPhase.finished) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Experiment Complete\nData saved to Downloads Folder.",
                    style: TextStyle(color: Colors.white, fontSize: 22),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      if (widget.showSleepinessPostSession) {
                        await StanfordSleepinessScaleDialog.show(
                          context,
                          'AdaptiveWMApp',
                          widget.subjectId,
                          'post-session (finished)',
                        );
                      }
                      if (!mounted) return;
                      runner.currentPhase = TrialPhase.idle;
                      setState(() {});
                      Navigator.of(context).pop();
                    },
                    child: const Text("Return Home"),
                  ),
                ],
              ),
            );
          }

          return Stack(
            children: [
              StimulusRenderer(
                phase: runner.currentPhase,
                currentTrial: runner.currentTrial,
                cueHemifield: runner.currentCue,
              ),
              if (runner.isRunning)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: Color(0xFF60A5FA),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${(runner.elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(runner.elapsedSeconds % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Color(0xFF60A5FA),
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (runner.isRunning)
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    onPressed: _showExitConfirmation,
                    icon: const Icon(Icons.close, color: Colors.white70, size: 28),
                    tooltip: 'Exit Experiment',
                  ),
                ),
              if (runner.currentPhase == TrialPhase.retrieval)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: const Color.fromARGB(210, 33, 33, 36),
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(
                                255,
                                52,
                                143,
                                80,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 24),
                            ),
                            onPressed: () =>
                                runner.submitResponse(MatchDecision.match),
                            child: const Text(
                              "Match",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(
                                255,
                                181,
                                61,
                                55,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 24),
                            ),
                            onPressed: () =>
                                runner.submitResponse(MatchDecision.mismatch),
                            child: const Text(
                              "Mismatch",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (runner.isPaused)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.6),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                      child: Center(
                        child: Card(
                          color: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Colors.white12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 30,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF14B8A6),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  "EEG Connection Lost",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  "EEG disconnected – waiting for reconnect…",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                  ),
                                  onPressed: () {
                                    runner.stop();
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text(
                                    "Cancel Experiment",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
  }
}
