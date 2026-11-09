# flutter_scenario_recorder

Flutter 앱의 사용자 시나리오(버튼 강조, 가상 손가락 터치/리플, 부드러운 스크롤, 글자 단위 타이핑)를 선언적 DSL(`ScenarioStep`)로 정의하고, **프레임 드랍 0%의 결정론적(Deterministic) 고화질 MP4 영상**으로 렌더링하는 패키지입니다.

코딩 에이전트(Cursor 등)가 바로 사용할 수 있는 Agent Skill([`skills/flutter-scenario-video/SKILL.md`](skills/flutter-scenario-video/SKILL.md))과 CLI 렌더러(`dart run flutter_scenario_recorder:render_video`)를 함께 포함합니다.

---

## 예제 비디오 (뷰즈 앱 상담 예약 시나리오)

<video src="example/consultation_scenario.mp4" width="360" controls></video>

- 예제 영상 파일: [`example/consultation_scenario.mp4`](example/consultation_scenario.mp4) (`786x1704`, `30fps`, H.264 `yuv420p`)

---

## 주요 기능

1. **선언적 시나리오 DSL (`ScenarioStep`)**
   - `WaitStep`: 지정된 시간 대기
   - `HighlightStep`: 타겟 위젯 주변에 Pulse Border, Elevation Glow, 선택적 Spotlight 배경 디밍 표시
   - `HighlightAndTapStep`: 타겟 위젯을 강조한 뒤 가상 터치 포인터가 이동하여 실제 포인터 이벤트(`PointerDown` -> `PointerUp`) 및 리플 발생
   - `ScrollUntilVisibleStep`: 타겟이 화면에 노출될 때까지 `Scrollable.ensureVisible` 또는 드래그 스크롤 수행
   - `TypeTextStep`: 입력 필드를 탭해 포커스한 뒤 한 글자씩 타이핑 연출
2. **듀얼 실행 모드**
   - **Preview 모드**: 시뮬레이터/디바이스에서 실시간으로 시나리오와 오버레이를 확인하며 우측 상단 컨트롤 바(`Replay` / `Stop` / `Rec MP4`)로 제어
   - **Deterministic 헤드리스 렌더링 모드**: `WidgetTester` 가상 시계를 정확히 `1/fps`초씩 전진시키며 `RepaintBoundary.toImage()`의 `rawRgba` 바이트를 `ffmpeg` `stdin`으로 직접 파이핑
3. **macOS `Apple Color Emoji` & 클린 레이아웃 CLI (`render_video`)**
   - `flutter_tester`의 `--use-test-fonts`, `--disable-asset-fonts`, `--enable-checked-mode` 제약을 자동으로 해제하여 macOS 시스템 컬러 이모지를 그대로 렌더링하고 디버그 오버플로우 스트라이프를 숨깁니다.

---

## 설치 및 빠른 시작

### 1. `pubspec.yaml` 의존성 추가

```yaml
dependencies:
  flutter_scenario_recorder:
    git:
      url: git@github.com:BreadKey/flutter_scenario_recorder.git
```
*(로컬 경로로 연결할 경우 `path: /Users/breadkey/dev/project/flutter_scenario_recorder`)*

### 2. `ScenarioStage`로 앱 감싸기

```dart
import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/flutter_scenario_recorder.dart';

final captureBoundaryKey = GlobalKey();
final scenarioRunner = ScenarioRunner();

final steps = <ScenarioStep>[
  const WaitStep(Duration(milliseconds: 800)),
  HighlightAndTapStep(
    ScenarioTargetMatcher.byText('상담 예약하기'),
    style: const HighlightStyle.spotlight(),
  ),
];

void main() {
  runApp(
    ScenarioStage(
      captureBoundaryKey: captureBoundaryKey,
      runner: scenarioRunner,
      steps: steps,
      child: const MyApp(),
    ),
  );
}
```

### 3. 결정론적 MP4 영상 추출 실행

```bash
dart run flutter_scenario_recorder:render_video test/scenario/render_consultation_video_test.dart
```

---

## 코딩 에이전트 스킬 (Cursor Agent Skill)

이 패키지는 코딩 에이전트가 자율적으로 시나리오를 설계하고 MP4 영상을 생성·검수할 수 있도록 [`skills/flutter-scenario-video/SKILL.md`](skills/flutter-scenario-video/SKILL.md) 스킬 문서를 포함합니다.

글로벌 Cursor 스킬로 등록하려면 아래 경로에 복사합니다:

```bash
mkdir -p ~/.cursor/skills/flutter-scenario-video
cp skills/flutter-scenario-video/SKILL.md ~/.cursor/skills/flutter-scenario-video/SKILL.md
```
