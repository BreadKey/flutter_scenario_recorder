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

Use this skill to build automated UI scenario scripts (virtual user/customer fixtures, button highlights with pulse border & elevation glow, virtual finger pointer & ripple, smooth scroll, character-by-character typing) and render frame-accurate, zero-frame-drop `.mp4` videos directly from Flutter widgets.

## Prerequisites & Package Info

- **Repository**: `https://github.com/BreadKey/flutter_scenario_recorder.git`
- **Main runtime library**: `package:flutter_scenario_recorder/flutter_scenario_recorder.dart`
- **Headless test & video rendering library**: `package:flutter_scenario_recorder/testing.dart`
- **System requirement**: `ffmpeg` must be installed on the machine:
  ```bash
  ffmpeg -version
  # macOS: brew install ffmpeg
  # Ubuntu/Debian: sudo apt-get install -y ffmpeg
  ```
- **CLI renderer** (enables native macOS `Apple Color Emoji` & suppresses debug overflow stripes):
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
    git:
      url: https://github.com/BreadKey/flutter_scenario_recorder.git
      ref: main
```

Run `flutter pub get`.

### Step 2: Prepare Offline Snapshot & Provider/DI Overrides

To guarantee fast, deterministic, offline rendering without network flakiness:
1. **Bypass Splash / Auth**: Override auth/session state or providers so the app starts immediately at the post-login target screen (e.g., `HomeScreen`).
2. **Snapshot API Data & Images**:
   - Capture or mock API/repository responses into a local JSON snapshot (e.g., `assets/scenario_api_snapshot.json`).
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
      ScenarioTargetMatcher.byText('Reserve Consultation'),
      highlightDuration: const Duration(milliseconds: 900),
      style: const HighlightStyle.spotlight(),
      label: 'Highlight & tap reservation button',
    ),
    ScrollUntilVisibleStep(
      ScenarioTargetMatcher.byText('\$1,000~\$3,000'),
      alignment: 0.4,
      label: 'Scroll to budget option',
    ),
    HighlightAndTapStep(
      ScenarioTargetMatcher.byText('\$1,000~\$3,000'),
      style: const HighlightStyle.elevatedPulse(),
    ),
    TypeTextStep(
      ScenarioTargetMatcher.byHintText('First Name'),
      'Sakura',
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

#### Available `HighlightStyle` Presets
- `const HighlightStyle.elevatedPulse()`: Animated pulsing border + outer glow shadow.
- `const HighlightStyle.spotlight()`: Dims the surrounding screen and spotlights the target widget with a pulsing border.

### Step 4: (Optional) Create Real-Time Simulator Preview Entrypoint (`lib/main_scenario.dart`)

To preview the scenario interactively on an iOS Simulator, Android Emulator, or desktop with a floating `Replay` / `Stop` / `Rec MP4` control bar:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/flutter_scenario_recorder.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (_) => const SizedBox.shrink();

  final boundaryKey = GlobalKey();
  final recorder = ScenarioFrameRecorder(boundaryKey: boundaryKey, fps: 30);
  final runner = ScenarioRunner(clock: RecordingScenarioClock(recorder: recorder));
  final steps = buildMyScenarioSteps();

  runApp(
    ScenarioStage(
      captureBoundaryKey: boundaryKey,
      runner: runner,
      recorder: recorder,
      steps: steps,
      autoStart: true,
      showPreviewControls: true,
      child: const MyScenarioApp(),
    ),
  );
}
```

### Step 5: Create Deterministic MP4 Render Test (`test/scenario/render_<name>_video_test.dart`)

Use `FfmpegPipeFrameRecorder`, `DeterministicVideoScenarioClock`, and `ScenarioHeadlessHarness` to render a frame-accurate MP4 without running a simulator:

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

    expect(File(outputPath).existsSync(), isTrue);
  });
}
```

### Step 6: Render Video & Visually Inspect Sample Frames

1. Run the CLI renderer (automatically strips `--use-test-fonts`, `--disable-asset-fonts`, and `--enable-checked-mode` from `flutter_tester` so system fonts & `Apple Color Emoji` render in full color and debug overflow stripes are suppressed):
   ```bash
   dart run flutter_scenario_recorder:render_video test/scenario/render_<name>_video_test.dart
   ```
2. Extract 1–2 sample frames using `ffmpeg` and inspect them to verify that images, fonts, emojis, and highlight overlays rendered cleanly:
   ```bash
   ffmpeg -y -ss 2.0 -i output/scenario.mp4 -frames:v 1 -update 1 output/check_frame.png
   ```
   Delete temporary `.png` check frames after verification.
