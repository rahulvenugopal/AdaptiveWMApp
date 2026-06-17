import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import '../models/experiment_models.dart';
import 'data_collector.dart';
import 'edf_recorder.dart';

class TrialRunner extends ChangeNotifier {
  final DataCollector dataCollector;
  final EdfRecorder edfRecorder;
  final Random _random = Random();
  
  LSLStreamInfo? _streamInfo;
  LSLOutlet? _outlet;

  TrialPhase currentPhase = TrialPhase.idle;
  int currentSetSize = 2;
  int _consecutiveCorrect = 0;
  bool _isRunning = false;
  
  TrialPlan? currentTrial;
  Hemifield? currentCue;
  
  Completer<MatchDecision>? _responseCompleter;
  int _retrievalOnsetMs = 0;

  TrialRunner(this.dataCollector, this.edfRecorder) {
    _initLsl();
  }

  void _initLsl() async {
    try {
      _streamInfo = LSLStreamInfo(
        streamName: 'AdaptiveWM_Markers',
        streamType: LSLContentType.markers,
        channelCount: 1,
        sampleRate: 0.0,
        channelFormat: LSLChannelFormat.int32,
        sourceId: 'awm_uid'
      );
      _outlet = LSLOutlet(_streamInfo!);
      await _outlet!.create();
    } catch (e) {
      debugPrint("Failed to init LSL: $e");
    }
  }

  void _pushMarker(int marker) {
    try {
      if (_outlet != null) {
        _outlet!.pushSample([marker]);
      }
      edfRecorder.setMarker(marker);
    } catch (e) {
      debugPrint("Failed to push LSL marker $marker: $e");
    }
  }

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    dataCollector.clear();
    currentSetSize = 2;
    _consecutiveCorrect = 0;

    for (int trialNum = 1; trialNum <= 100; trialNum++) {
      if (!_isRunning) break;
      final trial = _createTrialPlan(trialNum, currentSetSize);
      await _runTrial(trial);
    }

