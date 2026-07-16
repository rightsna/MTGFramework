import 'dart:convert';
import 'dart:io';

import '../models/character.dart';
import '../models/story_scene.dart';

/// Persists one project's storyboard as **per-scene files**: `scene1.json`,
/// `scene2.json`, … (파일 번호 = 씬 순서). 한 파일만 열어도 그 씬의 구성이 다 읽힌다.
/// 미디어(png/mp4/mp3)는 같은 프로젝트 폴더에 파일명으로 저장되고, JSON은 그 파일명만 참조한다.
///
/// 구버전 단일 파일 `storyboard.json`(씬 배열)이 있으면 로드 시 자동으로 읽어 와
/// 다음 저장 때 per-scene 파일로 옮기고 원본은 지운다.
class StoryboardStore {
  final String dirPath;
  StoryboardStore(this.dirPath);

  static final _sceneFile = RegExp(r'^scene(\d+)\.json$');
  static const _legacy = 'storyboard.json';

  Future<List<StoryScene>> load() async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    // scene1.json, scene2.json … 를 번호 순으로 모은다.
    final numbered = <(int, File)>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final m = _sceneFile.firstMatch(e.uri.pathSegments.last);
      if (m != null) numbered.add((int.parse(m.group(1)!), e));
    }
    if (numbered.isEmpty) return _loadLegacy();
    numbered.sort((a, b) => a.$1.compareTo(b.$1));
    final scenes = <StoryScene>[];
    for (final (_, f) in numbered) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map;
        scenes.add(StoryScene.fromJson(j.cast<String, dynamic>(), dirPath));
      } catch (_) {
        // 깨진 파일 하나는 건너뛰고 나머지는 살린다.
      }
    }
    return scenes;
  }

  Future<void> save(List<StoryScene> scenes) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    const enc = JsonEncoder.withIndent('  ');
    for (var i = 0; i < scenes.length; i++) {
      await File('$dirPath/scene${i + 1}.json')
          .writeAsString(enc.convert(scenes[i].toJson()));
    }
    // 씬 수가 줄었으면 남는 scene(N+1).json… 을 정리한다.
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final m = _sceneFile.firstMatch(e.uri.pathSegments.last);
      if (m != null && int.parse(m.group(1)!) > scenes.length) {
        await e.delete();
      }
    }
    // 마이그레이션 완료 — 구버전 단일 파일은 제거.
    final legacy = File('$dirPath/$_legacy');
    if (await legacy.exists()) await legacy.delete();
  }

  /// 구버전 `storyboard.json`(씬 배열) 읽기 — 다음 save에서 per-scene으로 전환된다.
  Future<List<StoryScene>> _loadLegacy() async {
    final f = File('$dirPath/$_legacy');
    if (!await f.exists()) return [];
    try {
      final data = jsonDecode(await f.readAsString()) as List;
      return data
          .map((e) =>
              StoryScene.fromJson((e as Map).cast<String, dynamic>(), dirPath))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ───────── 프로젝트 레벨 데이터(project.json) ─────────
  // 씬과 무관한 프로젝트 공통 설정. 지금은 공통 프롬프트 하나.
  static const _projectFile = 'project.json';

  /// 프로젝트 공통 프롬프트 읽기(없으면 빈 문자열).
  Future<String> loadCommonPrompt() async {
    final f = File('$dirPath/$_projectFile');
    if (!await f.exists()) return '';
    try {
      final j = jsonDecode(await f.readAsString()) as Map;
      return (j['commonPrompt'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 프로젝트 공통 프롬프트 저장.
  Future<void> saveCommonPrompt(String prompt) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    await File('$dirPath/$_projectFile').writeAsString(
        const JsonEncoder.withIndent('  ').convert({'commonPrompt': prompt}));
  }

  // ───────── 등장인물(characters.json) ─────────
  static const _charactersFile = 'characters.json';

  Future<List<Character>> loadCharacters() async {
    final f = File('$dirPath/$_charactersFile');
    if (!await f.exists()) return [];
    try {
      final data = jsonDecode(await f.readAsString()) as List;
      return data
          .map((e) =>
              Character.fromJson((e as Map).cast<String, dynamic>(), dirPath))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCharacters(List<Character> chars) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    await File('$dirPath/$_charactersFile').writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(chars.map((c) => c.toJson()).toList()));
  }

  /// 저장 위치(프로젝트 폴더). scene*.json + project.json + characters.json + 미디어가 여기 들어간다.
  String path() => dirPath;
}
