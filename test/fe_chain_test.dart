import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framework/storyboard.dart';

/// FE2V 컷 연속성: 샷의 시작장면은 앞 샷의 끝장면에 **연동**된다(복사본이 아니라 그 파일 자체).
/// 연동 중엔 앞 샷의 끝이 바뀌면 즉시 따라오고, 없어지면 같이 없어진다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 설정 저장소(path_provider)는 이 테스트의 관심사가 아니다 — 임시 폴더로 스텁.
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

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('chain');
    p = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300)); // _load
    p.addScene();
    p.addDialogue();
  });
  tearDown(() async {
    // addScene 같은 건 저장을 기다리지 않고 던져놓는다 — 폴더를 먼저 지우면 그 저장이 터진다.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// 앞 샷 + 뒤 샷 한 쌍. 뒤 샷은 기본으로 연동이 켜진 채 생긴다.
  Future<(Shot, Shot)> pair() async {
    final beat = p.dialogues.single;
    await p.addShot(beat);
    final first = beat.shots.single;
    await p.addShot(beat);
    return (first, beat.shots.last);
  }

  Future<File> endFrameFor(Shot shot, List<int> bytes) async {
    final f = File('${dir.path}/${shot.id}_end.png');
    await f.writeAsBytes(bytes);
    shot.endImagePath = f.path;
    return f;
  }

  test('새 샷은 연동이 켜진 채로 생기고, 첫 샷은 꺼져 있다', () async {
    final (s1, s2) = await pair();
    expect(s1.linkStart, isFalse, reason: '첫 샷은 연동할 앞이 없다');
    expect(s2.linkStart, isTrue, reason: '컷은 이어지는 게 기본이다');
  });

  test('연동된 시작장면은 앞 샷의 끝장면 파일 그 자체다', () async {
    final (s1, s2) = await pair();
    final end = await endFrameFor(s1, [1, 2, 3]);

    expect(p.startPathOf(s2), end.path, reason: '복사본이 아니라 앞 샷의 끝을 그대로 가리켜야 한다');
    expect(s2.startImagePath, isNull, reason: '연동 중엔 자기 파일을 만들지 않는다');
  });

  test('앞 샷의 끝장면이 바뀌면 시작장면도 따라 바뀐다', () async {
    final (s1, s2) = await pair();
    await endFrameFor(s1, [1, 1, 1]);

    // 끝장면을 다른 파일로 교체 — 연동이면 별도 조치 없이 따라와야 한다.
    final other = File('${dir.path}/other_end.png');
    await other.writeAsBytes([9, 9, 9]);
    s1.endImagePath = other.path;

    expect(p.startPathOf(s2), other.path);
  });

  test('앞 샷의 끝장면이 없어지면 시작장면도 없다', () async {
    final (s1, s2) = await pair();
    await endFrameFor(s1, [1, 2, 3]);
    expect(p.startPathOf(s2), isNotNull);

    s1.endImagePath = null; // 앞 샷의 끝을 지운 상황
    expect(p.startPathOf(s2), isNull, reason: '이어받을 게 없어졌으면 없는 게 사실이다');
  });

  test('첫 샷은 연동을 켤 수 없다', () async {
    final (s1, _) = await pair();
    await p.setLinkStart(s1, true);
    expect(s1.linkStart, isFalse, reason: '물려받을 앞이 없는데 켜졌다');
  });

  test('연동을 끄면 보고 있던 프레임이 자기 파일로 남는다', () async {
    final (s1, s2) = await pair();
    final end = await endFrameFor(s1, [4, 5, 6]);

    await p.setLinkStart(s2, false);

    expect(s2.linkStart, isFalse);
    expect(s2.startImagePath, isNotNull, reason: '끄자마자 프레임이 사라지면 안 된다');
    expect(s2.startImagePath, isNot(end.path), reason: '앞 샷 파일을 가리키면 연동을 끈 게 아니다');
    expect(await File(s2.startImagePath!).readAsBytes(), await end.readAsBytes());

    // 이제 앞 샷의 끝이 바뀌어도 따라가지 않는다.
    final other = File('${dir.path}/other_end.png');
    await other.writeAsBytes([7, 7, 7]);
    s1.endImagePath = other.path;
    expect(p.startPathOf(s2), s2.startImagePath);
  });

  test('직접 만든 시작장면이 있으면 연동을 껐다 켜도 그게 돌아온다', () async {
    final (s1, s2) = await pair();
    await endFrameFor(s1, [4, 5, 6]);

    // 연동을 끄고 자기만의 시작장면을 잡아둔다.
    await p.setLinkStart(s2, false);
    final own = File('${dir.path}/own.png');
    await own.writeAsBytes([8, 8, 8]);
    s2.startImagePath = own.path;

    // 켜면 앞 샷을 따라가고…
    await p.setLinkStart(s2, true);
    expect(p.startPathOf(s2), s1.endImagePath);

    // …다시 끄면 원래 자기 것으로 돌아온다(연동이 지워버리지 않았다).
    await p.setLinkStart(s2, false);
    expect(p.startPathOf(s2), own.path);
  });

  test('연동을 켜면 앞 샷의 끝 프롬프트가 시작 프롬프트로 따라온다', () async {
    final (s1, s2) = await pair();

    // 앞 샷의 끝 프롬프트를 나중에 고쳐도 — 이미지 생성 같은 계기가 없어도 —
    // 저장 시점에 연동된 시작 프롬프트가 맞춰져야 한다.
    p.endCtrl(s1.id).text = '복도 끝, 문이 열린다';
    await p.save();

    expect(s2.startPrompt, '복도 끝, 문이 열린다');
    expect(p.startCtrl(s2.id).text, '복도 끝, 문이 열린다', reason: '화면(컨트롤러)도 따라와야 한다');

    // 연동을 끄면 그 뒤 변경은 안 따라온다(지금 값은 그대로 남는다).
    await p.setLinkStart(s2, false);
    p.endCtrl(s1.id).text = '완전히 다른 장면';
    await p.save();
    expect(s2.startPrompt, '복도 끝, 문이 열린다');
  });

  test('선택 씬이 아니어도 연동이 살아 있다', () async {
    // 일괄 생성은 안 열어 본 씬까지 훑는다 — 그때 앞 샷을 못 찾으면 연동이 끊긴 것처럼 보인다.
    final (s1, s2) = await pair();
    final end = await endFrameFor(s1, [1, 2, 3]);

    p.addScene(); // 선택 씬이 새 씬으로 옮겨간다
    expect(p.selectedSceneId, isNot(p.scenes.first.id));

    expect(p.startPathOf(s2), end.path, reason: '다른 씬을 보고 있다고 연동이 끊기면 안 된다');
  });
}
