import 'dart:convert';
import 'dart:io';

import '../models/story_scene.dart';
import '../models/video_track.dart';
import 'scene_export.dart' show SceneResolver;

/// 스토리보드 CLI들이 공유하는 배선 — 인자 해석 · 프로젝트/씬/트랙 찾기 · 출력.
///
/// CLI가 둘 이상(`storyboard-export` · `storyboard-voice`)이 되면서 "프로젝트 이름 일부로
/// 폴더 찾기" 같은 규칙이 바인마다 복사될 자리가 생겼다. 그러면 한쪽만 고쳐지고 조용히
/// 갈라진다 — 내보내기 엔진을 한 벌로 둔 것과 같은 이유로 여기도 한 벌만 둔다.
/// Flutter를 안 물기 때문에 CLI가 그대로 쓴다.
class CliSupport {
  /// 프로젝트 루트 — **앱이 실제로 쓰는 폴더**를 그대로 따라간다.
  /// 앱은 루트를 바꿀 수 있고(외장 디스크·동기화 폴더) 그 값을 `project_root.txt`에 적어 둔다.
  /// 그걸 안 읽으면 루트를 옮긴 순간 CLI만 옛 폴더를 보게 되어 "프로젝트가 없다"고 나온다.
  static String defaultRoot() {
    final home = Platform.environment['HOME'] ?? '';
    final pref = File(
        '$home/Library/Application Support/com.mtg.storyboardMaker/project_root.txt');
    if (pref.existsSync()) {
      final saved = pref.readAsStringSync().trim();
      if (saved.isNotEmpty && Directory(saved).existsSync()) return saved;
    }
    return '$home/Documents/StoryboardMaker'; // 설정 전이면 앱 기본값과 같은 자리
  }

  /// `--키 값` / `--키=값` / `--플래그`만 받는 최소 파서(외부 패키지 없이).
  static Map<String, String?> parse(List<String> argv) {
    final out = <String, String?>{};
    for (var i = 0; i < argv.length; i++) {
      final a = argv[i];
      if (!a.startsWith('-')) continue;
      final key = a.replaceFirst(RegExp(r'^-+'), '');
      if (key.contains('=')) {
        final k = key.substring(0, key.indexOf('='));
        out[k] = key.substring(key.indexOf('=') + 1);
        continue;
      }
      final next = i + 1 < argv.length ? argv[i + 1] : null;
      if (next != null && !next.startsWith('-')) {
        out[key] = next;
        i++;
      } else {
        out[key] = null; // 플래그
      }
    }
    return out;
  }

  /// 루트의 프로젝트 목록(`projects.json`).
  static List<Map<String, dynamic>> projects(String root) {
    final f = File('$root/projects.json');
    if (!f.existsSync()) throw CliError('프로젝트 목록이 없습니다: ${f.path}');
    return (jsonDecode(f.readAsStringSync()) as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// `--project`: 폴더 경로면 그대로, 아니면 projects.json에서 이름/id로 찾는다(부분 일치 허용).
  static String resolveProjectDir(String root, String arg) {
    if (arg.contains('/') && Directory(arg).existsSync()) return arg;
    final list = projects(root);
    final hits = [
      for (final p in list)
        if (p['id'] == arg ||
            p['name'] == arg ||
            (p['name'] as String).contains(arg))
          p,
    ];
    if (hits.isEmpty) {
      throw CliError('그런 프로젝트가 없습니다: $arg\n'
          '있는 것: ${list.map((p) => p['name']).join(' · ')}');
    }
    if (hits.length > 1) {
      throw CliError('프로젝트가 여러 개 걸립니다: '
          '${hits.map((p) => p['name']).join(' · ')} — 더 정확히 적어 주세요');
    }
    return '$root/${hits.first['id']}';
  }

  /// `--scene`: 번호(**0부터**) · id · 제목(부분 일치). 생략하면 첫 씬.
  static StoryScene pickScene(List<StoryScene> scenes, String? arg) {
    if (arg == null) return scenes.first;
    // 번호는 **0부터** — 앱 화면·파일명(`scene<N>.json`)과 같은 수여야 헷갈리지 않는다.
    final n = int.tryParse(arg);
    if (n != null) {
      if (n < 0 || n >= scenes.length) {
        throw CliError('씬 번호는 0~${scenes.length - 1} 입니다 (받은 값: $n)');
      }
      return scenes[n];
    }
    for (final s in scenes) {
      if (s.id == arg || s.title == arg || s.title.contains(arg)) return s;
    }
    throw CliError('그런 씬이 없습니다: $arg');
  }

  /// `--scene all`이면 전 씬, 아니면 지정한 하나만.
  static List<StoryScene> pickScenes(List<StoryScene> scenes, String? arg) =>
      arg == 'all' ? scenes : [pickScene(scenes, arg)];

  /// `--track`: 번호(1부터) · 이름(부분 일치). 생략하면 기준 트랙.
  static VideoTrack pickTrack(StoryScene scene, String? arg) {
    if (arg == null) return scene.baseTrack;
    final n = int.tryParse(arg);
    if (n != null) {
      if (n < 1 || n > scene.tracks.length) {
        throw CliError('트랙 번호는 1~${scene.tracks.length} 입니다 (받은 값: $n)');
      }
      return scene.tracks[n - 1];
    }
    final r = SceneResolver(scene);
    for (final t in scene.tracks) {
      if (t.id == arg || r.trackLabel(t).contains(arg)) return t;
    }
    throw CliError('그런 트랙이 없습니다: $arg');
  }

  /// 앱 설정(`movie_settings.json`)에서 값 하나 — CLI는 설정 화면이 없으니 앱이 저장한 걸 읽는다.
  /// (플러그인 없이 읽으려고 파일을 직접 본다 — 경로는 [MovieSettingsStore]와 같은 자리다.)
  static Map<String, dynamic> appSettings() {
    final home = Platform.environment['HOME'] ?? '';
    final f = File('$home/Library/Application Support/'
        'com.mtg.storyboardMaker/movie_settings.json');
    if (!f.existsSync()) return const {};
    try {
      return (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
    } catch (_) {
      return const {};
    }
  }

  static void emit(bool asJson, Object json, String text) =>
      stdout.writeln(asJson ? jsonEncode(json) : text.trimRight());

  static void fail(bool asJson, String message) => asJson
      ? stdout.writeln(jsonEncode({'ok': false, 'error': message}))
      : stderr.writeln('실패: $message');
}

/// 사용자에게 그대로 보여 줄 CLI 오류(스택 없이 문구만).
class CliError implements Exception {
  CliError(this.message);
  final String message;
  @override
  String toString() => message;
}
