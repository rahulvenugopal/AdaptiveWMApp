import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/acquisition_service.dart';
import '../services/edf_recorder.dart';
import 'config_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _subjectController = TextEditingController(text: 'Subj001');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final acq = context.read<AcquisitionService>();
      acq.requestPermissions().then((_) {
        acq.addSyntheticDevice();
        acq.scan();
      });
    });
  }

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  void _startExperiment() async {
    if (_subjectController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a subject ID')),
      );
      return;
    }

    final edf = context.read<EdfRecorder>();
    try {
      // Start recording EDF. Assuming 2 channels (EEG + Marker) and 250Hz default.
      await edf.start(
        subject: _subjectController.text,
        channelCount: 2, // 2 Channels (1 EEG + 1 Marker) for simplicity.
        sampleRate: 250,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ConfigScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting EDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final acq = context.watch<AcquisitionService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Device Setup')),
      body: Padding(
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
              children: [
                ElevatedButton(
                  onPressed: () => acq.scan(),
                  child: const Text('Scan Devices'),
                ),
                const SizedBox(width: 8),
                if (acq.currentState == AcquisitionState.scanning)
                  const CircularProgressIndicator(),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<EegDevice>>(
                stream: acq.devices,
                initialData: const [],
                builder: (context, snapshot) {
                  final devices = snapshot.data ?? [];
                  if (devices.isEmpty) {
                    return const Center(child: Text('No devices found'));
                  }
                  return ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
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
            StreamBuilder<AcquisitionState>(
              stream: acq.state,
              initialData: acq.currentState,
              builder: (context, snapshot) {
                final state = snapshot.data ?? AcquisitionState.disconnected;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Status: ${state.name}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: state == AcquisitionState.streaming
                          ? _startExperiment
                          : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Start Experiment'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
