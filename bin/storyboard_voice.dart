// 대사 **음성 생성**과 **자막 큐 재계산**을 터미널에서 하는 CLI.
//
// 내보내기(`storyboard_export`)가 파이프라인의 뒤쪽이라면 이건 앞쪽이다:
//
//   ① --voice     대사 → 음성(mp3) + 그 길이로 샷 화면 길이 배분
//   ② --captions  이미 만든 음성을 강제 정렬해 자막 큐를 실제 발화에 맞춤
//   ③ (내보내기)  storyboard-export
//
// ②를 건너뛰면 자막이 어긋난다 — 글자수 비례로 나눈 큐는 보이스가 줄 끝에서 쉬는 만큼
// 밀리고, 마지막 큐가 음성 끝에서 사라져 패딩 구간에 자막이 빈다(실측 2026-08-01).
//
// 규칙은 전부 VoiceTiming(엔진)에 있다 — 여기엔 계산이 없다. GUI가 같은 함수를 부르므로
// 앱에서 한 것과 터미널에서 한 것이 어긋나지 않는다.
//
// Flutter 없이 도는 게 핵심이라 여기서 import하는 건 전부 순수 Dart다.
import 'dart:io';

import 'package:framework/src/storyboard/models/dialogue.dart';
import 'package:framework/src/storyboard/models/dialogue_beat.dart';
import 'package:framework/src/storyboard/services/cli_support.dart';
import 'package:framework/src/storyboard/services/elevenlabs_service.dart';
import 'package:framework/src/storyboard/services/scene_export.dart';
import 'package:framework/src/storyboard/services/storyboard_store.dart';
import 'package:framework/src/storyboard/services/voice_timing.dart';

const _usage = '''
대사 음성 생성 · 자막 큐 재계산 (GUI와 같은 엔진)

  --project <이름|id>       프로젝트(이름 일부만 써도 된다) 또는 폴더 경로
  --scene <번호|id|제목|all> 씬 지정(0부터). 생략하면 0, `all`이면 전 씬
  --track <번호|이름>       트랙 지정(1부터). 생략하면 1(기준 트랙)

  --voice                   대사 음성을 만든다(이미 있는 비트는 건너뛴다)
  --captions                이미 만든 음성을 강제 정렬해 자막 큐를 다시 잡는다
  --seconds                 음성 길이로 샷 화면 길이만 다시 배분한다(생성·통신 없음)

  --voice-id <id>           보이스 지정. 생략하면 트랙에 저장된 보이스
  --force                   이미 음성이 있는 비트도 다시 뽑는다(TTS 크레딧 나감)
  --dry-run                 무엇이 바뀔지만 보여주고 저장하지 않는다
  --root <경로>             프로젝트 루트 폴더(생략하면 앱이 쓰는 루트를 그대로 따라간다)
  --json                    결과를 JSON 한 줄로(기계 판독용)

  예) storyboard-voice --project 상담소 --scene all --captions
''';

Future<void> main(List<String> argv) async {
  exitCode = await _run(argv); // Dart는 main 반환값을 종료코드로 쓰지 않는다
}

