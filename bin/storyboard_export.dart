// 스토리보드 프로젝트를 **터미널에서** mp4로 내보내는 CLI.
//
// GUI(스토리보드 메이커)의 내보내기 버튼과 **같은 코드**(SceneExporter)를 탄다 —
// 여기엔 ffmpeg 명령이 한 줄도 없다. 내보내기 규칙이 바뀌면 이 CLI도 그냥 따라간다.
//
//   dart run framework:storyboard_export --list
//   dart run framework:storyboard_export --project 마일스머서1_숏폼 --list
//   dart run framework:storyboard_export --project 마일스머서1_숏폼 \
//       --scene 4 --track 2 --speed 1.2 --out ~/Downloads/scene4.mp4
//
// Flutter 없이 도는 게 핵심이라(플러그인 = GUI 전용) 여기서 import하는 건 전부 순수 Dart다.
import 'dart:io';

import 'package:framework/src/storyboard/models/story_scene.dart';
import 'package:framework/src/storyboard/models/video_track.dart';
import 'package:framework/src/storyboard/services/cli_support.dart';
import 'package:framework/src/storyboard/services/scene_export.dart';
import 'package:framework/src/storyboard/services/storyboard_store.dart';
import 'package:framework/src/storyboard/services/video_edit.dart';

const _usage = '''
스토리보드 무비 내보내기 (GUI 내보내기와 같은 엔진)

  --list                    프로젝트 목록. --project와 같이 쓰면 그 프로젝트의 씬·트랙 현황
  --project <이름|id>       프로젝트(이름 일부만 써도 된다) 또는 폴더 경로
  --scene <번호|id|제목>    씬 지정(1부터). 생략하면 1
  --track <번호|이름>       트랙 지정(1부터). 생략하면 1(기준 트랙)
  --out <경로.mp4>          저장 위치. 생략하면 ~/Downloads/<씬 제목> - <트랙 이름>.mp4
  --speed <1.0~2.0>         이번 내보내기만 이 배속으로(트랙 설정은 안 건드린다)
  --root <경로>             프로젝트 루트 폴더(생략하면 앱이 쓰는 루트를 그대로 따라간다)
  --json                    결과를 JSON 한 줄로(기계 판독용)
''';

Future<void> main(List<String> argv) async {
  exitCode = await _run(argv); // Dart는 main 반환값을 종료코드로 쓰지 않는다
}

Future<int> _run(List<String> argv) async {
  final args = CliSupport.parse(argv);
  if (args.containsKey('help') || args.containsKey('h')) {
    stdout.write(_usage);
    return 0;
  }
  final asJson = args.containsKey('json');
  final root = args['root'] ?? CliSupport.defaultRoot();

  try {
    final projectArg = args['project'];
    // --list 단독 = 프로젝트 목록.
    if (args.containsKey('list') && projectArg == null) {
      CliSupport.emit(asJson, _projectsJson(root), _projectsText(root));
      return 0;
    }
    if (projectArg == null) {
      stderr.writeln('--project 를 지정하세요 (목록: --list)\n\n$_usage');
      return 2;
    }

    final dir = CliSupport.resolveProjectDir(root, projectArg);
    final scenes = await StoryboardStore(dir).load();
    if (scenes.isEmpty) throw CliError('씬이 없습니다: $dir');

    // --project --list = 그 프로젝트의 씬·트랙 현황(무엇이 뽑을 준비가 됐는지).
    if (args.containsKey('list')) {
      CliSupport.emit(asJson, _scenesJson(dir, scenes), _scenesText(dir, scenes));
      return 0;
    }

    final scene = CliSupport.pickScene(scenes, args['scene']);
    final track = CliSupport.pickTrack(scene, args['track']);
    final speed = args['speed'] == null
        ? null
        : (double.tryParse(args['speed']!) ??
            (throw CliError('--speed 는 숫자여야 합니다: ${args['speed']}')));
    final out = _resolveOut(args['out'], scene, track);

    if (!VideoEdit.available) throw CliError(VideoEdit.missingHint);

    final res = await SceneExporter.exportTrack(
      scene: scene,
      track: track,
      outPath: out,
      projectDirPath: dir,
      speed: speed,
      onProgress: asJson ? null : (m) => stderr.writeln('· $m'),
    );
    // 내보내며 스틸컷을 구웠으면 씬에 남긴다(GUI도 같은 규칙) — 다음엔 다시 안 굽는다.
    if (res.changed) await StoryboardStore(dir).save(scenes);

    CliSupport.emit(
      asJson,
      {
        'ok': true,
        'out': res.outPath,
        'scene': scene.title.isEmpty ? scene.id : scene.title,
        'track': SceneResolver(scene).trackLabel(track),
        'speed': speed ?? track.speed,
        'beats': res.beats,
        'skippedBeats': res.skippedBeats,
        'stillsRendered': res.stillsRendered,
        'stillsFailed': res.stillsFailed,
      },
      '완료: ${res.outPath}${res.droppedNote}',
    );
    return 0;
  } on NothingToExportException catch (e) {
    CliSupport.fail(asJson, e.message);
    return 1;
  } on CliError catch (e) {
    CliSupport.fail(asJson, e.message);
    return 2;
  } catch (e) {
    CliSupport.fail(asJson, '$e');
    return 1;
  }
}

