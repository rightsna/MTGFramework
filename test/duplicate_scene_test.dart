import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framework/storyboard.dart';

/// 씬 복제: 선택 씬을 맨 뒤에 그대로 복제하되 **원본과 완전히 분리**돼야 한다.
/// id·미디어 파일이 겹치면 복제본을 지우거나 다시 뽑을 때 원본이 깨진다.
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

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('dup');
    p = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300)); // _load
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('복제본은 맨 뒤에 붙고 선택된다', () async {
    p.addScene();
    p.sceneTitleCtrl(p.selectedSceneId!).text = '편집실';
    p.addScene(); // 다른 씬
    p.selectScene(p.scenes.first.id); // 첫 씬(편집실) 선택
    await p.duplicateScene();

    expect(p.scenes.length, 3);
    expect(p.scenes.last.title, '편집실 복사본');
    expect(p.selectedSceneId, p.scenes.last.id, reason: '복제본이 선택돼야 한다');
  });

  test('복제본은 원본과 다른 id를 쓴다(씬·대사·샷 전부)', () async {
    p.addScene();
    p.addDialogue();
    final beat = p.dialogues.single;
    await p.addShot(beat);

    final src = p.selectedScene!;
    final srcBeatIds = {for (final b in src.dialogues) b.id};
    final srcShotIds = {for (final b in src.dialogues) ...b.shots.map((s) => s.id)};

    await p.duplicateScene();
    final copy = p.scenes.last;

    expect(copy.id, isNot(src.id));
    for (final b in copy.dialogues) {
      expect(srcBeatIds, isNot(contains(b.id)));
      for (final s in b.shots) {
        expect(srcShotIds, isNot(contains(s.id)));
      }
    }
    // 구조(대사·샷 개수)는 그대로.
    expect(copy.dialogues.length, src.dialogues.length);
    expect(copy.shotCount, src.shotCount);
  });

  test('미디어는 새 파일로 복사되고 원본 파일을 건드리지 않는다', () async {
    p.addScene();
    p.addDialogue();
    final beat = p.dialogues.single;
    await p.addShot(beat);
    final shot = beat.shots.single;

    // 원본 샷에 영상 파일을 붙인다.
    final srcVideo = File('${dir.path}/${shot.id}_vlow.mp4');
    await srcVideo.writeAsBytes([1, 2, 3]);
    shot.videoPath = srcVideo.path;

    await p.duplicateScene();
    final copyShot = p.scenes.last.dialogues.single.shots.single;

    expect(copyShot.videoPath, isNotNull);
    expect(copyShot.videoPath, isNot(srcVideo.path), reason: '같은 파일을 가리키면 분리가 안 된 것');
    expect(await File(copyShot.videoPath!).exists(), isTrue);
    expect(await File(copyShot.videoPath!).readAsBytes(), [1, 2, 3]);

    // 복제본 미디어를 지워도 원본 파일은 남아 있어야 한다.
    await p.removeMedia(copyShot, GenMode.videoLow);
    expect(await srcVideo.exists(), isTrue, reason: '복제본 삭제가 원본을 지웠다');
  });

  test('파일이 없는 경로는 복제본에서 끊는다(깨진 참조 X)', () async {
    p.addScene();
    p.addDialogue();
    final beat = p.dialogues.single;
    await p.addShot(beat);
    // 경로만 있고 파일은 없는 상태.
    beat.shots.single.endImagePath = '${dir.path}/${beat.shots.single.id}_end.png';

    await p.duplicateScene();
    final copyShot = p.scenes.last.dialogues.single.shots.single;
    expect(copyShot.endImagePath, isNull);
  });

  test('씬 위로/아래로 이동 — 순서가 바뀌고 경계에서 막힌다', () async {
    p.addScene();
    p.sceneTitleCtrl(p.selectedSceneId!).text = 'A';
    p.addScene();
    p.sceneTitleCtrl(p.selectedSceneId!).text = 'B';
    p.addScene();
    p.sceneTitleCtrl(p.selectedSceneId!).text = 'C';

    List<String> order() =>
        [for (final s in p.scenes) p.sceneTitleCtrl(s.id).text];
    expect(order(), ['A', 'B', 'C']);

    // C(마지막) 선택 → 아래로는 막힘.
    expect(p.canMoveSceneDown, isFalse);
    expect(p.canMoveSceneUp, isTrue);
    await p.moveScene(-1); // C 위로
    expect(order(), ['A', 'C', 'B']);
    // 선택은 따라 움직인다(계속 C).
    expect(p.sceneTitleCtrl(p.selectedSceneId!).text, 'C');

    await p.moveScene(-1); // C 맨 위로
    expect(order(), ['C', 'A', 'B']);
    expect(p.canMoveSceneUp, isFalse);
    await p.moveScene(-1); // 더 못 감 — 그대로
    expect(order(), ['C', 'A', 'B']);

    await p.moveScene(1); // C 아래로
    expect(order(), ['A', 'C', 'B']);
  });

  test('연동(linkStart) 샷은 복제본 안에서 다시 이어진다', () async {
    p.addScene();
    p.addDialogue();
    final beat = p.dialogues.single;
    await p.addShot(beat);
    await p.addShot(beat); // 둘째 샷 = 연동 켜짐
    // 앞 샷에 끝장면을 붙인다.
    final s1 = beat.shots.first;
    final end = File('${dir.path}/${s1.id}_end.png');
    await end.writeAsBytes([5, 5, 5]);
    s1.endImagePath = end.path;

    await p.duplicateScene();
    final cShots = p.scenes.last.dialogues.single.shots;
    expect(cShots.last.linkStart, isTrue, reason: '연동 상태가 복제돼야 한다');
    // 복제본의 둘째 샷 시작 = 복제본 첫 샷의 끝(원본이 아니라).
    expect(p.startPathOf(cShots.last), cShots.first.endImagePath);
    expect(p.startPathOf(cShots.last), isNot(end.path));
  });
}
