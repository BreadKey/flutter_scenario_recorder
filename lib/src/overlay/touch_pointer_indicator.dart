import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/src/engine/scenario_step.dart';

/// 가상 손가락 터치 위치와 탭 동심원(Ripple)을 렌더링하는 인디케이터 위젯
class TouchPointerIndicator extends StatelessWidget {
  final Offset? position;
  final bool isDown;
  final double rippleProgress;
  final Color color;

  const TouchPointerIndicator({
    super.key,
    required this.position,
    required this.isDown,
    required this.rippleProgress,
    this.color = kDefaultScenarioAccentColor,
  });

  @override
  Widget build(BuildContext context) {
    final pos = position;
    if (pos == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _TouchPointerPainter(
          position: pos,
          isDown: isDown,
          rippleProgress: rippleProgress,
          color: color,
        ),
      ),
    );
  }
}

class _TouchPointerPainter extends CustomPainter {
  final Offset position;
  final bool isDown;
  final double rippleProgress;
  final Color color;

  const _TouchPointerPainter({
    required this.position,
    required this.isDown,
    required this.rippleProgress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rippleProgress > 0.0 && rippleProgress < 1.0) {
      final rippleRadius = 18.0 + (28.0 * rippleProgress);
      final rippleAlpha = ((1.0 - rippleProgress) * 0.55).clamp(0.0, 1.0);

      final ripplePaint = Paint()
        ..color = color.withValues(alpha: rippleAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 * (1.0 - rippleProgress * 0.5);
      canvas.drawCircle(position, rippleRadius, ripplePaint);
    }

    final baseRadius = isDown ? 13.0 : 16.0;
    final shadowPaint = Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(position + const Offset(0, 2), baseRadius, shadowPaint);

    final fillPaint = Paint()
      ..color = color.withValues(alpha: isDown ? 0.72 : 0.45)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, baseRadius, fillPaint);

    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(position, baseRadius, strokePaint);

    final centerDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, isDown ? 4.5 : 3.5, centerDotPaint);
  }

  @override
  bool shouldRepaint(covariant _TouchPointerPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.isDown != isDown ||
        oldDelegate.rippleProgress != rippleProgress ||
        oldDelegate.color != color;
  }
}
