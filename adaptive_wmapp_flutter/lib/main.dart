import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/data_collector.dart';
import 'services/trial_runner.dart';
import 'services/acquisition_service.dart';
import 'services/edf_recorder.dart';
import 'screens/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdaptiveWMApp());
}

class AdaptiveWMApp extends StatefulWidget {
  const AdaptiveWMApp({super.key});

  @override
  State<AdaptiveWMApp> createState() => _AdaptiveWMAppState();
}

class _AdaptiveWMAppState extends State<AdaptiveWMApp> {
  final _acqService = AcquisitionService();
  final _edfRecorder = EdfRecorder();

  @override
  void initState() {
    super.initState();
    // Pipe EEG samples directly into the EDF Recorder
    _acqService.samples.listen((sample) {
      if (_edfRecorder.isRecording) {
        _edfRecorder.push(sample);
      }
    });
  }

  @override
  void dispose() {
    _acqService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AcquisitionService>.value(value: _acqService),
        Provider<EdfRecorder>.value(value: _edfRecorder),
        Provider<DataCollector>(create: (_) => DataCollector()),
        ChangeNotifierProxyProvider2<DataCollector, EdfRecorder, TrialRunner>(
          create: (context) => TrialRunner(context.read<DataCollector>(), context.read<EdfRecorder>()),
          update: (context, dataCollector, edfRecorder, previous) => previous ?? TrialRunner(dataCollector, edfRecorder),
        ),
      ],
      child: MaterialApp(
        title: 'Adaptive WM App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const SetupScreen(),
      ),
    );
  }
}