// ───────── 목록 ─────────

Map<String, dynamic> _projectsJson(String root) =>
    {'root': root, 'projects': CliSupport.projects(root)};

String _projectsText(String root) {
  final b = StringBuffer('프로젝트 ($root)\n');
  for (final p in CliSupport.projects(root)) {
    b.writeln('  ${p['name']}   [${p['id']}]');
  }
  return b.toString();
}

/// 씬·트랙 현황 — 어떤 트랙이 뽑을 준비가 됐는지, 안 구운 스틸이 몇 개인지.
Map<String, dynamic> _scenesJson(String dir, List<StoryScene> scenes) => {
      'dir': dir,
      'scenes': [
        for (var i = 0; i < scenes.length; i++)
          () {
            final sc = scenes[i];
            final r = SceneResolver(sc);
            return {
              'n': i + 1,
              'id': sc.id,
              'title': sc.title,
              'beats': sc.beats.length,
              'shots': sc.shotCount,
              'bgm': SceneResolver.hasFile(sc.bgmPath),
              'tracks': [
                for (var t = 0; t < sc.tracks.length; t++)
                  {
                    'n': t + 1,
                    'name': r.trackLabel(sc.tracks[t]),
                    'speed': sc.tracks[t].speed,
                    'filled': sc.tracks[t].filledCount,
                    'shots': sc.tracks[t].shotCount,
                    'pendingStills': r.pendingStills(sc.tracks[t]).length,
                    'ready': r.trackHasVideo(sc.tracks[t]),
                  },
              ],
            };
          }(),
      ],
    };

String _scenesText(String dir, List<StoryScene> scenes) {
  final b = StringBuffer('$dir\n');
  for (var i = 0; i < scenes.length; i++) {
    final sc = scenes[i];
    final r = SceneResolver(sc);
    b.writeln('씬 ${i + 1}. ${sc.title.isEmpty ? sc.id : sc.title}'
        '  (비트 ${sc.beats.length} · 샷 ${sc.shotCount}'
        '${SceneResolver.hasFile(sc.bgmPath) ? ' · 배경음' : ''})');
    for (var t = 0; t < sc.tracks.length; t++) {
      final tr = sc.tracks[t];
      final pend = r.pendingStills(tr).length;
      b.writeln('   트랙 ${t + 1}. ${r.trackLabel(tr)}'
          '  영상 ${tr.filledCount}/${tr.shotCount}'
          '${pend > 0 ? ' · 안 구운 스틸 $pend' : ''}'
          ' · ${tr.speed}배속'
          '${r.trackHasVideo(tr) ? '' : ' · 뽑을 것 없음'}');
    }
  }
  return b.toString();
}

// ───────── 인자 해석 ─────────
// (프로젝트·씬·트랙 찾기와 인자 파서는 CliSupport에 있다 — storyboard-voice와 공유한다.)

/// `--out`: 없으면 ~/Downloads 에 GUI와 같은 이름으로. 폴더를 주면 그 안에 같은 이름으로.
String _resolveOut(String? arg, StoryScene scene, VideoTrack track) {
  final name = SceneExporter.suggestedName(scene, track);
  final home = Platform.environment['HOME'] ?? '.';
  if (arg == null) return '$home/Downloads/$name';
  final p = arg.startsWith('~/') ? '$home/${arg.substring(2)}' : arg;
  if (Directory(p).existsSync()) return '$p/$name';
  final parent = Directory(p).parent;
  if (!parent.existsSync()) parent.createSync(recursive: true);
  return p;
}
