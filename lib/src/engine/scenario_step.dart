import 'package:flutter/material.dart';

/// 기본 강조/포인터 테마 컬러
const Color kDefaultScenarioAccentColor = Color(0xFF46D3C2);

/// 시나리오에서 강조하거나 조작할 타겟 위젯을 식별하는 매처
class ScenarioTargetMatcher {
  final String description;
  final bool Function(Element element) matches;
  final int index;
  final bool expandToInteractiveAncestor;

  const ScenarioTargetMatcher._({
    required this.description,
    required this.matches,
    this.index = 0,
    this.expandToInteractiveAncestor = true,
  });

  /// `Key`로 타겟 위젯 매칭
  factory ScenarioTargetMatcher.byKey(
    Key key, {
    bool expandToInteractiveAncestor = false,
  }) {
    return ScenarioTargetMatcher._(
      description: 'Key($key)',
      matches: (element) => element.widget.key == key,
      expandToInteractiveAncestor: expandToInteractiveAncestor,
    );
  }

  /// 화면에 표시되는 텍스트(정확히 일치 또는 포함)로 타겟 매칭
  factory ScenarioTargetMatcher.byText(
    String text, {
    bool contains = false,
    int index = 0,
    bool expandToInteractiveAncestor = true,
  }) {
    return ScenarioTargetMatcher._(
      description: contains ? 'TextContaining("$text")' : 'Text("$text")',
      index: index,
      expandToInteractiveAncestor: expandToInteractiveAncestor,
      matches: (element) {
        final widget = element.widget;
        if (widget is Text) {
          final data = widget.data ?? widget.textSpan?.toPlainText();
          if (data == null) return false;
          return contains ? data.contains(text) : data == text;
        }
        if (widget is RichText) {
          final plain = widget.text.toPlainText();
          return contains ? plain.contains(text) : plain == text;
        }
        return false;
      },
    );
  }

  /// 위젯 런타임 타입(`Type`)으로 타겟 매칭
  factory ScenarioTargetMatcher.byType(
    Type widgetType, {
    int index = 0,
    bool expandToInteractiveAncestor = false,
  }) {
    return ScenarioTargetMatcher._(
      description: 'Type($widgetType#$index)',
      index: index,
      expandToInteractiveAncestor: expandToInteractiveAncestor,
      matches: (element) => element.widget.runtimeType == widgetType,
    );
  }

  /// 사용자 정의 조건(`predicate`)으로 타겟 매칭
  factory ScenarioTargetMatcher.byPredicate(
    bool Function(Element element) predicate, {
    String description = 'CustomPredicate',
    int index = 0,
    bool expandToInteractiveAncestor = false,
  }) {
    return ScenarioTargetMatcher._(
      description: description,
      index: index,
      expandToInteractiveAncestor: expandToInteractiveAncestor,
      matches: predicate,
    );
  }

  /// `TextField` / `InputDecorator`의 `hintText`로 입력 필드 매칭
  factory ScenarioTargetMatcher.byHintText(
    String hintText, {
    int index = 0,
    bool expandToInteractiveAncestor = false,
  }) {
    return ScenarioTargetMatcher._(
      description: 'HintText("$hintText"#$index)',
      index: index,
      expandToInteractiveAncestor: expandToInteractiveAncestor,
      matches: (element) {
        final widget = element.widget;
        if (widget is TextField) {
          return widget.decoration?.hintText == hintText;
        }
        return false;
      },
    );
  }
}

/// 타겟 위젯 강조(Border, Elevation Glow, Pulse, Dimming) 스타일 설정
class HighlightStyle {
  final Color borderColor;
  final Color glowColor;
  final double borderWidth;
  final double borderRadius;
  final double elevationBlur;
  final double pulseScale;
  final EdgeInsets padding;
  final bool dimBackground;
  final Color dimColor;

  const HighlightStyle({
    this.borderColor = kDefaultScenarioAccentColor,
    this.glowColor = const Color(0x99FF5A5F),
    this.borderWidth = 3.0,
    this.borderRadius = 12.0,
    this.elevationBlur = 14.0,
    this.pulseScale = 0.04,
    this.padding = const EdgeInsets.all(4),
    this.dimBackground = false,
    this.dimColor = const Color(0x33000000),
  });

