import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/src/engine/scenario_step.dart';
import 'package:flutter_scenario_recorder/src/engine/scenario_target_resolver.dart';

/// 시나리오 진행 시간 제어 인터페이스
/// - Preview 모드에서는 실제 시간(`Future.delayed`)으로 동작
/// - 테스트/렌더링 모드에서는 프레임 캡처 펌프 루프와 연동 가능
abstract class ScenarioClock {
  const ScenarioClock();

  Future<void> delay(Duration duration);

  /// `duration` 동안 `0.0 -> 1.0` 진행률을 매 프레임 콜백으로 전달
  Future<void> animate(
    Duration duration,
    void Function(double progress) onTick, {
    int fps = 60,
  });
}

/// 실시간 프리뷰용 기본 `ScenarioClock`
class RealTimeScenarioClock extends ScenarioClock {
  const RealTimeScenarioClock();

  @override
  Future<void> delay(Duration duration) async {
    if (duration <= Duration.zero) return;
    await Future<void>.delayed(duration);
  }

  @override
  Future<void> animate(
    Duration duration,
    void Function(double progress) onTick, {
    int fps = 60,
  }) async {
    if (duration <= Duration.zero) {
      onTick(1.0);
      return;
    }

    final totalMicros = duration.inMicroseconds;
    final frameDuration = Duration(microseconds: (1000000 / fps).round());
    final stopwatch = Stopwatch()..start();

    onTick(0.0);
    while (stopwatch.elapsedMicroseconds < totalMicros) {
      await Future<void>.delayed(frameDuration);
      final progress = (stopwatch.elapsedMicroseconds / totalMicros).clamp(
        0.0,
        1.0,
      );
      onTick(progress);
    }
    onTick(1.0);
  }
}

/// 시나리오 실행 상태와 오버레이 렌더링 데이터를 관리하는 컨트롤러
class ScenarioRunner extends ChangeNotifier {
  final ScenarioTargetResolver _resolver;
  final ScenarioClock _clock;

  BuildContext? _stageContext;
  bool _isRunning = false;
  int _runGeneration = 0;
  int _nextPointerId = 900;

  /// 현재 진행 중인 스텝 인덱스 및 설명
  int _currentStepIndex = -1;
  String? _currentStepLabel;

  /// 강조(Highlight) 오버레이 상태
  Rect? _activeHighlightRect;
  HighlightStyle _highlightStyle = const HighlightStyle.elevatedPulse();
  double _highlightPulsePhase = 0.0;
  double _highlightOpacity = 0.0;

  /// 가상 터치 포인터 상태
  Offset? _pointerPosition;
  bool _isPointerDown = false;
  double _tapRippleProgress = 0.0;

  ScenarioRunner({
    ScenarioTargetResolver resolver = const ScenarioTargetResolver(),
    ScenarioClock clock = const RealTimeScenarioClock(),
  }) : _resolver = resolver,
       _clock = clock;

  bool get isRunning => _isRunning;
  int get currentStepIndex => _currentStepIndex;
  String? get currentStepLabel => _currentStepLabel;

  Rect? get activeHighlightRect => _activeHighlightRect;
  HighlightStyle get highlightStyle => _highlightStyle;
  double get highlightPulsePhase => _highlightPulsePhase;
  double get highlightOpacity => _highlightOpacity;

  Offset? get pointerPosition => _pointerPosition;
  bool get isPointerDown => _isPointerDown;
  double get tapRippleProgress => _tapRippleProgress;

  /// `ScenarioStage`가 마운트될 때 루트 `BuildContext`를 연결한다.
  void attachStageContext(BuildContext context) {
    _stageContext = context;
  }

  void detachStageContext(BuildContext context) {
    if (_stageContext == context) {
      _stageContext = null;
    }
  }

  /// 진행 중인 시나리오를 중단하고 오버레이 상태를 초기화한다.
  void stop() {
    _runGeneration++;
    _isRunning = false;
    _currentStepIndex = -1;
    _currentStepLabel = null;
    _clearHighlight();
    _pointerPosition = null;
    _isPointerDown = false;
    _tapRippleProgress = 0.0;
    notifyListeners();
  }

  /// 정의된 `ScenarioStep` 리스트를 순차적으로 재생한다.
  Future<void> run(List<ScenarioStep> steps) async {
    final generation = ++_runGeneration;
    _isRunning = true;
    notifyListeners();

    try {
      for (var i = 0; i < steps.length; i++) {
        if (!_isActiveGeneration(generation)) return;

        final step = steps[i];
        _currentStepIndex = i;
        _currentStepLabel = step.label ?? _defaultStepLabel(step);
        debugPrint(
          '[ScenarioRunner] Step ${i + 1}/${steps.length}: $_currentStepLabel',
        );
        notifyListeners();

        await _executeStep(step, generation);
      }
    } finally {
      if (_isActiveGeneration(generation)) {
        _isRunning = false;
        _currentStepLabel = null;
        _clearHighlight();
        notifyListeners();
      }
    }
  }

  bool _isActiveGeneration(int generation) =>
      _isRunning && _runGeneration == generation && _stageContext != null;

