import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/data_collector.dart';
import 'services/trial_runner.dart';
import 'services/acquisition_service.dart';
import 'services/lsl_eeg_acquisition_service.dart';
import 'services/edf_recorder.dart';
import 'screens/setup_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AcdmtApp());
}

class AcdmtApp extends StatefulWidget {
  const AcdmtApp({super.key});

  @override
  State<AcdmtApp> createState() => _AcdmtAppState();
}

class _AcdmtAppState extends State<AcdmtApp> {
  final _acqService = AcquisitionService();
  final _edfRecorder = EdfRecorder();
  final _lslEegService = LslEegAcquisitionService();

  @override
  void initState() {
    super.initState();
    // Pipe EEG samples directly into the EDF Recorder
    _acqService.samples.listen((sample) {
      if (_edfRecorder.isRecording) {
        _edfRecorder.push(sample);
      }
    });
    _lslEegService.samples.listen((sample) {
      if (_edfRecorder.isRecording) {
        _edfRecorder.push(sample);
      }
    });


  }

  @override
  void dispose() {
    _acqService.dispose();
    _lslEegService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AcquisitionService>.value(value: _acqService),
        Provider<LslEegAcquisitionService>.value(value: _lslEegService),
        Provider<EdfRecorder>.value(value: _edfRecorder),
        Provider<DataCollector>(create: (_) => DataCollector()),
        ChangeNotifierProxyProvider2<DataCollector, EdfRecorder, TrialRunner>(
          create: (context) => TrialRunner(context.read<DataCollector>(), context.read<EdfRecorder>()),
          update: (context, dataCollector, edfRecorder, previous) => previous ?? TrialRunner(dataCollector, edfRecorder),
        ),
      ],
      child: MaterialApp(
        title: 'ACDMT',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
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
