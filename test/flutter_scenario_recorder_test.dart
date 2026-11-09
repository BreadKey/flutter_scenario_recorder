import 'package:flutter/material.dart';
import 'package:flutter_scenario_recorder/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ScenarioStage highlights target, moves virtual pointer, taps, and types text',
    (tester) async {
      final boundaryKey = GlobalKey();
      final clock = WidgetTesterScenarioClock(tester);
      final runner = ScenarioRunner(clock: clock);

      var buttonTapped = false;

      final steps = <ScenarioStep>[
        HighlightAndTapStep(
          ScenarioTargetMatcher.byText('Reserve Now'),
          highlightDuration: const Duration(milliseconds: 240),
          pointerMoveDuration: const Duration(milliseconds: 120),
          tapHoldDuration: const Duration(milliseconds: 60),
          postTapDelay: const Duration(milliseconds: 80),
          style: const HighlightStyle.spotlight(),
        ),
        TypeTextStep(
          ScenarioTargetMatcher.byHintText('Enter name'),
          'Sakura',
          highlightDuration: const Duration(milliseconds: 180),
          charInterval: const Duration(milliseconds: 25),
        ),
      ];

      await tester.pumpWidget(
        ScenarioStage(
          captureBoundaryKey: boundaryKey,
          runner: runner,
          steps: steps,
          autoStart: false,
          showPreviewControls: true,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () {
                      buttonTapped = true;
                    },
                    child: const Text('Reserve Now'),
                  ),
                  const SizedBox(height: 16),
                  const TextField(
                    decoration: InputDecoration(hintText: 'Enter name'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await runner.run(steps);

      expect(buttonTapped, isTrue);
      expect(find.text('Sakura'), findsOneWidget);
    },
  );
}
