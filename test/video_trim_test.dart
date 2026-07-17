import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:framework/src/storyboard/services/video_edit.dart';

/// 트림은 원본을 덮어쓰는 비가역 동작이라 경계가 한 프레임이라도 밀리면 안 된다.
/// ffmpeg으로 프레임 수를 아는 영상을 즉석에서 만들어 실제로 잘라보고 확인한다.
void main() {
  // ffmpeg이 없는 기기에서는 이 스위트가 검증할 게 없다.
  final has = VideoEdit.available;

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('trim_test');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// 24fps · [frames]프레임 · 오디오 있는 테스트 영상을 만든다.
  Future<String> makeVideo(int frames) async {
    final path = '${tmp.path}/src.mp4';
    final seconds = frames / 24;
    final r = await Process.run(VideoEdit.toolPath('ffmpeg')!, [
      '-y',
      '-f', 'lavfi', '-i', 'testsrc=size=64x64:rate=24:duration=$seconds',
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=$seconds',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac',
      '-frames:v', '$frames',
      path,
    ]);
    expect(r.exitCode, 0, reason: '테스트 영상 생성 실패: ${r.stderr}');
    return path;
  }

  test('probe가 프레임 수·fps·오디오 유무를 읽는다', () async {
    final path = await makeVideo(48);
    final info = await VideoEdit.probe(path);
    expect(info, isNotNull);
    expect(info!.frameCount, 48);
    expect(info.fps, 24);
    expect(info.hasAudio, isTrue);
    expect(info.width, 64);
  }, skip: has ? null : 'ffmpeg 없음');

  test('trim이 지정한 프레임 구간만 정확히 남긴다', () async {
    final path = await makeVideo(48);

    // 10~29번(양끝 포함) = 20프레임만 남긴다.
    final seconds = await VideoEdit.trim(path, first: 10, last: 29, fps: 24);
    expect(seconds, closeTo(20 / 24, 0.0001));

    // 원본 경로를 덮어썼고, 임시 파일은 남기지 않는다.
    expect(await File(path).exists(), isTrue);
    expect(await File('$path.trim.mp4').exists(), isFalse);

    final info = await VideoEdit.probe(path);
    expect(info!.frameCount, 20, reason: '경계가 밀리면 19나 21이 된다');
    expect(info.hasAudio, isTrue, reason: '오디오도 함께 살아 있어야 한다');
    expect(info.duration, closeTo(20 / 24, 0.02));
  }, skip: has ? null : 'ffmpeg 없음');

  test('구간이 뒤집히면 자르지 않고 예외를 던진다', () async {
    final path = await makeVideo(24);
    await expectLater(
      VideoEdit.trim(path, first: 20, last: 5, fps: 24),
      throwsA(isA<Exception>()),
    );
    // 원본은 손대지 않았다.
    expect((await VideoEdit.probe(path))!.frameCount, 24);
  }, skip: has ? null : 'ffmpeg 없음');
}
