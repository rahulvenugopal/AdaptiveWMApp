import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../models/experiment_models.dart';

class DataCollector {
  final List<TrialRecord> _records = [];

  void log(TrialRecord record) {
    _records.add(record);
  }

  void clear() {
    _records.clear();
  }

  List<TrialRecord> allRecords() => List.unmodifiable(_records);

  Future<String> exportCsvString() async {
    List<List<dynamic>> rows = [
      [
        'trial_number',
        'set_size',
        'cued_hemifield',
        'is_match_trial',
        'user_response',
        'accuracy',
        'reaction_time_ms'
      ]
    ];
    
    for (var record in _records) {
      rows.add(record.toCsvRow());
    }

    return csv.encode(rows);
  }

  Future<String> saveToCsvFile() async {
    final csvString = await exportCsvString();
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${directory.path}/adaptive_wm_$timestamp.csv');
    await file.writeAsString(csvString);
    return file.path;
  }
}
