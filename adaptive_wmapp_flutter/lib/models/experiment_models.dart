import 'dart:ui';

enum Hemifield {
  left,
  right;

  String cueSymbol() => this == Hemifield.left ? "<" : ">";
}

enum TrialPhase {
  idle,
  iti,
  fixation,
  cue,
  encoding,
  maintenance,
  retrieval,
  finished
}

enum MatchDecision {
  match('match'),
  mismatch('mismatch'),
  noResponse('no_response');

  final String exportLabel;
  const MatchDecision(this.exportLabel);
}

class StimulusSlot {
  final double xFraction;
  final double yFraction;

  const StimulusSlot(this.xFraction, this.yFraction);
}

class StimulusItem {
  final Hemifield hemifield;
  final StimulusSlot slot;
  final Color color;

  StimulusItem({
    required this.hemifield,
    required this.slot,
    required this.color,
  });

  StimulusItem copyWith({Hemifield? hemifield, StimulusSlot? slot, Color? color}) {
    return StimulusItem(
      hemifield: hemifield ?? this.hemifield,
      slot: slot ?? this.slot,
      color: color ?? this.color,
    );
  }
}

class TrialPlan {
  final int trialNumber;
  final int setSize;
  final Hemifield cuedHemifield;
  final bool isMatchTrial;
  final List<StimulusItem> memoryItems;
  final List<StimulusItem> testItems;

  TrialPlan({
    required this.trialNumber,
    required this.setSize,
    required this.cuedHemifield,
    required this.isMatchTrial,
    required this.memoryItems,
    required this.testItems,
  });
}

class TrialRecord {
  final int trialNumber;
  final int setSize;
  final Hemifield cuedHemifield;
  final bool isMatchTrial;
  final MatchDecision userResponse;
  final int accuracy;
  final int? reactionTimeMs;

  TrialRecord({
    required this.trialNumber,
    required this.setSize,
    required this.cuedHemifield,
    required this.isMatchTrial,
    required this.userResponse,
    required this.accuracy,
    this.reactionTimeMs,
  });

  List<dynamic> toCsvRow() {
    return [
      trialNumber,
      setSize,
      cuedHemifield.name,
      isMatchTrial,
      userResponse.exportLabel,
      accuracy,
      reactionTimeMs ?? '',
    ];
  }
}
