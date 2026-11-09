import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/src/engine/scenario_step.dart';

/// 타겟 위젯 주변에 스포트라이트 디밍, Elevation Glow, Pulse Border를 그리는 CustomPainter
class ScenarioHighlightPainter extends CustomPainter {
  final Rect? targetRect;
  final HighlightStyle style;
  final double pulsePhase;
  final double opacity;

  const ScenarioHighlightPainter({
    required this.targetRect,
    required this.style,
    required this.pulsePhase,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = targetRect;
    if (rect == null || opacity <= 0.0) return;

    final paddedRect = style.padding.inflateRect(rect);
    final pulseDelta =
        (paddedRect.shortestSide * style.pulseScale) * pulsePhase;
    final animatedRect = paddedRect.inflate(pulseDelta);
    final rrect = RRect.fromRectAndRadius(
      animatedRect,
      Radius.circular(style.borderRadius),
    );

    if (style.dimBackground) {
      final screenRect = Offset.zero & size;
      canvas.saveLayer(screenRect, Paint());
      canvas.drawRect(
        screenRect,
        Paint()
          ..color = style.dimColor.withValues(
            alpha: style.dimColor.a * opacity,
          ),
      );
      canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
      canvas.restore();
    }

    if (style.elevationBlur > 0) {
      final glowPaint = Paint()
        ..color = style.glowColor.withValues(
          alpha: (style.glowColor.a * (0.65 + 0.35 * pulsePhase) * opacity)
              .clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.borderWidth + 4.0 + (pulsePhase * 3.0)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          style.elevationBlur * (0.85 + 0.3 * pulsePhase),
        );
      canvas.drawRRect(rrect, glowPaint);
    }

    final outerRingRect = animatedRect.inflate(pulsePhase * 6.0);
    final outerRingRRect = RRect.fromRectAndRadius(
      outerRingRect,
      Radius.circular(style.borderRadius + 3.0),
    );
    final outerRingPaint = Paint()
      ..color = style.borderColor.withValues(
        alpha: ((1.0 - pulsePhase * 0.5) * 0.45 * opacity).clamp(0.0, 1.0),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(outerRingRRect, outerRingPaint);

    final borderPaint = Paint()
      ..color = style.borderColor.withValues(alpha: opacity.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.borderWidth;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant ScenarioHighlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.style != style ||
        oldDelegate.pulsePhase != pulsePhase ||
        oldDelegate.opacity != opacity;
  }
}
