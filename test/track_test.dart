import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framework/storyboard.dart';

/// 트랙 = 같은 콘티를 백엔드별로 뽑아 **비교하는 단위**.
/// 지켜야 할 약속은 셋이다:
///  1. 트랙을 추가하고 아무것도 안 건드리면 **트랙 1과 똑같은 내용**이다(영상만 비어 있다).
///  2. 거기서 영상만 다시 뽑으면 **그 트랙의 영상만** 갈린다 — 트랙 1은 그대로.
///  3. 구조(비트·샷 개수)는 트랙끼리 항상 같다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final tmp = Directory.systemTemp.createTempSync('appsup').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
  });

  late Directory dir;
  late StoryboardProvider p;

  Future<File> file(String name) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes([1, 2, 3]);
    return f;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('track');
    p = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300)); // _load
    p.addScene();
    p.addDialogue();
    final beat = p.dialogues.single;
    await p.addShot(beat);
    await p.addShot(beat);
    // 트랙 1의 재료를 채워 둔다(프롬프트·프레임·영상).
    for (final s in beat.shots) {
      p.videoCtrl(s.id).text = '카메라가 밀려든다';
      p.startCtrl(s.id).text = '복도 끝';
      s.startImagePath = (await file('${s.id}_start.png')).path;
      s.endImagePath = (await file('${s.id}_end.png')).path;
      s.videoPath = (await file('${s.id}_vlow.mp4')).path;
    }
    await p.save();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('트랙을 추가하고 아무것도 안 하면 트랙 1과 똑같이 보인다', () async {
    final base = p.dialogues.single.shots.toList();
    await p.addTrack();

    expect(p.trackIndex, 1, reason: '새 트랙으로 옮겨 간다');
    expect(p.onBaseTrack, isFalse);
    // 구조가 같다.
    expect(p.dialogues.length, 1);
    final shots = p.dialogues.single.shots;
    expect(shots.length, 2);
    // 내용이 그대로 따라온다 — 프롬프트도 프레임도 트랙 1의 것.
    for (var i = 0; i < shots.length; i++) {
      expect(shots[i].inherits, isTrue);
      expect(shots[i].videoPrompt, base[i].videoPrompt);
      expect(shots[i].startPrompt, base[i].startPrompt);
      expect(shots[i].startImagePath, base[i].startImagePath);
      expect(p.videoCtrl(shots[i].id).text, '카메라가 밀려든다');
      // 영상만 비어 있다 — 트랙을 나눈 이유가 그것뿐이다.
      expect(shots[i].videoPath, isNull);
    }
    // 샷 id는 트랙마다 다르다 — 영상 파일이 서로 덮어쓰지 않도록.
    expect(shots.first.id, isNot(base.first.id));
  });

  test('트랙에서 영상만 다시 뽑으면 그 트랙 영상만 갈린다', () async {
    final base = p.dialogues.single.shots.first;
    final baseVideo = base.videoPath;
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;

    // 생성 결과가 들어오는 자리(gen()이 하는 일)를 그대로 흉내 낸다.
    derived.videoPath = (await file('${derived.id}_vlow.mp4')).path;
    await p.save();

    expect(base.videoPath, baseVideo, reason: '트랙 1 영상은 건드리지 않는다');
    // 내용은 여전히 따라간다 — 갈린 건 영상뿐.
    expect(derived.inherits, isTrue);
    expect(derived.videoPrompt, base.videoPrompt);
  });

  test('트랙의 백엔드가 그 트랙 생성 백엔드가 된다', () async {
    expect(p.backendOf(p.dialogues.single.shots.first), VideoBackend.serviceApi);
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;
    // 새 트랙은 기준 트랙과 같은 백엔드로 시작한다 — 무엇으로 뽑을지는 사람이 정한다
    // (같은 백엔드로 두 번 뽑아 비교해도 된다).
    expect(p.tracks[1].backend, VideoBackend.serviceApi);
    p.setTrackBackend(p.tracks[1], VideoBackend.veo);
    await p.save(); // 뒷정리 전에 저장이 끝나도록(설정 변경은 저장을 비동기로 건다)
    expect(p.backendOf(derived), VideoBackend.veo);
    expect(p.backendOf(p.tracks.first.beats.single.shots.first),
        VideoBackend.serviceApi,
        reason: '트랙마다 따로다');
  });

  test('기준 트랙에서 고친 내용은 따라가는 샷에 그대로 반영된다', () async {
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;
    p.selectTrack(0);
    final base = p.dialogues.single.shots.first;
    p.videoCtrl(base.id).text = '카메라가 뒤로 빠진다';
    await p.save();

    expect(derived.videoPrompt, '카메라가 뒤로 빠진다');
    expect(p.videoCtrl(derived.id).text, '카메라가 뒤로 빠진다');
  });

  test('분리하면 그 샷만 독립하고, 되돌리면 다시 따라간다', () async {
    await p.addTrack();
    final shots = p.dialogues.single.shots;
    final derived = shots.first;

    await p.detachShot(derived);
    expect(derived.detached, isTrue);
    expect(derived.inherits, isFalse);
    // 프레임은 자기 파일로 떠 온다 — 기준 샷을 지워도 안 깨지도록.
    expect(derived.startImagePath, contains(derived.id));
    expect(File(derived.startImagePath!).existsSync(), isTrue);

    p.videoCtrl(derived.id).text = '핸드헬드로 흔들린다';
    await p.save();
    p.selectTrack(0);
    expect(p.dialogues.single.shots.first.videoPrompt, '카메라가 밀려든다',
        reason: '트랙 1은 물들지 않는다');
    expect(shots.last.inherits, isTrue, reason: '분리는 샷 단위다');

    p.selectTrack(1);
    await p.relinkShot(derived);
    expect(derived.inherits, isTrue);
    expect(derived.videoPrompt, '카메라가 밀려든다');
  });

  test('비트·샷 추가/삭제는 모든 트랙에 똑같이 반영된다', () async {
    await p.addTrack();
    p.selectTrack(0);
    p.addDialogue();
    await p.addShot(p.dialogues.last);
    await p.save();

    for (final t in p.tracks) {
      expect(t.beats.length, 2);
      expect(t.beats.map((b) => b.shots.length).toList(), [2, 1]);
    }

    p.removeDialogue(p.dialogues.last);
    await p.save();
    for (final t in p.tracks) {
      expect(t.beats.length, 1);
    }
  });

  test('저장·재로딩 후에도 트랙 구성과 영상이 그대로다', () async {
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;
    derived.videoPath = (await file('${derived.id}_vlow.mp4')).path;
    p.setTrackName(p.tracks[1], 'Veo 3.1');
    p.setTrackBackend(p.tracks[1], VideoBackend.veo);
    await p.save();

    // 파일에는 따라가는 샷의 내용이 안 적힌다 — 정본은 기준 트랙 한 곳뿐.
    final raw = File('${dir.path}/scene1.json').readAsStringSync();
    expect('카메라가 밀려든다'.allMatches(raw).length, 2,
        reason: '트랙 1의 샷 2개에만 적힌다(파생 트랙엔 안 적힘)');

    final p2 = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final sc = p2.scenes.single;
    expect(sc.tracks.length, 2);
    expect(sc.tracks[1].name, 'Veo 3.1');
    expect(sc.tracks[1].backend, VideoBackend.veo);
    final back = sc.tracks[1].beats.single.shots.first;
    expect(back.inherits, isTrue);
    expect(back.videoPrompt, '카메라가 밀려든다', reason: '불러올 때 기준에서 다시 채워진다');
    expect(back.videoPath, derived.videoPath, reason: '뽑아 둔 영상은 트랙에 남는다');
    p2.dispose();
  });

  test('영상 길이는 트랙마다 따로 잡히고 타임라인이 그걸 따른다', () async {
    final beat = p.dialogues.single;
    final base = beat.shots.first;
    base.videoSeconds = 10; // 주문은 10초
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;

    // 트랙 1은 주문대로 10초, 트랙 2(예: Veo)는 4초로 나왔다고 하자.
    base.videoActualSeconds = 10.0;
    derived.videoPath = (await file('${derived.id}_vlow.mp4')).path;
    derived.videoActualSeconds = 4.0;
    await p.save();

    expect(derived.playSeconds, 4.0);
    expect(base.playSeconds, 10.0);
    expect(derived.videoSeconds, 10, reason: '주문값은 트랙끼리 공유(내용)');
    // 타임라인(비트 길이)도 그 트랙의 실제 길이로 잡힌다.
    expect(p.tracks[1].beats.single.seconds, 4.0 + p.tracks[1].beats.single.shots[1].playSeconds);
    expect(p.tracks.first.beats.single.seconds, 10.0 + beat.shots[1].playSeconds);

    // 저장·재로딩해도 트랙별 실제 길이가 남는다.
    final p2 = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final sc = p2.scenes.single;
    expect(sc.tracks[1].beats.single.shots.first.videoActualSeconds, 4.0);
    expect(sc.baseTrack.beats.single.shots.first.videoActualSeconds, 10.0);
    p2.dispose();
  });

  test('해상도는 씬별 — 한 씬을 바꿔도 다른 씬은 그대로', () async {
    // setUp이 씬 하나(scene1) 만들어 둠. 두 번째 씬 추가.
    p.addScene();
    final sc2 = p.selectedScene!;
    final sc1 = p.scenes.first;
    expect(identical(sc1, sc2), isFalse);

    // 씬2에서 해상도를 바꾼다.
    p.setImageRes(ImageRes.l1984x1088);
    p.setVideoRes(VideoRes.l1280x704);
    await p.save();

    expect(sc2.imageRes, ImageRes.l1984x1088);
    expect(sc2.videoRes, VideoRes.l1280x704);
    // 씬1은 그대로여야 한다(전역 공유 아님).
    expect(sc1.imageRes, ImageRes.p704x1280);
    expect(sc1.videoRes, VideoRes.p352x640);

    // 저장·재로딩 후에도 씬별로 남는다.
    final p2 = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final scenes = p2.scenes;
    expect(scenes[0].imageRes, ImageRes.p704x1280);
    expect(scenes[1].imageRes, ImageRes.l1984x1088);
    expect(scenes[1].videoRes, VideoRes.l1280x704);
    p2.dispose();
  });

  test('고아 미디어 정리 — 참조 끊긴 파일만 지운다', () async {
    final beat = p.dialogues.single;
    final shot = beat.shots.first;
    // 참조되는 파일들(위 setUp에서 start/end/video 이미 채움) + 고아 하나 + json은 보존.
    final orphan = await file('clip_dead_vlow.mp4');
    final keepJson = await file('characters.json'); // json은 미디어 아님 → 보존
    expect(orphan.existsSync(), isTrue);

    final n = await p.sweepOrphanMedia();
    expect(n, greaterThanOrEqualTo(1));
    expect(orphan.existsSync(), isFalse, reason: '참조 안 되는 미디어는 삭제');
    expect(File(shot.videoPath!).existsSync(), isTrue, reason: '참조되는 영상은 보존');
    expect(File(shot.startImagePath!).existsSync(), isTrue);
    expect(keepJson.existsSync(), isTrue, reason: 'json은 손대지 않는다');
  });

  test('샷을 지우면 그 샷의 미디어도 사라진다', () async {
    final beat = p.dialogues.single;
    final shot = beat.shots.first;
    final vp = shot.videoPath!;
    final sp = shot.startImagePath!;
    expect(File(vp).existsSync(), isTrue);

    p.removeShot(beat, shot);
    await p.save();
    await Future<void>.delayed(const Duration(milliseconds: 50)); // 스윕은 비동기
    expect(File(vp).existsSync(), isFalse, reason: '지운 샷의 영상은 삭제');
    expect(File(sp).existsSync(), isFalse, reason: '지운 샷의 프레임도 삭제');
  });

  test('대사 음성은 트랙별 — 한 트랙에서 재생성해도 다른 트랙은 그대로', () async {
    // 트랙 1의 비트에 대사·음성을 넣는다.
    final baseBeat = p.tracks.first.beats.single;
    p.setShotDialogueText(baseBeat, '그 밤에 무슨 일이 있었죠?');
    baseBeat.dialogue!.voicePath = (await file('${baseBeat.id}_voice.mp3')).path;
    baseBeat.dialogue!.voiceSeconds = 3.0;
    await p.addTrack(); // 트랙 2 — 대본은 따라오고 음성은 비어 있어야 한다
    await p.save();

    final derivedBeat = p.tracks[1].beats.single;
    expect(derivedBeat.dialogue?.text, '그 밤에 무슨 일이 있었죠?', reason: '대본은 공유');
    expect(derivedBeat.dialogue?.voicePath, isNull, reason: '음성은 트랙별 — 새 트랙은 비어 있음');

    // 트랙 2에서 음성을 만든다(gen이 하는 일 흉내).
    derivedBeat.dialogue!.voicePath = (await file('${derivedBeat.id}_voice.mp3')).path;
    derivedBeat.dialogue!.voiceSeconds = 4.0;
    await p.save();

    expect(baseBeat.dialogue!.voicePath, contains(baseBeat.id),
        reason: '트랙 1 음성은 그대로');
    expect(derivedBeat.dialogue!.voicePath, contains(derivedBeat.id));
    expect(p.voiceBusyKey(baseBeat.id), isNot(p.voiceBusyKey(derivedBeat.id)),
        reason: '진행 표시도 트랙별');

    // 저장·재로딩해도 트랙별 음성이 남는다.
    final p2 = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final sc = p2.scenes.single;
    expect(sc.tracks[1].beats.single.dialogue?.text, '그 밤에 무슨 일이 있었죠?',
        reason: '대본은 불러올 때 기준에서 채워진다');
    expect(sc.tracks[1].beats.single.dialogue?.voicePath,
        contains(sc.tracks[1].beats.single.id),
        reason: '트랙별 음성은 그 트랙 것으로 복원');
    expect(sc.tracks.first.beats.single.dialogue?.voicePath,
        contains(sc.tracks.first.beats.single.id));
    p2.dispose();
  });

  test('트랙을 지워도 트랙 1은 남는다', () async {
    await p.addTrack();
    expect(p.tracks.length, 2);
    await p.removeTrack(p.tracks[1]);
    expect(p.tracks.length, 1);
    expect(p.trackIndex, 0);
    // 기준 트랙은 지울 수 없다 — 구조의 정본이라서.
    await p.removeTrack(p.tracks.first);
    expect(p.tracks.length, 1);
  });
}
