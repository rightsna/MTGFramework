import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framework/storyboard.dart';
import 'package:framework/src/storyboard/screens/canvas/canvas_view.dart';

/// 캔버스는 **트랙 하나를 씬 한 벌**로 그린다 — 비트 카드가 가로로 이어진 줄이 트랙 수만큼
/// 아래로 쌓여, 같은 칸끼리 위아래로 견줄 수 있다.
/// 트랙을 고르는 별도 UI는 없고, 누른 샷의 트랙이 곧 선택 트랙이 된다.
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
    dir = Directory.systemTemp.createTempSync('canvas');
    p = StoryboardProvider(projectDirPath: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 300)); // _load
    p.addScene();
    p.addDialogue();
    await p.addShot(p.dialogues.single);
    await p.addShot(p.dialogues.single);
    await p.addTrack(); // 트랙 2(Veo) — 아무것도 안 건드린 상태
    p.selectTrack(0);
  });
  tearDown(() {
    p.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<void> pumpCanvas(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StoryboardScope(
        notifier: p,
        child: AnimatedBuilder(
          animation: p,
          builder: (_, _) => const Scaffold(body: CanvasView()),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('씬 한 벌이 트랙 수만큼 통째로 쌓인다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1400));
    await pumpCanvas(tester);

    // 트랙 줄 머리말이 둘. ('트랙 2'는 씬 상태 알약의 "트랙 2"(트랙 개수)와 문자열이 겹쳐
    // 헤더 + 알약 = 2개로 잡힌다. '트랙 1'은 헤더뿐이라 하나.)
    expect(find.text('트랙 1'), findsOneWidget);
    expect(find.text('트랙 2'), findsNWidgets(2));
    // 새 트랙은 기준 트랙과 같은 백엔드로 시작한다(강제로 다른 걸 물리지 않는다).
    expect(find.text('자체서버'), findsNWidgets(2));
    // 씬이 통째로 한 벌 더 깔린다 — 비트 카드도 대사 상자도 트랙마다 하나씩.
    expect(find.text('비트 1'), findsNWidgets(2));
    expect(find.text('대사 입력'), findsNWidgets(2));
    expect(find.text('영상 0/2'), findsNWidgets(2));
  });

  testWidgets('샷을 누르면 그 샷의 트랙이 선택 트랙이 된다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1400));
    await pumpCanvas(tester);
    expect(p.trackIndex, 0);

    // 아래 줄(트랙 2)의 첫 샷을 누른다.
    final track2Shot = p.tracks[1].beats.single.shots.first;
    await tester.tap(find.byKey(ValueKey('shot_${track2Shot.id}')));
    await tester.pump();

    expect(p.trackIndex, 1, reason: '트랙을 고르는 자리가 따로 없다 — 누른 샷이 곧 트랙');
    expect(p.selectedShotId, track2Shot.id);
    expect(p.selectedShot, same(track2Shot));
  });

  testWidgets('구조를 바꾸는 자리는 기준 트랙 줄에만 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1400));
    await pumpCanvas(tester);

    // ＋ 타일은 트랙 1 줄에 하나뿐(구조는 기준 트랙에서만 고친다).
    expect(find.byKey(const ValueKey('addShot')), findsOneWidget);
    // 샷 삭제(×)는 기준 트랙 샷 2개에만.
    expect(find.byIcon(Icons.close), findsNWidgets(2));
    // 휴지통은 둘: 기준 트랙의 '비트 삭제' 하나 + 파생 트랙의 '트랙 삭제' 하나.
    expect(find.byTooltip('비트 삭제'), findsOneWidget);
    expect(find.byTooltip('트랙 삭제'), findsOneWidget);
  });

  testWidgets('트랙 삭제 버튼으로 그 트랙만 사라진다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1400));
    await pumpCanvas(tester);
    expect(p.tracks.length, 2);

    await tester.tap(find.byTooltip('트랙 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(p.tracks.length, 1);
    expect(find.text('트랙 2'), findsNothing);
    expect(find.text('비트 1'), findsOneWidget, reason: '남은 트랙 1은 그대로');
  });
}
