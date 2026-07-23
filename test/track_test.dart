import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framework/storyboard.dart';

/// 트랙 = 같은 콘티를 백엔드별로 뽑아 **비교하는 단위**. 상속 모델의 약속:
///  1. 트랙을 추가하면 파생 트랙은 **진짜로 비어 있다**(overrides={}) — 읽을 땐 기준 트랙을 상속.
///  2. 어떤 필드를 고치면 **그 필드만** 이 트랙 것으로 오버라이드되고, **트랙 1은 절대 안 바뀐다**.
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
    // 트랙 1의 재료를 채워 둔다(프롬프트·프레임·영상). 편집칸→save로 기준 타입 필드에 굳힌다.
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

  test('트랙을 추가하면 파생 트랙은 비어 있고(overrides={}) 기준을 상속한다', () async {
    final base = p.dialogues.single.shots.toList();
    await p.addTrack();

    expect(p.trackIndex, 1, reason: '새 트랙으로 옮겨 간다');
    expect(p.onBaseTrack, isFalse);
    // 구조가 같다.
    expect(p.dialogues.length, 1);
    final shots = p.dialogues.single.shots;
    expect(shots.length, 2);
    for (var i = 0; i < shots.length; i++) {
      final d = shots[i];
      // 파생 샷은 진짜로 비어 있다 — 복사본이 아니다.
      expect(d.overrides, isEmpty, reason: '아무것도 오버라이드 안 함');
      expect(d.videoPrompt, '', reason: '타입 필드에 복사해 들고 있지 않는다');
      // 읽을 땐(리졸버) 기준 트랙 값을 상속한다.
      expect(p.shotVideoPrompt(d), base[i].videoPrompt);
      expect(p.shotStartPrompt(d), base[i].startPrompt);
      expect(p.shotStartImage(d), base[i].startImagePath);
      // 편집칸도 상속 값을 시드로 보여 준다.
      expect(p.videoCtrl(d.id).text, '카메라가 밀려든다');
      // 영상만 비어 있다 — 트랙을 나눈 이유가 그것뿐이다.
      expect(d.videoPath, isNull);
    }
    // 샷 id는 트랙마다 다르다 — 영상 파일이 서로 덮어쓰지 않도록.
    expect(shots.first.id, isNot(base.first.id));
  });

  test('트랙에서 영상만 다시 뽑으면 그 트랙 영상만 갈린다 — 내용은 여전히 상속', () async {
    final base = p.dialogues.single.shots.first;
    final baseVideo = base.videoPath;
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;

    derived.videoPath = (await file('${derived.id}_vlow.mp4')).path;
    await p.save();

    expect(base.videoPath, baseVideo, reason: '트랙 1 영상은 건드리지 않는다');
    // 영상은 오버라이드가 아니다 — 내용은 여전히 기준을 상속.
    expect(derived.overrides, isEmpty);
    expect(p.shotVideoPrompt(derived), p.shotVideoPrompt(base));
  });

  test('파생 샷의 한 필드만 고치면 그 필드만 오버라이드되고 트랙1은 안 바뀐다', () async {
    await p.addTrack();
    final shots = p.dialogues.single.shots;
    final derived = shots.first;

    // 이 트랙에서 영상 프롬프트만 고친다(UI = 그 샷 선택 + 편집칸 + save).
    p.selectShot(p.dialogues.single.id, derived.id);
    p.videoCtrl(derived.id).text = '핸드헬드로 흔들린다';
    await p.save();

    // 그 필드만 오버라이드.
    expect(derived.overrides.keys, contains('videoPrompt'));
    expect(p.shotVideoPrompt(derived), '핸드헬드로 흔들린다');
    // 나머지 필드는 여전히 상속(오버라이드 안 됨).
    expect(derived.overrides.containsKey('startPrompt'), isFalse);
    expect(p.shotStartPrompt(derived), '복도 끝');
    // 트랙 1은 물들지 않는다.
    p.selectTrack(0);
    expect(p.shotVideoPrompt(p.dialogues.single.shots.first), '카메라가 밀려든다');
    // 다른 샷은 여전히 통째로 상속.
    expect(shots.last.overrides, isEmpty);
  });

  test('⭐ 트랙2에서 화자·텍스트·제목·효과음을 바꿔도 트랙1은 하나도 안 바뀐다', () async {
    final baseBeat = p.tracks.first.beats.single;
    p.setShotDialogueText(baseBeat, '원래 대사');
    p.setShotDialogueSpeaker(baseBeat, null); // 내레이션
    p.titleCtrl(baseBeat.id).text = '원래 제목';
    p.setSfxPrompt(baseBeat, '천둥소리');
    await p.save();

    await p.addTrack();
    final derivedBeat = p.tracks[1].beats.single;

    // 트랙 2에서 전부 다른 값으로.
    p.setShotDialogueSpeaker(derivedBeat, 'char_kim'); // ← 유저가 발견한 그 버그
    p.setShotDialogueText(derivedBeat, '다른 대사');
    p.titleCtrl(derivedBeat.id).text = '다른 제목';
    p.setSfxPrompt(derivedBeat, '빗소리');
    await p.save();

    // 트랙 1(기준)은 하나도 안 바뀐다.
    expect(baseBeat.dialogue?.text, '원래 대사');
    expect(baseBeat.dialogue?.speakerId, isNull, reason: '★ 화자가 트랙1로 새지 않는다');
    expect(baseBeat.title, '원래 제목');
    expect(baseBeat.sfx?.prompt, '천둥소리');

    // 트랙 2는 자기 것으로 바뀐다.
    expect(p.beatScript(derivedBeat)?.speakerId, 'char_kim');
    expect(p.beatScript(derivedBeat)?.text, '다른 대사');
    expect(p.beatTitle(derivedBeat), '다른 제목');
    expect(p.sfxOf(derivedBeat)?.prompt, '빗소리');
  });

  test('기준 트랙에서 고치면 상속 중인 파생 샷 읽기값·편집칸이 따라온다', () async {
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;
    p.selectTrack(0);
    final base = p.dialogues.single.shots.first;
    p.videoCtrl(base.id).text = '카메라가 뒤로 빠진다';
    await p.save();

    expect(p.shotVideoPrompt(derived), '카메라가 뒤로 빠진다');
    expect(p.videoCtrl(derived.id).text, '카메라가 뒤로 빠진다',
        reason: '상속 중인 편집칸은 기준을 따라 갱신된다');
  });

  test('트랙의 백엔드가 그 트랙 생성 백엔드가 된다', () async {
    expect(p.backendOf(p.dialogues.single.shots.first), VideoBackend.serviceApi);
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;
    expect(p.tracks[1].backend, VideoBackend.serviceApi);
    p.setTrackBackend(p.tracks[1], VideoBackend.veo);
    await p.save();
    expect(p.backendOf(derived), VideoBackend.veo);
    expect(p.backendOf(p.tracks.first.beats.single.shots.first),
        VideoBackend.serviceApi,
        reason: '트랙마다 따로다');
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

  test('저장·재로딩 후에도 파생 트랙은 스파스이고 영상·오버라이드가 남는다', () async {
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;
    derived.videoPath = (await file('${derived.id}_vlow.mp4')).path;
    p.selectShot(p.dialogues.single.id, derived.id);
    p.videoCtrl(derived.id).text = '핸드헬드'; // 프롬프트만 오버라이드
    p.setTrackName(p.tracks[1], 'Veo 3.1');
    p.setTrackBackend(p.tracks[1], VideoBackend.veo);
    await p.save();

    // 파일에는 파생 샷의 상속 필드가 안 적힌다 — 기준 트랙 2곳 + (오버라이드는 파생에 1곳).
    final raw = File('${dir.path}/scene1.json').readAsStringSync();
    expect('카메라가 밀려든다'.allMatches(raw).length, 2,
        reason: '기준 트랙 샷 2개에만 적힌다(파생은 오버라이드만)');

    final p2 = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final sc = p2.scenes.single;
    expect(sc.tracks.length, 2);
    expect(sc.tracks[1].name, 'Veo 3.1');
    final back = sc.tracks[1].beats.single.shots.first;
    expect(back.overrides.keys, contains('videoPrompt'), reason: '오버라이드는 남는다');
    expect(back.overrides.containsKey('startPrompt'), isFalse, reason: '상속 필드는 저장 안 됨');
    expect(p2.shotVideoPrompt(back), '핸드헬드');
    expect(p2.shotStartPrompt(back), '복도 끝', reason: '상속 필드는 기준에서 다시 읽힌다');
    expect(back.videoPath, derived.videoPath, reason: '뽑아 둔 영상은 트랙에 남는다');
    p2.dispose();
  });

  test('영상 길이는 트랙마다 따로 잡히고 타임라인이 그걸 따른다', () async {
    final beat = p.dialogues.single;
    final base = beat.shots.first;
    base.videoSeconds = 10; // 주문은 10초
    base.videoActualSeconds = 10.0;
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;

    // 트랙 2(예: Veo)는 4초로 나왔다고 하자.
    derived.videoPath = (await file('${derived.id}_vlow.mp4')).path;
    derived.videoActualSeconds = 4.0;
    await p.save();

    expect(p.shotDisplaySeconds(derived), 4.0);
    expect(p.shotDisplaySeconds(base), 10.0);
    expect(p.shotVideoSeconds(derived), 10, reason: '주문 길이는 상속(오버라이드 안 함)');

    // 저장·재로딩해도 트랙별 실제 길이가 남는다.
    final p2 = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final sc = p2.scenes.single;
    expect(sc.tracks[1].beats.single.shots.first.videoActualSeconds, 4.0);
    expect(sc.baseTrack.beats.single.shots.first.videoActualSeconds, 10.0);
    p2.dispose();
  });

  test('파생 트랙 영상을 트랙1로 복사 — 기준 트랙이 그 파일을 자기 것으로 갖는다', () async {
    final beat = p.dialogues.single;
    final base = beat.shots.first;
    base.videoPath = null; // 트랙1은 아직 영상 없음
    await p.addTrack();
    final derived = p.dialogues.single.shots.first;
    derived.videoPath = (await file('${derived.id}_vlow.mp4')).path;
    derived.videoActualSeconds = 4.0;
    await p.save();

    await p.copyVideoToBase(derived);

    expect(base.videoPath, isNotNull);
    expect(base.videoPath, isNot(derived.videoPath));
    expect(base.videoPath!.contains('${base.id}_vlow'), isTrue);
    expect(File(base.videoPath!).existsSync(), isTrue);
    expect(base.videoActualSeconds, 4.0, reason: '원본 실측 길이를 그대로 가져온다');
  });

  test('대사 음성은 트랙별 — 대본은 상속, 음성은 그 트랙 것', () async {
    final baseBeat = p.tracks.first.beats.single;
    p.setShotDialogueText(baseBeat, '그 밤에 무슨 일이 있었죠?');
    baseBeat.dialogue!.voicePath = (await file('${baseBeat.id}_voice.mp3')).path;
    baseBeat.dialogue!.voiceSeconds = 3.0;
    await p.addTrack();
    await p.save();

    final derivedBeat = p.tracks[1].beats.single;
    expect(p.beatScript(derivedBeat)?.text, '그 밤에 무슨 일이 있었죠?',
        reason: '대본은 상속');
    expect(derivedBeat.dialogue?.voicePath, isNull,
        reason: '음성은 트랙별 — 새 트랙은 비어 있음');

    // 트랙 2에서 음성을 만든다(gen이 하는 일 흉내).
    derivedBeat.dialogue = Dialogue(
      voicePath: (await file('${derivedBeat.id}_voice.mp3')).path,
      voiceSeconds: 4.0,
    );
    await p.save();

    expect(baseBeat.dialogue!.voicePath, contains(baseBeat.id),
        reason: '트랙 1 음성은 그대로');
    expect(derivedBeat.dialogue!.voicePath, contains(derivedBeat.id));

    // 저장·재로딩해도 트랙별 음성이 남고, 대본은 기준에서 상속된다.
    final p2 = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final sc = p2.scenes.single;
    final b1 = sc.tracks[1].beats.single;
    expect(p2.beatScript(b1)?.text, '그 밤에 무슨 일이 있었죠?');
    expect(b1.dialogue?.voicePath, contains(b1.id));
    p2.dispose();
  });

  test('고아 미디어 정리 — 파생 오버라이드 프레임도 살린다', () async {
    final beat = p.dialogues.single;
    final shot = beat.shots.first;
    await p.addTrack();
    // 파생 샷에 자기 시작 프레임을 오버라이드(gen이 하는 일).
    final derived = p.dialogues.single.shots.first;
    final derivedFrame = await file('${derived.id}_start.png');
    p.selectTrack(1);
    // loadFrame 대신 직접 오버라이드 세팅(파일 I/O 다이얼로그 회피).
    derived.overrides['startImage'] = derivedFrame.path;
    await p.save();

    final orphan = await file('clip_dead_vlow.mp4');
    final n = await p.sweepOrphanMedia();
    expect(n, greaterThanOrEqualTo(1));
    expect(orphan.existsSync(), isFalse, reason: '참조 안 되는 미디어는 삭제');
    expect(File(shot.videoPath!).existsSync(), isTrue, reason: '기준 영상 보존');
    expect(derivedFrame.existsSync(), isTrue, reason: '★ 파생 오버라이드 프레임도 보존');
  });

  test('트랙2 음성 생성 — 상속받은 대사를 인식한다(대사 입력 요구 안 함)', () async {
    final baseBeat = p.tracks.first.beats.single;
    p.setShotDialogueText(baseBeat, '상속되는 대사');
    await p.addTrack();
    final derivedBeat = p.tracks[1].beats.single;

    final msgs = <String>[];
    p.messenger = msgs.add;
    // 키가 없어 뒤(일레븐랩스)에서 멈추지만, **대사 체크는 통과**해야 한다(상속 대사 인식).
    await p.genVoice(derivedBeat);

    expect(msgs, isNot(contains('대사를 먼저 입력하세요')),
        reason: '★ 파생 비트의 상속 대사를 인식해야 한다');
    expect(msgs.any((m) => m.contains('일레븐랩스')), isTrue,
        reason: '대사 체크를 지나 키 없음에서 멈춘다 = 대사는 인식됨');
  });

  test('트랙을 지워도 트랙 1은 남는다', () async {
    await p.addTrack();
    expect(p.tracks.length, 2);
    await p.removeTrack(p.tracks[1]);
    expect(p.tracks.length, 1);
    expect(p.trackIndex, 0);
    await p.removeTrack(p.tracks.first);
    expect(p.tracks.length, 1);
  });
}
