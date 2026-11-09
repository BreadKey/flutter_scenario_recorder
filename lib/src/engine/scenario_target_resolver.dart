import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/src/engine/scenario_step.dart';

/// 매칭된 타겟 요소와 스테이지 기준 좌표(`Rect`) 결과
class ResolvedScenarioTarget {
  /// 매처가 직접 찾은 원본 `Element`
  final Element matchedElement;

  /// 강조(Highlight) 및 터치의 기준이 되는 `Element` (버튼 조상으로 확장된 경우 조상 Element)
  final Element interactiveElement;

  /// 스테이지 루트(`ScenarioStage`) 기준 로컬 `Rect`
  final Rect rectInStage;

  /// 글로벌 화면(`Overlay`/포인터 주입) 기준 `Rect`
  final Rect globalRect;

  const ResolvedScenarioTarget({
    required this.matchedElement,
    required this.interactiveElement,
    required this.rectInStage,
    required this.globalRect,
  });

  Offset get globalCenter => globalRect.center;
  Offset get stageCenter => rectInStage.center;
}

/// 위젯 트리에서 `ScenarioTargetMatcher`에 해당하는 요소를 탐색하고 좌표를 계산하는 리졸버
class ScenarioTargetResolver {
  /// 앱별 커스텀 버튼/입력 위젯을 추가로 인터랙티브 조상으로 인식할 때 사용하는 선택적 콜백
  final bool Function(Widget widget)? customInteractivePredicate;

  const ScenarioTargetResolver({this.customInteractivePredicate});

  /// 스테이지 루트 `BuildContext` 하위에서 매처에 일치하는 타겟을 탐색한다.
  ResolvedScenarioTarget? resolve(
    BuildContext stageContext,
    ScenarioTargetMatcher matcher,
  ) {
    if (!stageContext.mounted) return null;

    final stageRenderObject = stageContext.findRenderObject();
    if (stageRenderObject is! RenderBox || !stageRenderObject.hasSize) {
      return null;
    }

    final candidates = <Element>[];

    void visit(Element element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) {
        return;
      }
      if (widget is Visibility && !widget.visible) {
        return;
      }

      if (matcher.matches(element)) {
        final renderObject = element.renderObject;
        if (renderObject is RenderBox &&
            renderObject.attached &&
            renderObject.hasSize &&
            !renderObject.size.isEmpty) {
          candidates.add(element);
        }
      }

      element.visitChildren(visit);
    }

    stageContext.visitChildElements(visit);

    if (candidates.length <= matcher.index) {
      return null;
    }

    final matchedElement = candidates[matcher.index];
    final interactiveElement = matcher.expandToInteractiveAncestor
        ? _findInteractiveAncestor(matchedElement) ?? matchedElement
        : matchedElement;

    final targetRenderBox = interactiveElement.renderObject;
    if (targetRenderBox is! RenderBox ||
        !targetRenderBox.attached ||
        !targetRenderBox.hasSize) {
      return null;
    }

    final stageTopLeft = targetRenderBox.localToGlobal(
      Offset.zero,
      ancestor: stageRenderObject,
    );
    final globalTopLeft = targetRenderBox.localToGlobal(Offset.zero);

    return ResolvedScenarioTarget(
      matchedElement: matchedElement,
      interactiveElement: interactiveElement,
      rectInStage: stageTopLeft & targetRenderBox.size,
      globalRect: globalTopLeft & targetRenderBox.size,
    );
  }

  /// 타겟 요소(또는 하위 서브트리)에서 `EditableTextState`를 찾는다.
  EditableTextState? findEditableTextState(Element rootElement) {
    EditableTextState? found;

    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    visit(rootElement);
    return found;
  }

  /// 텍스트 등 내부 자식 위젯이 매칭된 경우, 가장 가까운 인터랙티브 버튼/입력 조상 Element로 확장한다.
  Element? _findInteractiveAncestor(Element startElement) {
    Element? result;
    startElement.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (_isInteractiveWidget(widget)) {
        final renderObject = ancestor.renderObject;
        if (renderObject is RenderBox &&
            renderObject.attached &&
            renderObject.hasSize &&
            !renderObject.size.isEmpty) {
          result = ancestor;
          return false;
        }
      }
      return true;
    });
    return result;
  }

  bool _isInteractiveWidget(Widget widget) {
    if (customInteractivePredicate?.call(widget) == true) {
      return true;
    }
    final typeName = widget.runtimeType.toString();
    return widget is ButtonStyleButton ||
        widget is MaterialButton ||
        widget is IconButton ||
        widget is InkResponse ||
        widget is InkWell ||
        widget is Tab ||
        widget is NavigationDestination ||
        widget is TextField ||
        widget is TextFormField ||
        widget is CupertinoButtonLike ||
        typeName == 'SelectButton' ||
        typeName == 'InquiryItemButton' ||
        typeName.startsWith('WithdicalTextFormInput') ||
        typeName.startsWith('WithdicalMultiTextInput') ||
        typeName.startsWith('WithdicalTextInput') ||
        (widget is GestureDetector &&
            (widget.onTap != null || widget.onTapDown != null));
  }
}

/// 타입 체크 보조용 마커 인터페이스 (필요 시 커스텀 버튼에서 구현 가능)
abstract interface class CupertinoButtonLike {}