  String _defaultStepLabel(ScenarioStep step) {
    return switch (step) {
      WaitStep(:final duration) => 'Wait (${duration.inMilliseconds}ms)',
      HighlightStep(:final target) => 'Highlight ${target.description}',
      HighlightAndTapStep(:final target) => 'Tap ${target.description}',
      ScrollUntilVisibleStep(:final target) => 'Scroll to ${target.description}',
      TypeTextStep(:final text) => 'Type "$text"',
      CustomActionStep() => 'Custom Action',
    };
  }

  Future<void> _executeStep(ScenarioStep step, int generation) async {
    switch (step) {
      case WaitStep():
        await _clock.delay(step.duration);

      case HighlightStep():
        await _runHighlight(
          matcher: step.target,
          duration: step.duration,
          style: step.style,
          generation: generation,
        );
        _clearHighlight();
        notifyListeners();

      case HighlightAndTapStep():
        await _runHighlightAndTap(step, generation);

      case ScrollUntilVisibleStep():
        await _runScrollUntilVisible(step, generation);

      case TypeTextStep():
        await _runTypeText(step, generation);

      case CustomActionStep():
        final ctx = _stageContext;
        if (ctx != null && ctx.mounted) {
          await step.action(ctx);
        }
    }
  }

  Future<ResolvedScenarioTarget?> _waitForTarget(
    ScenarioTargetMatcher matcher,
    int generation, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    const pollInterval = Duration(milliseconds: 50);
    final maxTries = math.max(
      1,
      (timeout.inMilliseconds / pollInterval.inMilliseconds).round(),
    );

    for (var i = 0; i < maxTries; i++) {
      if (!_isActiveGeneration(generation)) return null;
      final ctx = _stageContext;
      if (ctx != null && ctx.mounted) {
        final resolved = _resolver.resolve(ctx, matcher);
        if (resolved != null) {
          return resolved;
        }
      }
      await _clock.delay(pollInterval);
    }
    debugPrint('[ScenarioRunner] Target not found: ${matcher.description}');
    return null;
  }

  Future<ResolvedScenarioTarget?> _runHighlight({
    required ScenarioTargetMatcher matcher,
    required Duration duration,
    required HighlightStyle style,
    required int generation,
  }) async {
    final resolved = await _waitForTarget(matcher, generation);
    if (resolved == null || !_isActiveGeneration(generation)) return null;

    _highlightStyle = style;
    _activeHighlightRect = resolved.rectInStage;

    await _clock.animate(duration, (progress) {
      if (!_isActiveGeneration(generation)) return;

      final ctx = _stageContext;
      if (ctx != null && ctx.mounted) {
        final updated = _resolver.resolve(ctx, matcher);
        if (updated != null) {
          _activeHighlightRect = updated.rectInStage;
        }
      }

      final fadeIn = (progress / 0.2).clamp(0.0, 1.0);
      _highlightOpacity = fadeIn;
      _highlightPulsePhase = math.sin(progress * math.pi * 2).abs();
      notifyListeners();
    });

    return _stageContext != null
        ? _resolver.resolve(_stageContext!, matcher) ?? resolved
        : resolved;
  }

