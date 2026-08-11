import 'package:flutter/material.dart';

import '../theme.dart';

/// A rounded rectangle drawn in a broken line.
///
/// The one place the app uses a dashed edge, and it earns it: a solid border
/// says "this is a panel", a dashed one says "this is a place to put things
/// in". Everything else in the interface is a hairline, so the difference reads
/// immediately.
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    required this.color,
    this.radius = MqTheme.radius,
    this.dash = 5,
    this.gap = 4,
    this.strokeWidth = 1,
  });

  final Widget child;
  final Color color;
  final double radius;

  /// The lit segment and the space after it. Kept close together: a wide gap
  /// stops reading as a rectangle at all on a shape this size.
  final double dash;
  final double gap;

  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color,
        radius: radius,
        dash: dash,
        gap: gap,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          // Inset by half the stroke so the line lands inside the box rather
          // than straddling its edge, which is what makes a dashed frame look
          // one pixel wider than the solid ones beside it.
          Rect.fromLTWH(
            strokeWidth / 2,
            strokeWidth / 2,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(radius),
        ),
      );

    final brush = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, end.clamp(0, metric.length)),
          brush,
        );
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.dash != dash ||
      old.gap != gap ||
      old.strokeWidth != strokeWidth;
}
