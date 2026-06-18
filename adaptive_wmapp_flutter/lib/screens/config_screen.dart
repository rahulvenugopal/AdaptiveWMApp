import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/trial_runner.dart';
import 'experiment_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late int _fixationDuration;
  late int _cueDuration;
  late int _encodingDuration;
  late int _delayDuration;

  @override
  void initState() {
    super.initState();
    final runner = context.read<TrialRunner>();
    _fixationDuration = runner.fixationDurationMs;
    _cueDuration = runner.cueDurationMs;
    _encodingDuration = runner.encodingDurationMs;
    _delayDuration = runner.delayDurationMs;
  }

  void _saveAndContinue() {
    final runner = context.read<TrialRunner>();
    runner.fixationDurationMs = _fixationDuration;
    runner.cueDurationMs = _cueDuration;
    runner.encodingDurationMs = _encodingDuration;
    runner.delayDurationMs = _delayDuration;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ExperimentScreen()),
    );
  }

  Widget _buildDropdown(String label, int value, List<int> options, ValueChanged<int?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          DropdownButton<int>(
            value: value,
            items: options.map((int option) {
              return DropdownMenuItem<int>(
                value: option,
                child: Text('$option ms'),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trial Configuration')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select durations for the trial phases:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _buildDropdown(
              'Fixation Duration',
              _fixationDuration,
              [500, 600, 700, 800, 900],
              (val) => setState(() => _fixationDuration = val!),
            ),
            _buildDropdown(
              'Cue Duration',
              _cueDuration,
              [300, 400, 500, 600, 700],
              (val) => setState(() => _cueDuration = val!),
            ),
            _buildDropdown(
              'Encoding Array Duration',
              _encodingDuration,
              [300, 400, 500, 600, 700],
              (val) => setState(() => _encodingDuration = val!),
            ),
            _buildDropdown(
              'Delay Duration',
              _delayDuration,
              [1000, 1100, 1200, 1300, 1400],
              (val) => setState(() => _delayDuration = val!),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _saveAndContinue,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Continue to Instructions', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
