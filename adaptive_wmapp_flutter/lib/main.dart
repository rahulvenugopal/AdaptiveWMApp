import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/data_collector.dart';
import 'services/trial_runner.dart';
import 'screens/experiment_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdaptiveWMApp());
}

class AdaptiveWMApp extends StatelessWidget {
  const AdaptiveWMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DataCollector>(create: (_) => DataCollector()),
        ChangeNotifierProxyProvider<DataCollector, TrialRunner>(
          create: (context) => TrialRunner(context.read<DataCollector>()),
          update: (context, dataCollector, previous) => previous ?? TrialRunner(dataCollector),
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
        home: const ExperimentScreen(),
      ),
    );
  }
}
