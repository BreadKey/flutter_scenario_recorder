import 'package:flutter_scenario_recorder/src/engine/frame_recorder.dart';
import 'package:flutter_scenario_recorder/src/engine/scenario_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// `flutter test`의 `WidgetTester`와 동기화되는 단위 테스트용 `ScenarioClock`
class WidgetTesterScenarioClock extends ScenarioClock {
  final WidgetTester tester;

  const WidgetTesterScenarioClock(this.tester);

  @override
  Future<void> delay(Duration duration) async {
    if (duration <= Duration.zero) return;
    const step = Duration(milliseconds: 16);
    var remaining = duration;
    while (remaining > Duration.zero) {
      final chunk = remaining > step ? step : remaining;
      await tester.pump(chunk);
      remaining -= chunk;
    }
  }

  @override
  Future<void> animate(
    Duration duration,
    void Function(double progress) onTick, {
    int fps = 60,
  }) async {
    if (duration <= Duration.zero) {
      onTick(1.0);
      await tester.pump();
      return;
    }

    final frameDuration = Duration(microseconds: (1000000 / fps).round());
    final totalFrames =
        (duration.inMicroseconds / frameDuration.inMicroseconds).round().clamp(
          1,
          10000,
        );

    onTick(0.0);
    await tester.pump();

    for (var i = 1; i <= totalFrames; i++) {
      await tester.pump(frameDuration);
      onTick((i / totalFrames).clamp(0.0, 1.0));
    }
    await tester.pump();
  }
}

/// `flutter test`의 가상 시계(`tester.pump`)를 정확히 `1/fps`초씩 전진시키며
/// `FfmpegPipeFrameRecorder.captureFrame()`을 호출하는 결정론적(Deterministic) 비디오 시계
class DeterministicVideoScenarioClock extends ScenarioClock {
  final WidgetTester tester;
  final FfmpegPipeFrameRecorder recorder;

  const DeterministicVideoScenarioClock({
    required this.tester,
    required this.recorder,
  });

  Duration get _frameDuration =>
      Duration(microseconds: (1000000 / recorder.fps).round());

  Future<void> _pumpAndCapture() async {
    await tester.pump(_frameDuration);
    while (tester.takeException() != null) {}
    await tester.runAsync(() async {
      await recorder.captureFrame();
    });
  }

  @override
  Future<void> delay(Duration duration) async {
    if (duration <= Duration.zero) return;
    final totalFrames =
        (duration.inMicroseconds / _frameDuration.inMicroseconds).round().clamp(
          1,
          100000,
        );
    for (var i = 0; i < totalFrames; i++) {
      await _pumpAndCapture();
    }
  }

  @override
  Future<void> animate(
    Duration duration,
    void Function(double progress) onTick, {
    int fps = 60,
  }) async {
    if (duration <= Duration.zero) {
      onTick(1.0);
      await _pumpAndCapture();
      return;
    }

    final totalFrames =
        (duration.inMicroseconds / _frameDuration.inMicroseconds).round().clamp(
          1,
          100000,
        );

    onTick(0.0);
    await _pumpAndCapture();

    for (var i = 1; i <= totalFrames; i++) {
      final progress = (i / totalFrames).clamp(0.0, 1.0);
      onTick(progress);
      await _pumpAndCapture();
    }
  }
}
