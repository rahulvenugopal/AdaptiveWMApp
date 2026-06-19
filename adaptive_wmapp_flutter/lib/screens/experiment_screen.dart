import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/experiment_models.dart';
import '../services/trial_runner.dart';
import '../widgets/stimulus_renderer.dart';

class ExperimentScreen extends StatefulWidget {
  const ExperimentScreen({super.key});

  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StimulusRenderer.backgroundColor,
      body: Consumer<TrialRunner>(
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
                    ElevatedButton(
                      onPressed: () => runner.start(),
                      child: const Text("Start Experiment"),
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
                    "Experiment Complete\nData saved to CSV.",
                    style: TextStyle(color: Colors.white, fontSize: 22),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      runner.currentPhase = TrialPhase.idle;
                      setState(() {});
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
                          '${(runner.elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:'
                          '${(runner.elapsedSeconds % 60).toString().padLeft(2, '0')}',
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
      ),
    );
  }
}
