import 'dart:math';
import 'package:flutter/material.dart';

/// Аналоговый круговой прибор (стрелка), как в Torque.
class GaugeWidget extends StatelessWidget {
  final String label;
  final String unit;
  final double value;
  final double maxValue;
  final Color color;

  const GaugeWidget({
    super.key,
    required this.label,
    required this.unit,
    required this.value,
    required this.maxValue,
    this.color = Colors.cyanAccent,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _GaugePainter(value.clamp(0, maxValue), maxValue, color),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 36),
              Text(value.toStringAsFixed(0),
                  style: TextStyle(
                      color: color,
                      fontSize: 30,
                      fontWeight: FontWeight.bold)),
              Text(unit,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final double maxValue;
  final Color color;
  _GaugePainter(this.value, this.maxValue, this.color);

  // дуга от 135° до 405° (270° полного хода)
  static const _start = 135 * pi / 180;
  static const _sweep = 270 * pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // фон дуги
    final bg = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, bg);

    // заполненная часть
    final fillAngle = _sweep * (value / maxValue);
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, fillAngle, false, fg);

    // стрелка
    final needleAngle = _start + fillAngle;
    final needleEnd = Offset(
      center.dx + (radius - 18) * cos(needleAngle),
      center.dy + (radius - 18) * sin(needleAngle),
    );
    final needle = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleEnd, needle);
    canvas.drawCircle(center, 5, Paint()..color = Colors.redAccent);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}