  /// 기본 펄스 + Elevation Glow 강조 스타일
  const HighlightStyle.elevatedPulse({
    this.borderColor = kDefaultScenarioAccentColor,
    this.glowColor = const Color(0xAAFF5A5F),
    this.borderWidth = 3.0,
    this.borderRadius = 12.0,
    this.elevationBlur = 16.0,
    this.pulseScale = 0.045,
    this.padding = const EdgeInsets.all(4),
    this.dimBackground = false,
    this.dimColor = const Color(0x33000000),
  });

  /// 주변 배경을 어둡게 낮추고 타겟 버튼에 시선을 집중시키는 스포트라이트 스타일
  const HighlightStyle.spotlight({
    this.borderColor = kDefaultScenarioAccentColor,
    this.glowColor = const Color(0xCCFF5A5F),
    this.borderWidth = 3.0,
    this.borderRadius = 12.0,
    this.elevationBlur = 20.0,
    this.pulseScale = 0.05,
    this.padding = const EdgeInsets.all(6),
    this.dimBackground = true,
    this.dimColor = const Color(0x44000000),
  });
}

/// 시나리오를 구성하는 단위 액션 Step (Sealed DSL)
sealed class ScenarioStep {
  final String? label;
  const ScenarioStep({this.label});
}

/// 1. 지정된 시간만큼 대기
class WaitStep extends ScenarioStep {
  final Duration duration;

  const WaitStep(this.duration, {super.label});
}

/// 2. 타겟 위젯을 찾아 강조(Border + Elevation Glow + Pulse)만 수행
class HighlightStep extends ScenarioStep {
  final ScenarioTargetMatcher target;
  final Duration duration;
  final HighlightStyle style;

  const HighlightStep(
    this.target, {
    this.duration = const Duration(milliseconds: 800),
    this.style = const HighlightStyle.elevatedPulse(),
    super.label,
  });
}

/// 3. 타겟 위젯을 강조한 뒤 가상 포인터가 이동하여 탭(Tap) 수행
class HighlightAndTapStep extends ScenarioStep {
  final ScenarioTargetMatcher target;
  final Duration highlightDuration;
  final Duration pointerMoveDuration;
  final Duration tapHoldDuration;
  final Duration postTapDelay;
  final HighlightStyle style;

  const HighlightAndTapStep(
    this.target, {
    this.highlightDuration = const Duration(milliseconds: 750),
    this.pointerMoveDuration = const Duration(milliseconds: 350),
    this.tapHoldDuration = const Duration(milliseconds: 110),
    this.postTapDelay = const Duration(milliseconds: 450),
    this.style = const HighlightStyle.elevatedPulse(),
    super.label,
  });
}

/// 4. 타겟 위젯이 화면 안에 들어올 때까지 부드럽게 스크롤
class ScrollUntilVisibleStep extends ScenarioStep {
  final ScenarioTargetMatcher target;
  final double alignment;
  final Duration duration;
  final double dragDeltaPerAttempt;
  final int maxAttempts;

  const ScrollUntilVisibleStep(
    this.target, {
    this.alignment = 0.35,
    this.duration = const Duration(milliseconds: 500),
    this.dragDeltaPerAttempt = -240,
    this.maxAttempts = 8,
    super.label,
  });
}

/// 5. 텍스트 입력 필드를 강조·탭한 뒤 한 글자씩 타이핑
class TypeTextStep extends ScenarioStep {
  final ScenarioTargetMatcher target;
  final String text;
  final Duration highlightDuration;
  final Duration charInterval;
  final bool unfocusAfterTyping;
  final HighlightStyle style;

  const TypeTextStep(
    this.target,
    this.text, {
    this.highlightDuration = const Duration(milliseconds: 500),
    this.charInterval = const Duration(milliseconds: 65),
    this.unfocusAfterTyping = true,
    this.style = const HighlightStyle.elevatedPulse(),
    super.label,
  });
}

/// 6. 커스텀 비동기 액션 수행 (상태 직접 조작이나 검증 등에 활용)
class CustomActionStep extends ScenarioStep {
  final Future<void> Function(BuildContext stageContext) action;

  const CustomActionStep(this.action, {super.label});
}
