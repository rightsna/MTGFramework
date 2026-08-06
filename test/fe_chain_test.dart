import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framework/storyboard.dart';
import 'package:framework/src/storyboard/services/video_edit.dart';

/// 컷 잇기: **앞 샷 끝 프레임으로 시작 프레임 만들기**(한 번짜리 가져오기).
/// 예전의 '연동'(앞 샷 끝 파일을 계속 가리키기)을 대신한다 — 가져온 순간 이 샷의 자기
/// 파일이라 앞 샷이 나중에 바뀌어도 따라 변하지 않는다.
///
/// 가져올 것은 앞 샷이 가진 것으로 정해진다: 끝 프레임이 있으면 그 그림, 없고 영상이
/// 있으면 그 영상의 **마지막 프레임**.
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
    await p.ready; // 첫 읽기가 끝난 뒤에 만진다(시간으로 재면 바쁜 기계에서 어긋난다)
    p.addScene();
    p.addDialogue();
  });
  tearDown(() async {
    // addScene 같은 건 저장을 기다리지 않고 던져놓는다 — 폴더를 먼저 지우면 그 저장이 터진다.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// 앞 샷 + 뒤 샷 한 쌍.
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

  /// 진짜 영상 한 개(색 클립) — 마지막 프레임 추출을 실제로 돌려 보기 위해.
  Future<String> colorClip(Shot shot, double sec) async {
    final path = '${dir.path}/${shot.id}_vlow.mp4';
    final r = await Process.run(VideoEdit.toolPath('ffmpeg')!, [
      '-y',
      '-f', 'lavfi', '-i', 'color=c=green:size=64x64:rate=24:duration=$sec',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', path,
    ]);
    expect(r.exitCode, 0, reason: '클립 실패: ${r.stderr}');
    shot.videoPath = path;
    return path;
  }

  test('첫 샷은 가져올 앞이 없다', () async {
    final beat = p.dialogues.single;
    await p.addShot(beat);
    expect(p.prevShotOf(beat.shots.single), isNull);
    expect(p.canStartFromPrevShot(beat.shots.single), isFalse);
  });

  test('앞 샷에 끝 프레임도 영상도 없으면 가져올 수 없다', () async {
    final (_, second) = await pair();
    expect(p.canStartFromPrevShot(second), isFalse);
  });

  test('앞 샷 끝 프레임을 가져오면 **이 샷의 자기 파일**이 된다 (앞이 바뀌어도 안 따라간다)',
      () async {
    final (first, second) = await pair();
    final end = await endFrameFor(first, [1, 2, 3]);
    expect(p.canStartFromPrevShot(second), isTrue);

    await p.startFromPrevShot(second);

    final start = p.startPathOf(second);
    expect(start, isNotNull);
    expect(start, isNot(end.path), reason: '★ 앞 샷 파일을 가리키지 않고 자기 파일로 복사된다');
    expect(File(start!).readAsBytesSync(), [1, 2, 3]);

    // 앞 샷의 끝을 다른 그림으로 바꿔도 이 샷 시작은 그대로다.
    await end.writeAsBytes([9, 9, 9]);
    expect(File(p.startPathOf(second)!).readAsBytesSync(), [1, 2, 3]);
  });

  test('앞 샷에 끝 프레임이 없고 영상이 있으면 마지막 프레임을 잘라 쓴다', () async {
    final (first, second) = await pair();
    await colorClip(first, 1.0); // 끝 프레임은 없고 영상만 있다(I2V·IA2V·스틸컷 자리)
    expect(p.canStartFromPrevShot(second), isTrue);

    await p.startFromPrevShot(second);

    final start = p.startPathOf(second);
    expect(start, isNotNull, reason: '★ 영상 마지막 프레임이 시작 프레임이 된다');
    expect(File(start!).existsSync(), isTrue);
    expect(File(start).lengthSync(), greaterThan(0));
    expect(start, contains(second.id), reason: '이 샷 자기 파일로 저장된다');
  }, skip: VideoEdit.available ? null : 'ffmpeg 없음');

  test('파생 트랙(트랙2)에서도 된다 — 오버라이드로만 들어가고 트랙1은 안 바뀐다', () async {
    final (first, _) = await pair();
    await endFrameFor(first, [1, 2, 3]);
    await p.save();
    final baseSecond = p.dialogues.single.shots.last;

    await p.addTrack(); // 트랙 2로 이동(파생 샷들은 비어 있고 기준을 상속)
    final shots = p.dialogues.single.shots;
    final derivedSecond = shots.last;
    expect(derivedSecond.isDerived, isTrue);
    // 앞 샷은 **같은 트랙의** 앞 샷이고, 그 끝 프레임은 기준 트랙에서 상속해 보인다.
    expect(p.prevShotOf(derivedSecond), shots.first);
    expect(p.canStartFromPrevShot(derivedSecond), isTrue);

    await p.startFromPrevShot(derivedSecond);

    // 파생 샷은 **오버라이드**로만 갖는다 — 파일도 자기 id로 따로 쓴다.
    expect(derivedSecond.overrides.containsKey(Shot.kStartImage), isTrue);
    final start = p.startPathOf(derivedSecond)!;
    expect(start, contains(derivedSecond.id));
    expect(File(start).readAsBytesSync(), [1, 2, 3]);

    // 트랙 1은 물들지 않는다.
    p.selectTrack(0);
    expect(baseSecond.startImagePath, isNull);
    expect(p.startPathOf(baseSecond), isNull);
  });

  test('끝 프레임이 있으면 영상보다 그 그림을 먼저 쓴다', () async {
    final (first, second) = await pair();
    await endFrameFor(first, [7, 7, 7]);
    await colorClip(first, 1.0);

    await p.startFromPrevShot(second);

    expect(File(p.startPathOf(second)!).readAsBytesSync(), [7, 7, 7],
        reason: '끝 프레임(FE2V)이 있으면 그게 이어지는 그림이다');
  }, skip: VideoEdit.available ? null : 'ffmpeg 없음');
}
