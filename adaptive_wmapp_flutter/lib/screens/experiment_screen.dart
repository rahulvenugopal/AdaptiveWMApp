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
              if (runner.currentPhase == TrialPhase.retrieval)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: const Color.fromARGB(210, 33, 33, 36),
                    padding: const EdgeInsets.all(16),
                    height: 100,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(255, 52, 143, 80),
                            ),
                            onPressed: () => runner.submitResponse(MatchDecision.match),
                            child: const Text("Match", style: TextStyle(color: Colors.white, fontSize: 18)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(255, 181, 61, 55),
                            ),
                            onPressed: () => runner.submitResponse(MatchDecision.mismatch),
                            child: const Text("Mismatch", style: TextStyle(color: Colors.white, fontSize: 18)),
                          ),
                        ),
                      ],
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
