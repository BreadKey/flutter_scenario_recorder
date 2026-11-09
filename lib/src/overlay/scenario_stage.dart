import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/src/engine/frame_recorder.dart';
import 'package:flutter_scenario_recorder/src/engine/scenario_runner.dart';
import 'package:flutter_scenario_recorder/src/engine/scenario_step.dart';
import 'package:flutter_scenario_recorder/src/overlay/highlight_painter.dart';
import 'package:flutter_scenario_recorder/src/overlay/touch_pointer_indicator.dart';

/// 프레임 캡처용 `RepaintBoundary`와 강조/터치 포인터 오버레이를 결합하는 최상단 스테이지 위젯
class ScenarioStage extends StatefulWidget {
  /// 영상 프레임 추출 시 사용할 `RepaintBoundary` GlobalKey
  final GlobalKey captureBoundaryKey;

  /// 시나리오 실행기
  final ScenarioRunner runner;

  /// 선택적 프레임 레코더 (연결 시 `Rec` 버튼 및 자동 녹화 지원)
  final ScenarioFrameRecorder? recorder;

  /// 자동 실행하거나 재시작할 기본 시나리오 스텝 목록
  final List<ScenarioStep> steps;

  /// 마운트 직후 자동으로 시나리오를 재생할지 여부
  final bool autoStart;

  /// 프리뷰 디버깅용 상단 플로팅 컨트롤 바 표시 여부 (렌더링 캡처 시 `false`)
  final bool showPreviewControls;

  /// 강조/컨트롤바 기본 포인트 컬러
  final Color accentColor;

  /// 감쌀 대상 앱 위젯
  final Widget child;

  const ScenarioStage({
    super.key,
    required this.captureBoundaryKey,
    required this.runner,
    required this.steps,
    required this.child,
    this.recorder,
    this.autoStart = true,
    this.showPreviewControls = true,
    this.accentColor = kDefaultScenarioAccentColor,
  });

  @override
  State<ScenarioStage> createState() => _ScenarioStageState();
}

class _ScenarioStageState extends State<ScenarioStage> {
  final GlobalKey _stageContentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachContext();
      if (widget.autoStart && widget.steps.isNotEmpty) {
        widget.runner.run(widget.steps);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ScenarioStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachContext();
    });
  }

  void _attachContext() {
    final ctx = _stageContentKey.currentContext;
    if (ctx != null && ctx.mounted) {
      widget.runner.attachStageContext(ctx);
    }
  }

  @override
  void dispose() {
    final ctx = _stageContentKey.currentContext;
    if (ctx != null) {
      widget.runner.detachStageContext(ctx);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            key: widget.captureBoundaryKey,
            child: Stack(
              key: _stageContentKey,
              fit: StackFit.expand,
              children: [
                widget.child,
                ListenableBuilder(
                  listenable: widget.runner,
                  builder: (context, _) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        IgnorePointer(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: ScenarioHighlightPainter(
                              targetRect: widget.runner.activeHighlightRect,
                              style: widget.runner.highlightStyle,
                              pulsePhase: widget.runner.highlightPulsePhase,
                              opacity: widget.runner.highlightOpacity,
                            ),
                          ),
                        ),
                        TouchPointerIndicator(
                          position: widget.runner.pointerPosition,
                          isDown: widget.runner.isPointerDown,
                          rippleProgress: widget.runner.tapRippleProgress,
                          color: widget.accentColor,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          if (widget.showPreviewControls)
            Positioned(
              top: 52,
              right: 12,
              child: _ScenarioPreviewControlBar(
                runner: widget.runner,
                recorder: widget.recorder,
                steps: widget.steps,
                accentColor: widget.accentColor,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScenarioPreviewControlBar extends StatelessWidget {
  final ScenarioRunner runner;
  final ScenarioFrameRecorder? recorder;
  final List<ScenarioStep> steps;
  final Color accentColor;

  const _ScenarioPreviewControlBar({
    required this.runner,
    required this.recorder,
    required this.steps,
    required this.accentColor,
  });

  Future<void> _runWithRecording() async {
    final rec = recorder;
    if (rec == null || rec.isRecording || rec.isEncoding) return;

    runner.stop();
    await rec.startSession();
    try {
      await runner.run(steps);
    } finally {
      await rec.finishSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[runner, ?recorder];

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final isRunning = runner.isRunning;
        final isRecording = recorder?.isRecording ?? false;
        final isEncoding = recorder?.isEncoding ?? false;
        final label =
            recorder?.statusMessage ??
            runner.currentStepLabel ??
            (isRunning ? 'Playing...' : 'Scenario Idle');

        return Material(
          color: const Color(0xCC1E1E1E),
          borderRadius: BorderRadius.circular(20),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRecording
                        ? Colors.redAccent
                        : isRunning
                        ? accentColor
                        : Colors.grey,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 165),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: isEncoding
                      ? null
                      : () {
                          if (isRunning) {
                            runner.stop();
                          } else {
                            runner.run(steps);
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isRunning ? 'Stop' : 'Replay',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (recorder != null && !isRunning && !isEncoding)
                  GestureDetector(
                    onTap: _runWithRecording,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Rec MP4',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