Future<int> _run(List<String> argv) async {
  final args = CliSupport.parse(argv);
  if (args.isEmpty || args.containsKey('help') || args.containsKey('h')) {
    stdout.write(_usage);
    return args.isEmpty ? 2 : 0;
  }
  final asJson = args.containsKey('json');
  final dry = args.containsKey('dry-run');
  final doVoice = args.containsKey('voice');
  final doCaptions = args.containsKey('captions');
  final doSeconds = args.containsKey('seconds');

  try {
    if (!doVoice && !doCaptions && !doSeconds) {
      throw CliError('--voice · --captions · --seconds 중 하나는 지정하세요');
    }
    final projectArg = args['project'];
    if (projectArg == null) throw CliError('--project 를 지정하세요');

    final root = args['root'] ?? CliSupport.defaultRoot();
    final dir = CliSupport.resolveProjectDir(root, projectArg);
    final store = StoryboardStore(dir);
    final all = await store.load();
    if (all.isEmpty) throw CliError('씬이 없습니다: $dir');

    // 통신이 필요한 작업(생성·정렬)에만 키를 요구한다 — --seconds는 계산뿐이다.
    final key = (CliSupport.appSettings()['elevenKey'] as String?)?.trim();
    if ((doVoice || doCaptions) && (key == null || key.isEmpty)) {
      throw CliError('일레븐랩스 키가 없습니다 — 앱 설정에서 먼저 넣으세요');
    }
    final eleven = key == null || key.isEmpty ? null : ElevenLabsService(key);
    final stability = _stabilityOf(CliSupport.appSettings());

    final report = <Map<String, dynamic>>[];
    var changedAny = false;
    for (final scene in CliSupport.pickScenes(all, args['scene'])) {
      final track = CliSupport.pickTrack(scene, args['track']);
      final r = SceneResolver(scene);
      final voiceId = args['voice-id'] ?? track.defaultVoiceId;
      var changed = false;

      for (final beat in track.beats) {
        final row = <String, dynamic>{
          'scene': scene.title.isEmpty ? scene.id : scene.title,
          'beat': beat.id,
        };
        // 대본은 기준 트랙에만 있다 — 파생 트랙(번역본) 비트는 overrides['text'] 이거나
        // 손 안 댔으면 기준 비트 것이다. 여기서 beat.dialogue.text 를 직접 보면 파생 트랙이
        // 통째로 "대사 없음" 으로 걸러진다(= 번역 트랙 음성을 CLI 로 못 뽑는다).
        final text = (beat.resolvedScript(r.baseBeatOf(beat))?.text ?? '').trim();
        if (text.isEmpty) {
          row['skip'] = '대사 없음';
          report.add(row);
          continue;
        }

        // ① 음성 — 이미 있는 비트는 건너뛴다(비트 하나 추가할 때 전편을 다시 뽑으면 크레딧만 나간다).
        if (doVoice) {
          final have = SceneResolver.hasFile(beat.dialogue?.voicePath);
          if (have && !args.containsKey('force')) {
            row['voice'] = '있음';
          } else if (voiceId.isEmpty) {
            throw CliError('보이스가 지정되지 않았습니다 — --voice-id 로 주거나 '
                '앱에서 트랙 보이스를 고르세요');
          } else if (dry) {
            row['voice'] = '생성 예정';
          } else {
            final res = await eleven!.generateSpeech(
              voiceId: voiceId,
              text: text,
              stability: stability,
            );
            final f = File('$dir/${beat.id}_voice.mp3');
            await f.writeAsBytes(res.bytes);
            // 파생 트랙 비트는 대본을 기준 트랙에서 물려받으므로, 음성이 아직 없으면
            // dialogue 자체가 null 이다(그릇은 음성을 담을 때 생긴다). 비트를 새로 만들고
            // 첫 음성을 붙이는 경우가 그것 — 여기서 만들어 주지 않으면 널 참조로 죽는다.
            (beat.dialogue ??= Dialogue())
              ..voicePath = f.path
              ..voiceSeconds = res.seconds;
            changed = true;
            row['voice'] = '${res.seconds.toStringAsFixed(2)}s';
          }
        }

        // ② 샷 화면 길이 = 내림(음성초)+1 을 샷들에 나눈다.
        if (doVoice || doSeconds) {
          final secs = r.voiceSecondsOfBeat(beat);
          if (secs > 0 && !dry && VoiceTiming.applyToBeat(beat, voiceSeconds: secs)) {
            changed = true;
          }
          row['seconds'] = VoiceTiming.beatVideoSeconds(secs);
        }

        // ③ 자막 큐 — 이미 만들어 둔 mp3를 강제 정렬(TTS 크레딧 안 듦).
        if (doCaptions) {
          final path = r.voicePathOf(beat);
          if (!SceneResolver.hasFile(path)) {
            row['captions'] = '음성 없음';
          } else if (dry) {
            row['captions'] = '재계산 예정';
          } else {
            final words = await eleven!.forcedAlignment(
              audio: await File(path!).readAsBytes(),
              text: text,
              filename: path.split('/').last,
            );
            final cues = VoiceTiming.cuesFromWords(
              words,
              VoiceTiming.linesOf(text),
              beatSeconds: beat.shots.fold<double>(
                  0.0, (a, s) => a + r.shotVideoSeconds(s)),
            );
            VoiceTiming.applyCaption(beat, cues);
            changed = true;
            row['captions'] = '큐 ${cues.length}';
          }
        }
        report.add(row);
      }

      if (changed && !dry) {
        changedAny = true;
      }
    }
    if (changedAny) await store.save(all);

    CliSupport.emit(
      asJson,
      {'ok': true, 'dryRun': dry, 'saved': changedAny, 'beats': report},
      _text(report, dry: dry, saved: changedAny),
    );
    return 0;
  } on CliError catch (e) {
    CliSupport.fail(asJson, e.message);
    return 2;
  } catch (e) {
    CliSupport.fail(asJson, '$e');
    return 1;
  }
}

/// 앱 설정의 안정성 프리셋 → eleven v3 값. 모르는 값이면 null(모델 기본).
double? _stabilityOf(Map<String, dynamic> settings) =>
    switch (settings['ttsStability']) {
      'creative' => 0.0,
      'natural' => 0.5,
      'robust' => 1.0,
      _ => null,
    };

String _text(List<Map<String, dynamic>> rows,
    {required bool dry, required bool saved}) {
  final b = StringBuffer();
  var scene = '';
  for (final r in rows) {
    if (r['scene'] != scene) {
      scene = r['scene'] as String;
      b.writeln(scene);
    }
    final bits = [
      if (r['skip'] != null) '— ${r['skip']}',
      if (r['voice'] != null) '음성 ${r['voice']}',
      if (r['seconds'] != null) '화면 ${r['seconds']}s',
      if (r['captions'] != null) '자막 ${r['captions']}',
    ];
    b.writeln('  ${(r['beat'] as String).padRight(22)} ${bits.join(' · ')}');
  }
  b.writeln(dry
      ? '\n(미리보기 — 저장하지 않았다)'
      : saved
          ? '\n저장 완료'
          : '\n바뀐 것 없음');
  return b.toString();
}

/// 씬 안에서 이 비트가 **실제로 들려 주는** 음성의 길이(상속 포함).
extension on SceneResolver {
  double voiceSecondsOfBeat(DialogueBeat b) {
    final own = b.dialogue?.voiceSeconds ?? 0;
    if (own > 0) return own;
    return baseBeatOf(b)?.dialogue?.voiceSeconds ?? 0;
  }
}
