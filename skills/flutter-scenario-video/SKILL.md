---
name: flutter-scenario-video
description: >-
  Creates automated UI scenario walkthroughs with highlight/touch overlays and
  renders frame-accurate MP4 videos for Flutter apps using
  flutter_scenario_recorder. Use when the user asks to record a Flutter app
  flow as a video, highlight buttons/interactions, create an app demo/tutorial
  MP4, or use flutter_scenario_recorder.
---

# Flutter Scenario Video Recorder (`flutter_scenario_recorder`)

Use this skill to build automated UI scenario scripts (virtual customer fixtures, button highlights with pulse border & elevation glow, virtual finger pointer & ripple, smooth scroll, character-by-character typing) and render frame-accurate, zero-frame-drop `.mp4` videos directly from Flutter widgets.

## Package Location

- Local package path: `/Users/breadkey/dev/project/flutter_scenario_recorder`
- Main library: `package:flutter_scenario_recorder/flutter_scenario_recorder.dart`
- Headless test & video rendering library: `package:flutter_scenario_recorder/testing.dart`
- CLI renderer (enables native macOS `Apple Color Emoji` & suppresses debug overflow stripes):
  ```bash
  dart run flutter_scenario_recorder:render_video test/scenario/render_<name>_video_test.dart
  ```

---

## Step-by-Step Workflow

### Step 1: Add Dependency to `pubspec.yaml`

Add `flutter_scenario_recorder` to the target Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  flutter_scenario_recorder:
    path: /Users/breadkey/dev/project/flutter_scenario_recorder
```

Run `flutter pub get`.

### Step 2: Prepare Offline Snapshot & Provider/DI Overrides

To guarantee fast, deterministic, offline rendering without network flakiness:
1. **Bypass Splash / Auth**: Override auth/session providers so the app starts immediately at the post-login target screen (e.g., `HomeScreen`).
2. **Snapshot API Data & Images**:
   - Capture or mock API responses into a local JSON snapshot (e.g., `assets/scenario_api_snapshot.json`).
   - Download remote content/event/profile images referenced in the snapshot into `assets/scenario_images/` and store a `localImageMap` (`{ "https://...": "assets/scenario_images/img_000.jpg" }`) inside the snapshot JSON.
   - Stub final mutation calls (e.g., reservation submit, payment submit) to return a synthetic success model so production data is never mutated.

### Step 3: Author the Scenario Script (`ScenarioStep` DSL)

Inspect the target screen widgets to identify button labels, `Key`s, `ValueKey`s, `TextField` `hintText`s, or widget `Type`s, then build a `List<ScenarioStep>`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/flutter_scenario_recorder.dart';

List<ScenarioStep> buildMyScenarioSteps() {
  return [
    const WaitStep(Duration(milliseconds: 1000), label: 'Wait for home screen'),
    HighlightAndTapStep(
      ScenarioTargetMatcher.byText('カウンセリング予約'),
      highlightDuration: const Duration(milliseconds: 900),
      style: const HighlightStyle.spotlight(),
      label: 'Highlight & tap reservation button',
    ),
    ScrollUntilVisibleStep(
      ScenarioTargetMatcher.byText('10万円〜30万円'),
      alignment: 0.4,
      label: 'Scroll to budget option',
    ),
    HighlightAndTapStep(
      ScenarioTargetMatcher.byText('10万円〜30万円'),
      style: const HighlightStyle.elevatedPulse(),
    ),
    TypeTextStep(
      ScenarioTargetMatcher.byHintText('花子'),
      'さくら',
      charInterval: const Duration(milliseconds: 60),
      label: 'Type first name',
    ),
  ];
}
```

#### Available `ScenarioTargetMatcher` Factories
- `ScenarioTargetMatcher.byKey(Key key)`
- `ScenarioTargetMatcher.byText(String text, {bool contains = false, int index = 0})`
- `ScenarioTargetMatcher.byHintText(String hintText, {int index = 0})`
- `ScenarioTargetMatcher.byType(Type widgetType, {int index = 0})`
- `ScenarioTargetMatcher.byPredicate(bool Function(Element) predicate, {String description})`

### Step 4: Create Deterministic MP4 Render Test (`test/scenario/render_<name>_video_test.dart`)

Use `FfmpegPipeFrameRecorder`, `DeterministicVideoScenarioClock`, and `ScenarioHeadlessHarness`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Render scenario to output/scenario.mp4', (tester) async {
    const logicalWidth = 393;
    const logicalHeight = 852;
    const fps = int.fromEnvironment('SCENARIO_FPS', defaultValue: 30);
    const outputPath = String.fromEnvironment(
      'SCENARIO_OUTPUT',
      defaultValue: 'output/scenario.mp4',
    );

    tester.view.physicalSize = const Size(logicalWidth * 2.0, logicalHeight * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    ScenarioHeadlessHarness.installCommonMockChannels();
    final originalErrorWidgetBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (_) => const SizedBox.shrink();

    final boundaryKey = GlobalKey();
    final recorder = FfmpegPipeFrameRecorder(
      boundaryKey: boundaryKey,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      fps: fps,
      pixelRatio: 2.0,
    );

    await tester.runAsync(() async {
      await ScenarioHeadlessHarness.loadMaterialIconsFont();
      // Load app custom fonts via ScenarioHeadlessHarness.loadFontFamily(...)
      await recorder.start(outputPath);
    });

    final clock = DeterministicVideoScenarioClock(
      tester: tester,
      recorder: recorder,
    );
    final runner = ScenarioRunner(clock: clock);
    final steps = buildMyScenarioSteps();

    await tester.pumpWidget(
      ScenarioStage(
        captureBoundaryKey: boundaryKey,
        runner: runner,
        steps: steps,
        autoStart: false,
        showPreviewControls: false,
        child: const MyScenarioApp(),
      ),
    );

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 33));
      while (tester.takeException() != null) {}
    }

    try {
      await runner.run(steps);
    } finally {
      await tester.runAsync(() async {
        await recorder.stop();
      });
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    while (tester.takeException() != null) {}
    ErrorWidget.builder = originalErrorWidgetBuilder;
  });
}
```

### Step 5: Render Video & Visually Inspect Sample Frames

1. Run the CLI renderer (this automatically strips `--use-test-fonts`, `--disable-asset-fonts`, and `--enable-checked-mode` from `flutter_tester` so macOS `Apple Color Emoji` renders in full color and debug overflow stripes are suppressed):
   ```bash
   dart run flutter_scenario_recorder:render_video test/scenario/render_<name>_video_test.dart
   ```
2. Extract 1–2 sample frames using `ffmpeg` and inspect them with the `Read` tool to verify that images, fonts, emojis, and highlight overlays look clean:
   ```bash
   ffmpeg -y -ss 2.0 -i output/scenario.mp4 -frames:v 1 -update 1 output/check_frame.png
   ```
   Delete temporary `.png` check frames after verification.
