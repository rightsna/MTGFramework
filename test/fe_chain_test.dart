import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framework/storyboard.dart';

/// FE2V 컷 연속성: 새 샷을 추가하면 앞 샷의 끝 프레임을 시작으로 물려받아야 한다.
/// (반대 방향인 '끝을 만들면 다음 샷 시작으로 밀기'는 _chainEndToNextStart 가 담당.)
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
  test('새 샷 추가 시 앞 샷 끝 프레임을 시작으로 물려받는다', () async {
    final dir = Directory.systemTemp.createTempSync('chain');
    // 앞 샷의 끝 프레임 파일을 만들어 둔다.
    final endFile = File('${dir.path}/s1_end.png');
    await endFile.writeAsBytes(List<int>.generate(64, (i) => i));

    final p = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300)); // _load

    p.addScene();
    p.addDialogue();
    final beat = p.dialogues.single;

    await p.addShot(beat);                       // 첫 샷
    final s1 = beat.shots.single;
    s1.endImagePath = endFile.path;              // 끝 프레임 보유

    await p.addShot(beat);                       // 둘째 샷 추가 → 물려받아야 함
    final s2 = beat.shots.last;

    expect(s2.startImagePath, isNotNull, reason: '앞 샷 끝을 시작으로 못 가져옴');
    expect(await File(s2.startImagePath!).exists(), isTrue);
    expect(await File(s2.startImagePath!).readAsBytes(),
        await endFile.readAsBytes(),
        reason: '내용이 앞 샷 끝 프레임과 같아야 함');

    // 첫 샷은 물려받을 앞이 없어야 한다.
    expect(s1.startImagePath, isNull);
    dir.deleteSync(recursive: true);
  });
}
