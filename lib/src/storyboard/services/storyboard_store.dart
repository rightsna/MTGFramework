import 'dart:convert';
import 'dart:io';

import '../models/character.dart';
import '../models/story_scene.dart';

/// Persists one project's storyboard as **per-scene files**: `scene1.json`,
/// `scene2.json`, … (파일 번호 = 씬 순서). 한 파일만 열어도 그 씬의 구성이 다 읽힌다.
/// 미디어(png/mp4/mp3)는 같은 프로젝트 폴더에 파일명으로 저장되고, JSON은 그 파일명만 참조한다.
class StoryboardStore {
  final String dirPath;
  StoryboardStore(this.dirPath);

  static final _sceneFile = RegExp(r'^scene(\d+)\.json$');

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

  /// 저장 위치(프로젝트 폴더). scene*.json + characters.json + 미디어가 여기 들어간다.
  String path() => dirPath;
}
