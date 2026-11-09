import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scenario_recorder/src/engine/scenario_runner.dart';

/// `ScenarioStage`의 `RepaintBoundary`에서 매 프레임을 캡처하여 저장하고,
/// macOS/데스크톱 환경에서는 `ffmpeg`를 직접 호출하거나,
/// iOS 시뮬레이터 환경에서는 프레임 시퀀스를 기록하는 레코더
class ScenarioFrameRecorder extends ChangeNotifier {
  final GlobalKey boundaryKey;
  final int fps;
  final double pixelRatio;

  bool _isRecording = false;
  bool _isEncoding = false;
  int _capturedFrameCount = 0;
  String? _sessionDirPath;
  String? _lastOutputVideoPath;
  String? _statusMessage;

  ScenarioFrameRecorder({
    required this.boundaryKey,
    this.fps = 30,
    this.pixelRatio = 2.0,
  });

  bool get isRecording => _isRecording;
  bool get isEncoding => _isEncoding;
  int get capturedFrameCount => _capturedFrameCount;
  String? get sessionDirPath => _sessionDirPath;
  String? get lastOutputVideoPath => _lastOutputVideoPath;
  String? get statusMessage => _statusMessage;

  /// 새로운 녹화 세션을 시작하고 프레임 저장 폴더를 초기화한다.
  Future<String> startSession() async {
    final baseDir = Directory.systemTemp;
    final framesDir = Directory('${baseDir.path}/scenario_frames');

    if (await framesDir.exists()) {
      await framesDir.delete(recursive: true);
    }
    await framesDir.create(recursive: true);

    _sessionDirPath = framesDir.path;
    _capturedFrameCount = 0;
    _lastOutputVideoPath = null;
    _isRecording = true;
    _isEncoding = false;
    _statusMessage = 'Recording frames (0)...';
    notifyListeners();

    debugPrint('[ScenarioFrameRecorder] Session started: $_sessionDirPath');
    return framesDir.path;
  }

