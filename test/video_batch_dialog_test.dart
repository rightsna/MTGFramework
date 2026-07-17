import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framework/src/storyboard/screens/common/video_batch.dart';
import 'package:framework/storyboard.dart';

/// '모든 씬 영상 생성' 다이얼로그는 Navigator 위에 떠서 StoryboardScope **바깥**에 뜬다.
/// 스코프를 다시 씌워주지 않으면 여는 순간 터진다 — 그 회귀를 막는다.
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

  testWidgets('모든 씬 다이얼로그가 스코프 밖에서도 열린다', (tester) async {
    final dir = Directory.systemTemp.createTempSync('batchdlg');
    final p = StoryboardProvider(projectDirPath: dir.path);
    await tester.pump(const Duration(milliseconds: 300)); // _load
    p.addScene();
    p.addDialogue();

    await tester.pumpWidget(
      MaterialApp(
        home: StoryboardScope(
          notifier: p,
          child: Scaffold(
            body: Builder(
              // 버튼은 스코프 안, 다이얼로그는 스코프 밖 — 실제 씬 목록과 같은 구조.
              builder: (ctx) => ElevatedButton(
                onPressed: () => showAllScenesVideoDialog(ctx),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '스코프를 못 찾아 터지면 안 된다');
    expect(find.text('모든 씬 영상 생성'), findsOneWidget);
    // 스코프가 제대로 붙었다면 프로바이더를 읽어야 나오는 내용이 그려진다.
    expect(find.text('이미 생성된 영상 건너뛰기'), findsOneWidget);

    p.dispose();
    dir.deleteSync(recursive: true);
  });
}
