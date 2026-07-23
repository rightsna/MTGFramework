import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framework/storyboard.dart';

/// 씬 일괄 영상 생성 계획: 어떤 샷이 돌고(ready) 뭐가 빠졌고(blocked) 뭘 건너뛸지(skipped).
/// 생성은 GPU 시간이 드는 일이라, 이 판정이 틀리면 돈이 새거나 덮어쓰면 안 될 걸 덮는다.
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

  /// 샷 하나를 만들고 재료를 채운다. FE2V는 시작·끝 프레임 + 프롬프트가 다 있어야 돈다.
  Future<Shot> makeShot(
    DialogueBeat beat, {
    bool start = true,
    bool end = true,
    String prompt = '카메라가 천천히 밀려든다',
    bool video = false,
  }) async {
    await p.addShot(beat);
    final s = beat.shots.last;
    // addShot이 앞 샷 끝 프레임을 물려줄 수 있으니 항상 명시적으로 세팅한다.
    s.startImagePath = start ? (await file('${s.id}_start.png')).path : null;
    s.endImagePath = end ? (await file('${s.id}_end.png')).path : null;
    s.videoPath = video ? (await file('${s.id}_vlow.mp4')).path : null;
    p.videoCtrl(s.id).text = prompt;
    return s;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('plan');
    p = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300)); // _load
    p.addScene();
    p.addDialogue();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('재료가 다 있는 샷은 ready로 잡힌다', () async {
    final beat = p.dialogues.single;
    await makeShot(beat);
    await makeShot(beat);

    final plan = p.sceneVideoPlan(skipExisting: false);
    expect(plan.ready.length, 2);
    expect(plan.blocked, isEmpty);
    expect(plan.skipped, isEmpty);
  });

  test('스틸컷은 시작 프레임 한 장이면 ready — 끝 프레임·프롬프트 없어도 된다', () async {
    final beat = p.dialogues.single;
    // 끝 프레임도 프롬프트도 없지만 스틸컷이면 시작 한 장으로 충분하다.
    final s = await makeShot(beat, end: false, prompt: '');
    s.videoMode = VideoMode.still;

    final plan = p.sceneVideoPlan(skipExisting: false);
    expect(plan.ready.single, same(s));
    expect(plan.blocked, isEmpty);
  });

  test('프레임·프롬프트가 빠지면 blocked로 빠지고 이유가 붙는다', () async {
    final beat = p.dialogues.single;
    await makeShot(beat); // 정상
    await makeShot(beat, end: false); // 끝장면 없음
    await makeShot(beat, start: false, prompt: ''); // 시작장면 + 프롬프트 없음

    final plan = p.sceneVideoPlan(skipExisting: false);
    expect(plan.ready.length, 1);
    expect(plan.blocked.length, 2);
    expect(plan.blocked[0].missing, ['끝 프레임']);
    expect(plan.blocked[1].missing, ['시작 프레임', '영상 프롬프트']);
    // 이유는 사람이 보는 경고에 그대로 나가므로 라벨도 붙어 있어야 한다.
    expect(plan.blocked[0].label, isNotEmpty);
  });

  test('경로만 있고 파일이 없으면 준비된 걸로 치지 않는다', () async {
    final beat = p.dialogues.single;
    final s = await makeShot(beat);
    await File(s.endImagePath!).delete(); // 파일만 사라진 상황

    final plan = p.sceneVideoPlan(skipExisting: false);
    expect(plan.ready, isEmpty);
    expect(plan.blocked.single.missing, ['끝 프레임']);
  });

  test('건너뛰기를 켜면 영상 있는 샷은 skipped, 끄면 덮어쓸 대상', () async {
    final beat = p.dialogues.single;
    await makeShot(beat, video: true); // 이미 영상 있음
    await makeShot(beat); // 아직 없음

    final on = p.sceneVideoPlan(skipExisting: true);
    expect(on.ready.length, 1);
    expect(on.skipped.length, 1);

    final off = p.sceneVideoPlan(skipExisting: false);
    expect(off.ready.length, 2, reason: '끄면 있는 것도 다시 만든다');
    expect(off.skipped, isEmpty);
  });

  test('씬 공통 프롬프트만 있어도 프롬프트는 채워진 것으로 본다', () async {
    final beat = p.dialogues.single;
    await makeShot(beat, prompt: ''); // 샷 프롬프트는 비었지만…
    p.selectedScene!.commonPrompt = '1998년 방송국, 필름 그레인'; // …씬 공통이 있다

    final plan = p.sceneVideoPlan(skipExisting: false);
    expect(plan.ready.length, 1);
    expect(plan.blocked, isEmpty);
  });

  test('계획은 선택된 씬만 본다(다른 씬은 안 섞인다)', () async {
    await makeShot(p.dialogues.single); // SCENE 1: 샷 1개

    p.addScene(); // SCENE 2로 이동 → 이제 이게 선택 씬
    p.addDialogue();
    await makeShot(p.dialogues.single);
    await makeShot(p.dialogues.single, end: false); // 준비 안 된 샷

    expect(p.scenes.length, 2);
    final plan = p.sceneVideoPlan(skipExisting: false);
    expect(plan.ready.length, 1, reason: 'SCENE 2의 준비된 샷만');
    expect(plan.blocked.length, 1);
  });
}