  /// 현재 프레임의 렌더링이 끝난 직후 `RepaintBoundary`를 캡처해 `frame_XXXXXX.png`로 저장한다.
  Future<void> captureCurrentFrame() async {
    if (!_isRecording || _sessionDirPath == null) return;

    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    SchedulerBinding.instance.scheduleFrame();
    await completer.future;

    final context = boundaryKey.currentContext;
    if (context == null || !context.mounted) return;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return;

    try {
      final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final width = image.width;
      final height = image.height;
      image.dispose();

      if (byteData == null) return;

      final frameIndex = _capturedFrameCount++;
      final fileName = 'frame_${frameIndex.toString().padLeft(6, '0')}.png';
      final filePath = '$_sessionDirPath/$fileName';

      await File(filePath).writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        flush: false,
      );

      if (frameIndex == 0) {
        await _writeMetadata(width: width, height: height);
      }

      if (frameIndex % 10 == 0) {
        _statusMessage = 'Recording ($frameIndex frames)';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ScenarioFrameRecorder] Frame capture error: $e');
    }
  }

  Future<void> _writeMetadata({
    required int width,
    required int height,
  }) async {
    if (_sessionDirPath == null) return;
    final metaFile = File('$_sessionDirPath/metadata.json');
    await metaFile.writeAsString(
      jsonEncode({
        'fps': fps,
        'pixelRatio': pixelRatio,
        'width': width,
        'height': height,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// 녹화를 종료하고, 가능한 경우 FFmpeg 인코딩을 수행한다.
  Future<void> finishSession() async {
    if (!_isRecording) return;
    _isRecording = false;

    final dirPath = _sessionDirPath;
    if (dirPath == null || _capturedFrameCount == 0) {
      _statusMessage = 'No frames captured';
      notifyListeners();
      return;
    }

    final doneFile = File('$dirPath/DONE');
    await doneFile.writeAsString('$_capturedFrameCount\n');

    debugPrint('============================================================');
    debugPrint('[ScenarioFrameRecorder] Capture finished!');
    debugPrint('  Total frames : $_capturedFrameCount (${fps}fps)');
    debugPrint('  Frames dir   : $dirPath');

    if (!kIsWeb && Platform.isMacOS) {
      await _encodeWithFfmpegOnMacOS(dirPath);
    } else {
      _lastOutputVideoPath = dirPath;
      _statusMessage = 'Saved $_capturedFrameCount frames';
    }
    debugPrint('============================================================');
    notifyListeners();
  }

  Future<void> _encodeWithFfmpegOnMacOS(String dirPath) async {
    _isEncoding = true;
    _statusMessage = 'Encoding MP4...';
    notifyListeners();

    try {
      final outputPath = '$dirPath/scenario_output.mp4';
      final result = await Process.run('/opt/homebrew/bin/ffmpeg', [
        '-y',
        '-framerate',
        '$fps',
        '-i',
        '$dirPath/frame_%06d.png',
        '-vf',
        'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-preset',
        'slow',
        '-crf',
        '18',
        outputPath,
      ]);

      if (result.exitCode == 0) {
        _lastOutputVideoPath = outputPath;
        _statusMessage = 'MP4 Ready ($_capturedFrameCount frames)';
        debugPrint('  MP4 Output   : $outputPath');
      } else {
        _statusMessage = 'FFmpeg error (${result.exitCode})';
        debugPrint('[ScenarioFrameRecorder] FFmpeg stderr: ${result.stderr}');
      }
    } catch (e) {
      _statusMessage = 'Saved $_capturedFrameCount frames';
      debugPrint('[ScenarioFrameRecorder] Direct FFmpeg unavailable: $e');
    } finally {
      _isEncoding = false;
      notifyListeners();
    }
  }
}

/// 녹화 중일 때는 프레임 단위로 정확하게 시간을 전진시키며 `ScenarioFrameRecorder.captureCurrentFrame()`을
/// 호출하고, 일반 재생 중일 때는 실시간(`RealTimeScenarioClock`)으로 동작하는 하이브리드 시계
class RecordingScenarioClock extends ScenarioClock {
  final ScenarioFrameRecorder recorder;
  final ScenarioClock fallbackClock;

  const RecordingScenarioClock({
    required this.recorder,
    this.fallbackClock = const RealTimeScenarioClock(),
  });

  @override
  Future<void> delay(Duration duration) async {
    if (!recorder.isRecording) {
      await fallbackClock.delay(duration);
      return;
    }

    if (duration <= Duration.zero) return;

    final fps = recorder.fps;
    final frameMicros = (1000000 / fps).round();
    final frameDuration = Duration(microseconds: frameMicros);
    final totalFrames = (duration.inMicroseconds / frameMicros).round().clamp(
      1,
      100000,
    );

    for (var i = 0; i < totalFrames; i++) {
      if (!recorder.isRecording) break;
      await Future<void>.delayed(frameDuration);
      await recorder.captureCurrentFrame();
    }
  }

  @override
  Future<void> animate(
    Duration duration,
    void Function(double progress) onTick, {
    int fps = 60,
  }) async {
    if (!recorder.isRecording) {
      await fallbackClock.animate(duration, onTick, fps: fps);
      return;
    }

    final targetFps = recorder.fps;
    if (duration <= Duration.zero) {
      onTick(1.0);
      await recorder.captureCurrentFrame();
      return;
    }

    final frameMicros = (1000000 / targetFps).round();
    final frameDuration = Duration(microseconds: frameMicros);
    final totalFrames = (duration.inMicroseconds / frameMicros).round().clamp(
      1,
      100000,
    );

    onTick(0.0);
    await recorder.captureCurrentFrame();

    for (var i = 1; i <= totalFrames; i++) {
      if (!recorder.isRecording) break;
      await Future<void>.delayed(frameDuration);
      final progress = (i / totalFrames).clamp(0.0, 1.0);
      onTick(progress);
      await recorder.captureCurrentFrame();
    }
  }
}

/// 디스크에 수천 개의 PNG 파일을 쓰는 대신, `RepaintBoundary`에서 추출한
/// `rawRgba` 바이트 스트림을 `ffmpeg` 프로세스의 `stdin`으로 직접 파이핑하여
/// 고화질 MP4 영상을 생성하는 레코더 (`flutter test` 결정론적 렌더링용)
class FfmpegPipeFrameRecorder {
  final GlobalKey boundaryKey;
  final int logicalWidth;
  final int logicalHeight;
  final int fps;
  final double pixelRatio;

  Process? _ffmpegProcess;
  int _capturedFrameCount = 0;
  final StringBuffer _stderrBuffer = StringBuffer();

  FfmpegPipeFrameRecorder({
    required this.boundaryKey,
    required this.logicalWidth,
    required this.logicalHeight,
    this.fps = 30,
    this.pixelRatio = 2.0,
  });

  int get capturedFrameCount => _capturedFrameCount;
  int get pixelWidth => (logicalWidth * pixelRatio).round();
  int get pixelHeight => (logicalHeight * pixelRatio).round();

  static Future<String> _resolveFfmpegExecutable() async {
    for (final candidate in [
      '/opt/homebrew/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
      'ffmpeg',
    ]) {
      try {
        final result = await Process.run(candidate, ['-version']);
        if (result.exitCode == 0) {
          return candidate;
        }
      } catch (_) {}
    }
    throw StateError('ffmpeg executable not found on this machine.');
  }

  /// `ffmpeg` 프로세스를 시작하고 `stdin` 파이프를 연다.
  Future<void> start(String outputPath) async {
    final outFile = File(outputPath);
    await outFile.parent.create(recursive: true);

    final ffmpegBin = await _resolveFfmpegExecutable();
    _capturedFrameCount = 0;
    _stderrBuffer.clear();

    _ffmpegProcess = await Process.start(ffmpegBin, [
      '-y',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'rgba',
      '-s',
      '${pixelWidth}x$pixelHeight',
      '-r',
      '$fps',
      '-i',
      '-',
      '-vf',
      'scale=trunc(iw/2)*2:trunc(ih/2)*2',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-preset',
      'fast',
      '-crf',
      '18',
      outputPath,
    ]);

    _ffmpegProcess!.stderr.transform(utf8.decoder).listen(_stderrBuffer.write);
    _ffmpegProcess!.stdout.drain<void>();
  }

  /// 현재 `RepaintBoundary`를 캡처하여 `rawRgba` 바이트를 `ffmpeg` `stdin`에 기록한다.
  Future<void> captureFrame() async {
    final process = _ffmpegProcess;
    if (process == null) return;

    final context = boundaryKey.currentContext;
    if (context == null || !context.mounted) return;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return;

    final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    image.dispose();

    if (byteData == null) return;

    process.stdin.add(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
    );
    _capturedFrameCount++;

    if (_capturedFrameCount % 30 == 0) {
      await process.stdin.flush();
    }
  }

  /// `stdin`을 닫고 `ffmpeg` 인코딩 완료를 대기한다.
  Future<void> stop() async {
    final process = _ffmpegProcess;
    _ffmpegProcess = null;
    if (process == null) return;

    await process.stdin.flush();
    await process.stdin.close();
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw StateError(
        'FFmpeg exited with code $exitCode:\n$_stderrBuffer',
      );
    }
  }
}
