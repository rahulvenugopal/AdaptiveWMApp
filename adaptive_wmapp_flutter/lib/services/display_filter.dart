import 'dart:math';

class DisplayFilter {
  DisplayFilter(double sampleRate) {
    _notch = _Biquad.notch(sampleRate, 50, 25);
    _highPass = _Biquad.highPass(sampleRate, 1);
    _lowPass = _Biquad.lowPass(sampleRate, min(30, sampleRate * 0.4));
  }

  late final _Biquad _notch;
  late final _Biquad _highPass;
  late final _Biquad _lowPass;

  double process(
    double value, {
    required bool notchEnabled,
    required bool bandpassEnabled,
  }) {
    var filtered = value;
    if (notchEnabled) {
      filtered = _notch.process(filtered);
    }
    if (bandpassEnabled) {
      filtered = _lowPass.process(_highPass.process(filtered));
    }
    return filtered;
  }
}

class _Biquad {
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _Biquad.notch(double sampleRate, double frequency, double q) {
    final w0 = 2 * pi * frequency / sampleRate;
    final alpha = sin(w0) / (2 * q);
    final a0 = 1 + alpha;
    return _Biquad(
      1 / a0,
      -2 * cos(w0) / a0,
      1 / a0,
      -2 * cos(w0) / a0,
      (1 - alpha) / a0,
    );
  }

  factory _Biquad.highPass(double sampleRate, double frequency) {
    final w0 = 2 * pi * frequency / sampleRate;
    final alpha = sin(w0) / (2 * sqrt(0.5));
    final a0 = 1 + alpha;
    return _Biquad(
      (1 + cos(w0)) / (2 * a0),
      -(1 + cos(w0)) / a0,
      (1 + cos(w0)) / (2 * a0),
      -2 * cos(w0) / a0,
      (1 - alpha) / a0,
    );
  }

  factory _Biquad.lowPass(double sampleRate, double frequency) {
    final w0 = 2 * pi * frequency / sampleRate;
    final alpha = sin(w0) / (2 * sqrt(0.5));
    final a0 = 1 + alpha;
    return _Biquad(
      (1 - cos(w0)) / (2 * a0),
      (1 - cos(w0)) / a0,
      (1 - cos(w0)) / (2 * a0),
      -2 * cos(w0) / a0,
      (1 - alpha) / a0,
    );
  }

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;
  double _x1 = 0;
  double _x2 = 0;
  double _y1 = 0;
  double _y2 = 0;

  double process(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}
