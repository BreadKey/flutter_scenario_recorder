# flutter_scenario_recorder

Declarative UI scenario automation, interactive highlight/touch overlays, and **frame-accurate, zero-frame-drop FFmpeg MP4 video rendering** for Flutter apps.

Ships with a ready-to-use **Cursor Agent Skill** ([`skills/flutter-scenario-video/SKILL.md`](skills/flutter-scenario-video/SKILL.md)) and a built-in CLI renderer (`dart run flutter_scenario_recorder:render_video`) so coding agents can autonomously script user journeys and export production-ready demo/tutorial videos.

---

## Preview Demo

[![Scenario Preview](example/preview.gif)](example/consultation_scenario.mp4)

- **Inline Preview**: [`example/preview.gif`](example/preview.gif) (2x speed preview)
- **Full MP4 Video**: [`example/consultation_scenario.mp4`](example/consultation_scenario.mp4) (`524x1136`, `30fps`, H.264 `yuv420p`, `1.6 MB`)

---

## Features

1. **Declarative Scenario DSL (`ScenarioStep`)**
   - `WaitStep`: Pause for a specific duration.
   - `HighlightStep`: Draw an animated pulse border, elevation glow, and optional spotlight dimming around a target widget.
   - `HighlightAndTapStep`: Highlight a target widget, smoothly move a virtual finger pointer to its center, and dispatch real Flutter pointer events (`PointerDownEvent` -> `PointerUpEvent`) with ripple animation.
   - `ScrollUntilVisibleStep`: Smoothly scroll via `Scrollable.ensureVisible` or pointer drag gestures until the target widget enters the viewport.
   - `TypeTextStep`: Focus an input field and type text character-by-character.
   - `CustomActionStep`: Execute custom async logic against the live `BuildContext`.
2. **Flexible Target Resolution (`ScenarioTargetMatcher`)**
   - Match widgets by `Key` (`byKey`), visible text (`byText`), `TextField` `hintText` (`byHintText`), runtime `Type` (`byType`), or custom predicate (`byPredicate`).
   - Automatically expands child text matches to their nearest interactive button/input ancestor so borders wrap the full button.
3. **Dual Execution Modes**
   - **Real-Time Preview Mode**: Run on an iOS Simulator, Android Emulator, or desktop with a floating control bar (`Replay` / `Stop` / `Rec MP4`).
   - **Deterministic Headless Render Mode**: Step `WidgetTester` virtual time by exact `1/fps` increments and pipe `RepaintBoundary.toImage()` `rawRgba` frames directly into `ffmpeg` `stdin` with **0% frame drop**.
4. **Native macOS `Apple Color Emoji` & Clean Layout CLI (`render_video`)**
   - Automatically strips `--use-test-fonts`, `--disable-asset-fonts`, and `--enable-checked-mode` from `flutter_tester` so macOS system color emojis render natively and debug overflow stripes are suppressed.

---

## Getting Started

### 1. Add Dependency

Add `flutter_scenario_recorder` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_scenario_recorder:
    git:
      url: https://github.com/BreadKey/flutter_scenario_recorder.git
      ref: main
```

### 2. Wrap Your App with `ScenarioStage`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/flutter_scenario_recorder.dart';

final captureBoundaryKey = GlobalKey();
final scenarioRunner = ScenarioRunner();

final steps = <ScenarioStep>[
  const WaitStep(Duration(milliseconds: 800)),
  HighlightAndTapStep(
    ScenarioTargetMatcher.byText('Reserve Consultation'),
    style: const HighlightStyle.spotlight(),
  ),
  TypeTextStep(
    ScenarioTargetMatcher.byHintText('First Name'),
    'Sakura',
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

### 3. Render Deterministic MP4 Video via CLI

Ensure `ffmpeg` is installed (`brew install ffmpeg`), then run:

```bash
dart run flutter_scenario_recorder:render_video test/scenario/render_consultation_video_test.dart
```

Pass custom FPS or output path via `--dart-define`:

```bash
dart run flutter_scenario_recorder:render_video \
  test/scenario/render_consultation_video_test.dart \
  --dart-define=SCENARIO_FPS=60 \
  --dart-define=SCENARIO_OUTPUT=output/demo_60fps.mp4
```

---

## Coding Agent Skill (`SKILL.md`)

This repository includes a Cursor Agent Skill at [`skills/flutter-scenario-video/SKILL.md`](skills/flutter-scenario-video/SKILL.md) that teaches AI coding agents how to:
- Snapshot API responses and prefetch remote images for offline deterministic rendering,
- Author `ScenarioStep` scripts from existing Flutter screens,
- Run `dart run flutter_scenario_recorder:render_video` and visually inspect extracted frames.

To install it globally in Cursor:

```bash
mkdir -p ~/.cursor/skills/flutter-scenario-video
cp skills/flutter-scenario-video/SKILL.md ~/.cursor/skills/flutter-scenario-video/SKILL.md
```

---

## License

MIT License. See [`LICENSE`](LICENSE) for details.