    _transitionTo(TrialPhase.finished, null);
    await dataCollector.saveToCsvFile();
    _isRunning = false;
  }

  void stop() {
    _isRunning = false;
    _responseCompleter?.complete(MatchDecision.noResponse);
  }

  void submitResponse(MatchDecision decision) {
    if (decision == MatchDecision.noResponse) return;
    if (currentPhase != TrialPhase.retrieval || _responseCompleter == null || _responseCompleter!.isCompleted) return;
    
    _responseCompleter!.complete(decision);
  }

  Future<void> _runTrial(TrialPlan trial) async {
    _transitionTo(TrialPhase.iti, trial);
    await _delay(_random.nextInt(501) + 300); // 300 to 800

    _pushMarker(88); // Fixation marker
    _transitionTo(TrialPhase.fixation, trial);
    await _delay(500);

    _transitionTo(TrialPhase.cue, trial);
    await _delay(300);

    final encodingMarker = (trial.setSize * 10) + (trial.cuedHemifield == Hemifield.left ? 1 : 9);
    _pushMarker(encodingMarker);
    _transitionTo(TrialPhase.encoding, trial);
    await _delay(300);

    _transitionTo(TrialPhase.maintenance, trial);
    await _delay(1000);

    final response = await _runRetrieval(trial);
    final userDecision = response ?? MatchDecision.noResponse;
    
    int responseMarker = 12; // omission
    if (userDecision == MatchDecision.match) responseMarker = 11;
    if (userDecision == MatchDecision.mismatch) responseMarker = 10;
    _pushMarker(responseMarker);

    final isResponseCorrect = _isCorrect(userDecision, trial);
    final accuracy = isResponseCorrect ? 1 : 0;
    
    int? rt;
    if (userDecision != MatchDecision.noResponse) {
      rt = DateTime.now().millisecondsSinceEpoch - _retrievalOnsetMs;
    }

    dataCollector.log(
      TrialRecord(
        trialNumber: trial.trialNumber,
        setSize: trial.setSize,
        cuedHemifield: trial.cuedHemifield,
        isMatchTrial: trial.isMatchTrial,
        userResponse: userDecision,
        accuracy: accuracy,
        reactionTimeMs: rt,
      ),
    );

    _updateStaircase(isResponseCorrect);
  }

  Future<MatchDecision?> _runRetrieval(TrialPlan trial) async {
    _responseCompleter = Completer<MatchDecision>();
    _retrievalOnsetMs = DateTime.now().millisecondsSinceEpoch;
    _transitionTo(TrialPhase.retrieval, trial);

    try {
      final decision = await _responseCompleter!.future.timeout(const Duration(milliseconds: 2000));
      return decision;
    } on TimeoutException {
      return MatchDecision.noResponse;
    } finally {
      _responseCompleter = null;
    }
  }

  void _transitionTo(TrialPhase phase, TrialPlan? trial) {
    currentPhase = phase;
    currentTrial = trial;
    if (phase == TrialPhase.cue || phase == TrialPhase.encoding || phase == TrialPhase.retrieval) {
      currentCue = trial?.cuedHemifield;
    } else {
      currentCue = null;
    }
    notifyListeners();
  }

  Future<void> _delay(int milliseconds) async {
    if (!_isRunning) return;
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  TrialPlan _createTrialPlan(int trialNumber, int setSize) {
    final cuedHemifield = _random.nextBool() ? Hemifield.left : Hemifield.right;
    final isMatchTrial = _random.nextBool();
    
    final leftItems = _createHemifieldItems(Hemifield.left, setSize);
    final rightItems = _createHemifieldItems(Hemifield.right, setSize);
    
    final cuedItems = cuedHemifield == Hemifield.left ? leftItems : rightItems;
    final uncuedItems = cuedHemifield == Hemifield.left ? rightItems : leftItems;
    
    final cuedTestItems = isMatchTrial ? cuedItems.map((e) => e.copyWith()).toList() : _createMismatchItems(cuedItems);
    
    List<StimulusItem> testItems;
    if (cuedHemifield == Hemifield.left) {
      testItems = [...cuedTestItems, ...uncuedItems.map((e) => e.copyWith())];
    } else {
      testItems = [...uncuedItems.map((e) => e.copyWith()), ...cuedTestItems];
    }

    return TrialPlan(
      trialNumber: trialNumber,
      setSize: setSize,
      cuedHemifield: cuedHemifield,
      isMatchTrial: isMatchTrial,
      memoryItems: [...leftItems, ...rightItems],
      testItems: testItems,
    );
  }

  List<StimulusItem> _createHemifieldItems(Hemifield hemifield, int setSize) {
    final slots = List<StimulusSlot>.from(_slotTemplate)..shuffle(_random);
    final colors = List<Color>.from(_colorPalette)..shuffle(_random);
    
    final selectedSlots = slots.take(setSize).toList();
    final selectedColors = colors.take(setSize).toList();
    
    return List.generate(setSize, (i) => StimulusItem(
      hemifield: hemifield,
      slot: selectedSlots[i],
      color: selectedColors[i],
    ));
  }

  List<StimulusItem> _createMismatchItems(List<StimulusItem> cuedItems) {
    final changedIndex = _random.nextInt(cuedItems.length);
    final usedColors = cuedItems.map((e) => e.color).toSet();
    final availableColors = _colorPalette.where((c) => !usedColors.contains(c)).toList();
    final replacement = availableColors[_random.nextInt(availableColors.length)];
    
    final newItems = cuedItems.map((e) => e.copyWith()).toList();
    newItems[changedIndex] = newItems[changedIndex].copyWith(color: replacement);
    return newItems;
  }

  bool _isCorrect(MatchDecision decision, TrialPlan trial) {
    if (decision == MatchDecision.match) return trial.isMatchTrial;
    if (decision == MatchDecision.mismatch) return !trial.isMatchTrial;
    return false;
  }

  void _updateStaircase(bool wasCorrect) {
    if (wasCorrect) {
      _consecutiveCorrect++;
      if (_consecutiveCorrect >= 2) {
        currentSetSize = (currentSetSize + 1).clamp(3, 8);
        _consecutiveCorrect = 0;
      }
    } else {
      _consecutiveCorrect = 0;
      currentSetSize = (currentSetSize - 1).clamp(3, 8);
    }
  }

  @override
  void dispose() {
    _outlet?.destroy();
    _streamInfo?.destroy();
    super.dispose();
  }

  static const List<StimulusSlot> _slotTemplate = [
    StimulusSlot(-0.82, -0.58),
    StimulusSlot(0, -0.72),
    StimulusSlot(0.82, -0.58),
    StimulusSlot(-0.82, 0),
    StimulusSlot(0.82, 0),
    StimulusSlot(-0.82, 0.58),
    StimulusSlot(0, 0.72),
    StimulusSlot(0.82, 0.58)
  ];

  static const List<Color> _colorPalette = [
    Color.fromARGB(255, 228, 30, 40),
    Color.fromARGB(255, 242, 128, 20),
    Color.fromARGB(255, 242, 215, 20),
    Color.fromARGB(255, 100, 222, 20),
    Color.fromARGB(255, 20, 188, 90),
    Color.fromARGB(255, 20, 215, 222),
    Color.fromARGB(255, 20, 100, 222),
    Color.fromARGB(255, 138, 20, 222),
    Color.fromARGB(255, 222, 20, 165),
    Colors.white,
  ];
}
