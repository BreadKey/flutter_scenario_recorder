import 'dart:io';

/// `flutter test` 실행 시 `flutter_tester`의 하드코딩된 플래그
/// (`--use-test-fonts`, `--disable-asset-fonts`, `--enable-checked-mode`)를
/// 자동으로 제거하여:
///   1) macOS 시스템 `Apple Color Emoji` 및 에셋 폰트가 그대로 렌더링되도록 하고,
///   2) 디버그 오버플로우 노란/검은 줄무늬 박스가 화면에 그려지지 않게 한 뒤,
/// 종료 시 `flutter_tester` 원본 바이너리를 안전하게 복원하는 CLI 러너.
///
/// 사용 예시:
///   dart run flutter_scenario_recorder:render_video test/scenario/render_consultation_video_test.dart
Future<void> main(List<String> args) async {
  final targetArgs = args.isEmpty
      ? ['test/scenario/render_consultation_video_test.dart']
      : args;

  final flutterBin = await _resolveFlutterBin();
  final flutterRoot = File(flutterBin).parent.parent.path;

  final testerCandidates = [
    '$flutterRoot/bin/cache/artifacts/engine/darwin-x64/flutter_tester',
    '$flutterRoot/bin/cache/artifacts/engine/darwin-arm64/flutter_tester',
  ];

  final wrappedTesters = <({String realPath, String backupPath})>[];

  try {
    for (final testerPath in testerCandidates) {
      final testerFile = File(testerPath);
      if (!await testerFile.exists()) continue;

      final backupPath = '$testerPath.orig';
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        await testerFile.copy(backupPath);
      }

      final wrapperScript = '''#!/usr/bin/env bash
ARGS=()
for arg in "\$@"; do
  case "\$arg" in
    --use-test-fonts|--disable-asset-fonts|--enable-checked-mode)
      ;;
    *)
      ARGS+=("\$arg")
      ;;
  esac
done
exec "$backupPath" "\${ARGS[@]}"
''';
      await testerFile.writeAsString(wrapperScript, flush: true);
      await Process.run('chmod', ['+x', testerPath]);
      wrappedTesters.add((realPath: testerPath, backupPath: backupPath));
    }

    stdout.writeln(
      '[flutter_scenario_recorder] Running with native system fonts (Apple Color Emoji) & clean layout mode...',
    );

    final process = await Process.start(
      flutterBin,
      ['test', ...targetArgs],
      mode: ProcessStartMode.inheritStdio,
    );
    final exitCode = await process.exitCode;
    exit(exitCode);
  } finally {
    for (final entry in wrappedTesters) {
      final backupFile = File(entry.backupPath);
      if (await backupFile.exists()) {
        await backupFile.rename(entry.realPath);
      }
    }
  }
}

Future<String> _resolveFlutterBin() async {
  final envRoot = Platform.environment['FLUTTER_ROOT'];
  if (envRoot != null && File('$envRoot/bin/flutter').existsSync()) {
    return '$envRoot/bin/flutter';
  }
  if (File('/Users/breadkey/dev/flutter/bin/flutter').existsSync()) {
    return '/Users/breadkey/dev/flutter/bin/flutter';
  }
  final whichRes = await Process.run('which', ['flutter']);
  if (whichRes.exitCode == 0) {
    final resolved = whichRes.stdout.toString().trim();
    if (resolved.isNotEmpty) {
      return File(resolved).resolveSymbolicLinksSync();
    }
  }
  throw StateError('Could not locate flutter executable.');
}
