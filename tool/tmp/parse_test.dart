import 'dart:convert';
import 'dart:io';
import '../../lib/src/storyboard/models/story_scene.dart';
void main() {
  const dir = '/Users/sewon/SynologyDrive/storyboard/StoryboardMaker/proj_1785404052529175_0';
  for (var n = 1; n <= 20; n++) {
    try {
      final j = jsonDecode(File('$dir/scene$n.json').readAsStringSync()) as Map;
      StoryScene.fromJson(j.cast<String, dynamic>(), dir);
    } catch (e) {
      stdout.writeln('scene$n ✗ $e');
    }
  }
  stdout.writeln('전체 20씬 검사 끝');
}
