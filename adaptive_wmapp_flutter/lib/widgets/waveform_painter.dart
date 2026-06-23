import 'dart:math';

import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.channels,
    required this.visibleChannels,
    required this.stacked,
    required this.selectedChannel,
    required this.gain,
    required this.sampleRate,
    required this.durationSeconds,
    required this.autoscale,
    this.channelLabels,
  });

  final List<List<double>> channels;
  final List<bool> visibleChannels;
  final bool stacked;
  final int selectedChannel;
  final double gain;
  final double sampleRate;
  final int durationSeconds;
  final bool autoscale;
  /// Optional list of channel label strings (e.g. 10-20 labels like 'Fp1', 'Cz').
  /// Falls back to 'Ch N' if null or index out of range.
  final List<String>? channelLabels;

  static const colors = [
    Color(0xFF14B8A6), // Teal
    Color(0xFF3B82F6), // Blue
    Color(0xFFF87171), // Coral
    Color(0xFFFBBF24), // Amber
    Color(0xFF8B5CF6), // Purple
    Color(0xFF10B981), // Emerald
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    final indices = stacked
        ? [
            for (var i = 0; i < channels.length; i++)
              if (i < visibleChannels.length && visibleChannels[i]) i,
          ]
        : [selectedChannel.clamp(0, max(0, channels.length - 1)).toInt()];
    if (indices.isEmpty) return;
    final points = max(2, (sampleRate * durationSeconds).round());
    final laneHeight = size.height / indices.length;
    for (var lane = 0; lane < indices.length; lane++) {
      final channel = indices[lane];
      final data = channels[channel];
      if (data.length < 2) continue;
      final start = max(0, data.length - points);
      final visible = data.sublist(start);
      final mean = visible.reduce((a, b) => a + b) / visible.length;

      final double scaleFactor;
      if (autoscale) {
        scaleFactor = max(
          20.0,
          visible.map((v) => (v - mean).abs()).reduce(max),
        );
      } else {
        // Fixed scale: 150 uV full-scale height per lane
        scaleFactor = 150.0;
      }

      final centerY = laneHeight * (lane + 0.5);
      final path = Path();
      for (var i = 0; i < visible.length; i++) {
        final x = i * size.width / max(1, points - 1);
        final y =
            (centerY -
                    ((visible[i] - mean) / scaleFactor) * laneHeight * 0.42 * gain)
                .clamp(0.0, size.height);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[channel % colors.length]
          ..strokeWidth = stacked ? 1.2 : 1.6
          ..style = PaintingStyle.stroke,
      );
      final label = TextPainter(
        text: TextSpan(
          text: channelLabels != null && channel < channelLabels!.length
              ? channelLabels![channel]
              : 'Ch ${channel + 1}',
          style: TextStyle(
            color: colors[channel % colors.length],
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(6, centerY - label.height - 3));
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) => true;
}