  Future<void> _runHighlightAndTap(
    HighlightAndTapStep step,
    int generation,
  ) async {
    final resolved = await _waitForTarget(step.target, generation);
    if (resolved == null || !_isActiveGeneration(generation)) return;

    final startPointer =
        _pointerPosition ??
        Offset(
          resolved.rectInStage.center.dx,
          resolved.rectInStage.bottom + 72,
        );

    _highlightStyle = step.style;
    _activeHighlightRect = resolved.rectInStage;

    final totalHighlightMs = math.max(
      step.highlightDuration.inMilliseconds,
      step.pointerMoveDuration.inMilliseconds,
    );
    final moveRatio = totalHighlightMs > 0
        ? (step.pointerMoveDuration.inMilliseconds / totalHighlightMs).clamp(
            0.1,
            1.0,
          )
        : 1.0;

    await _clock.animate(Duration(milliseconds: totalHighlightMs), (progress) {
      if (!_isActiveGeneration(generation)) return;

      final ctx = _stageContext;
      ResolvedScenarioTarget currentTarget = resolved;
      if (ctx != null && ctx.mounted) {
        currentTarget = _resolver.resolve(ctx, step.target) ?? resolved;
        _activeHighlightRect = currentTarget.rectInStage;
      }

      final moveProgress = Curves.easeOutCubic.transform(
        (progress / moveRatio).clamp(0.0, 1.0),
      );
      _pointerPosition = Offset.lerp(
        startPointer,
        currentTarget.stageCenter,
        moveProgress,
      );

      _highlightOpacity = (progress / 0.18).clamp(0.0, 1.0);
      _highlightPulsePhase = math.sin(progress * math.pi * 2).abs();
      notifyListeners();
    });

    if (!_isActiveGeneration(generation)) return;

    final finalTarget =
        (_stageContext != null
            ? _resolver.resolve(_stageContext!, step.target)
            : null) ??
        resolved;
    _activeHighlightRect = finalTarget.rectInStage;
    _pointerPosition = finalTarget.stageCenter;

    final pointerId = _nextPointerId++;
    final globalTapPos = finalTarget.globalCenter;

    _isPointerDown = true;
    _tapRippleProgress = 0.0;
    notifyListeners();

    WidgetsBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: pointerId, position: globalTapPos),
    );

    await _clock.animate(step.tapHoldDuration, (progress) {
      if (!_isActiveGeneration(generation)) return;
      _tapRippleProgress = progress;
      notifyListeners();
    });

    WidgetsBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: pointerId, position: globalTapPos),
    );

    _isPointerDown = false;
    await _clock.animate(const Duration(milliseconds: 180), (progress) {
      if (!_isActiveGeneration(generation)) return;
      _tapRippleProgress = progress;
      _highlightOpacity = 1.0 - progress;
      notifyListeners();
    });

    _clearHighlight();
    notifyListeners();

    await _clock.delay(step.postTapDelay);
  }

  Future<void> _runScrollUntilVisible(
    ScrollUntilVisibleStep step,
    int generation,
  ) async {
    for (var attempt = 0; attempt < step.maxAttempts; attempt++) {
      if (!_isActiveGeneration(generation)) return;
      final ctx = _stageContext;
      if (ctx == null || !ctx.mounted) return;

      final resolved = _resolver.resolve(ctx, step.target);
      if (resolved != null) {
        unawaited(
          Scrollable.ensureVisible(
            resolved.interactiveElement,
            alignment: step.alignment,
            duration: step.duration,
            curve: Curves.easeInOutCubic,
          ),
        );
        await _clock.animate(
          step.duration + const Duration(milliseconds: 100),
          (_) {},
        );
        return;
      }

      final stageBox = ctx.findRenderObject() as RenderBox?;
      if (stageBox == null || !stageBox.hasSize) return;

      final centerInStage = stageBox.size.center(Offset.zero);
      final centerGlobal = stageBox.localToGlobal(centerInStage);
      await _performDrag(
        startInStage: centerInStage,
        startGlobal: centerGlobal,
        delta: Offset(0, step.dragDeltaPerAttempt),
        duration: const Duration(milliseconds: 320),
        generation: generation,
      );
      await _clock.delay(const Duration(milliseconds: 120));
    }
  }

  Future<void> _performDrag({
    required Offset startInStage,
    required Offset startGlobal,
    required Offset delta,
    required Duration duration,
    required int generation,
  }) async {
    final pointerId = _nextPointerId++;
    _pointerPosition = startInStage;
    _isPointerDown = true;
    notifyListeners();

    WidgetsBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: pointerId, position: startGlobal),
    );

    var previousOffset = Offset.zero;
    await _clock.animate(duration, (progress) {
      if (!_isActiveGeneration(generation)) return;
      final curved = Curves.easeInOutCubic.transform(progress);
      final currentOffset = delta * curved;
      final stepDelta = currentOffset - previousOffset;
      previousOffset = currentOffset;

      _pointerPosition = startInStage + currentOffset;
      WidgetsBinding.instance.handlePointerEvent(
        PointerMoveEvent(
          pointer: pointerId,
          position: startGlobal + currentOffset,
          delta: stepDelta,
        ),
      );
      notifyListeners();
    });

    WidgetsBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: pointerId, position: startGlobal + delta),
    );
    _isPointerDown = false;
    notifyListeners();
  }

  Future<void> _runTypeText(TypeTextStep step, int generation) async {
    await _runHighlightAndTap(
      HighlightAndTapStep(
        step.target,
        highlightDuration: step.highlightDuration,
        postTapDelay: const Duration(milliseconds: 200),
        style: step.style,
      ),
      generation,
    );

    if (!_isActiveGeneration(generation)) return;
    final ctx = _stageContext;
    if (ctx == null || !ctx.mounted) return;

    final resolved = _resolver.resolve(ctx, step.target);
    if (resolved == null) return;

    final editableState =
        _resolver.findEditableTextState(resolved.interactiveElement) ??
        _resolver.findEditableTextState(resolved.matchedElement);
    if (editableState == null) {
      debugPrint(
        '[ScenarioRunner] EditableTextState not found for ${step.target.description}',
      );
      return;
    }

    editableState.requestKeyboard();
    for (var i = 1; i <= step.text.length; i++) {
      if (!_isActiveGeneration(generation)) return;
      final partial = step.text.substring(0, i);
      editableState.userUpdateTextEditingValue(
        TextEditingValue(
          text: partial,
          selection: TextSelection.collapsed(offset: partial.length),
        ),
        SelectionChangedCause.keyboard,
      );
      await _clock.delay(step.charInterval);
    }

    if (step.unfocusAfterTyping) {
      FocusManager.instance.primaryFocus?.unfocus();
      await _clock.delay(const Duration(milliseconds: 150));
    }
  }

  void _clearHighlight() {
    _activeHighlightRect = null;
    _highlightPulsePhase = 0.0;
    _highlightOpacity = 0.0;
  }
}
