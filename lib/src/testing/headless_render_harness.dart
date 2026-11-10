import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 헤드리스 `flutter test` 비디오 렌더링 시 자주 필요한 폰트 로더,
/// 플랫폼 채널(`path_provider`, `sqflite`, `platform_views`) Mock,
/// 로컬 이미지 HTTP 응답 오버라이드를 제공하는 헬퍼
class ScenarioHeadlessHarness {
  const ScenarioHeadlessHarness._();

  /// 지정된 폰트 패밀리와 파일 경로 리스트를 `FontLoader`로 로드한다.
  static Future<void> loadFontFamily(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var loadedAny = false;
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
        loadedAny = true;
      }
    }
    if (loadedAny) {
      await loader.load();
    }
  }

  /// Flutter SDK 내장 `MaterialIcons` 폰트를 로드한다.
  static Future<void> loadMaterialIconsFont() async {
    String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot == null || !Directory(flutterRoot).existsSync()) {
      final whichRes = await Process.run('which', ['flutter']);
      if (whichRes.exitCode == 0) {
        final resolved = whichRes.stdout.toString().trim();
        if (resolved.isNotEmpty) {
          flutterRoot = File(
            File(resolved).resolveSymbolicLinksSync(),
          ).parent.parent.path;
        }
      }
    }
    final home = Platform.environment['HOME'];
    flutterRoot ??= (home != null && Directory('$home/dev/flutter').existsSync())
        ? '$home/dev/flutter'
        : '$home/flutter';
    await loadFontFamily('MaterialIcons', [
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  }

  /// `path_provider`, `sqflite`, `platform_views` 등 헤드리스 렌더링 중 호출되는
  /// 네이티브 채널을 자동으로 Mock 처리하고 `addTearDown`에 정리를 등록한다.
  static Directory installCommonMockChannels() {
    final tempStorageDir = Directory.systemTemp.createTempSync(
      'scenario_cache_',
    );

    const pathProviderChannel = MethodChannel(
      'plugins.flutter.io/path_provider',
    );
    const sqfliteChannel = MethodChannel('com.tekartik.sqflite');
    const platformViews2Channel = MethodChannel('flutter/platform_views_2');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') {
            return Completer<dynamic>().future;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformViews2Channel, (call) async {
          if (call.method == 'create') {
            return Completer<dynamic>().future;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          return tempStorageDir.path;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sqfliteChannel, (call) async {
          switch (call.method) {
            case 'getDatabasesPath':
              return tempStorageDir.path;
            case 'openDatabase':
              return 1;
            case 'query':
              return <String, dynamic>{
                'columns': <String>[],
                'rows': <List<dynamic>>[],
              };
            case 'insert':
            case 'update':
            case 'delete':
            case 'execute':
            case 'batch':
            case 'closeDatabase':
              return 0;
            default:
              return null;
          }
        });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platformViews2Channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(sqfliteChannel, null);
      if (tempStorageDir.existsSync()) {
        tempStorageDir.deleteSync(recursive: true);
      }
    });

    return tempStorageDir;
  }
}

/// 일반 `Image.network` 및 `http.IOClient` 요청에 대해 로컬에 캐시된 이미지 바이트를 즉시 반환하는 `HttpOverrides`
class ScenarioLocalImageHttpOverrides extends HttpOverrides {
  final Map<String, String> urlToLocalPath;
  final Uint8List fallbackBytes;

  ScenarioLocalImageHttpOverrides({
    required this.urlToLocalPath,
    required this.fallbackBytes,
  });

  Uint8List _bytesForUri(Uri uri) {
    final url = uri.toString();
    final path = urlToLocalPath[url];
    if (path != null && File(path).existsSync()) {
      return File(path).readAsBytesSync();
    }
    final decoded = Uri.decodeFull(url);
    for (final entry in urlToLocalPath.entries) {
      if (Uri.decodeFull(entry.key) == decoded &&
          File(entry.value).existsSync()) {
        return File(entry.value).readAsBytesSync();
      }
    }
    return fallbackBytes;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _LocalImageHttpClient(_bytesForUri);
  }
}

class _LocalImageHttpClient implements HttpClient {
  final Uint8List Function(Uri uri) _resolveBytes;
  _LocalImageHttpClient(this._resolveBytes);

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _LocalHttpClientRequest(url, _resolveBytes(url));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _LocalHttpClientRequest(url, _resolveBytes(url));

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _LocalHttpClientRequest implements HttpClientRequest {
  @override
  final Uri uri;
  final Uint8List _bytes;

  _LocalHttpClientRequest(this.uri, this._bytes);

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  final HttpHeaders headers = _DummyHttpHeaders();

  @override
  Future<HttpClientResponse> get done async => _LocalHttpClientResponse(_bytes);

  @override
  Future<HttpClientResponse> close() async => _LocalHttpClientResponse(_bytes);

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  void add(List<int> data) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DummyHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  String? value(String name) => null;

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _LocalHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final Uint8List _bytes;

  _LocalHttpClientResponse(this._bytes);

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _bytes.length;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _DummyHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
