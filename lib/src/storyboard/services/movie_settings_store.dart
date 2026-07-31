import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'movie_settings.dart';

export 'movie_settings.dart';

/// [MovieSettings]를 앱 지원 폴더(movie_settings.json)에 저장한다.
///
/// **저장만** 여기 있다 — 값(enum·MovieSettings)은 `movie_settings.dart`에 순수 Dart로 남겼다.
/// path_provider는 Flutter 플러그인이라, 이 파일을 import하는 순간 그 코드는 Flutter 없이는
/// 못 돈다. 씬 모델이 ImageRes/VideoRes를 쓰므로 값과 저장을 갈라 놔야
/// CLI 내보내기(`bin/storyboard_export.dart`)가 같은 모델을 그대로 읽을 수 있다.
class MovieSettingsStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/movie_settings.json');
  }

  Future<MovieSettings> load() async {
    final f = await _file();
    if (!await f.exists()) return const MovieSettings();
    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return const MovieSettings();
      return MovieSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return const MovieSettings();
    }
  }

  Future<void> save(MovieSettings s) async {
    final f = await _file();
    const encoder = JsonEncoder.withIndent('  ');
    await f.writeAsString(encoder.convert(s.toJson()));
  }
}
