import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:framework/src/storyboard/services/video_edit.dart';

/// 자막(캡션)이 내보내기에서 영상 위에 실제로 구워지는지 — 진짜 ffmpeg(subtitles/libass)로 확인한다.
/// (libass가 안 깔린 빌드면 subtitles 필터에서 에러가 나므로, 산출물이 나오면 파이프라인이 산다.)
void main() {
  final has = VideoEdit.available;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cap_export');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> makeClip(double seconds) async {
    final path = '${tmp.path}/clip_${seconds.toStringAsFixed(2)}.mp4';
    final r = await Process.run(VideoEdit.toolPath('ffmpeg')!, [
      '-y',
      '-f', 'lavfi', '-i', 'color=c=navy:size=128x128:rate=24:duration=$seconds',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
      path,
    ]);
    expect(r.exitCode, 0, reason: '클립 생성 실패: ${r.stderr}');
    return path;
  }

  test('한글 자막이 영상 위에 구워진 산출물이 나온다', () async {
    final clip = await makeClip(2.0);
    final out = '${tmp.path}/out.mp4';

    await VideoEdit.exportScene(
      beats: [
        ExportBeat(
          clips: [clip],
          caption: const ExportCaption(
            cues: [
              (seconds: 1.0, text: '첫 번째 자막'),
              (seconds: 1.0, text: '두 번째 자막'),
            ],
            position: 'bottom',
          ),
        ),
      ],
      width: 128,
      height: 128,
      outPath: out,
    );

    expect(await File(out).exists(), isTrue, reason: 'subtitles 필터가 살아 있어야 산출물이 나온다');
    final info = await VideoEdit.probe(out);
    expect(info, isNotNull);
    expect(info!.duration, closeTo(2.0, 0.2), reason: '길이는 유지된다');
    // 임시 자막 폴더는 정리된다(경로에 특수문자 없는 systemTemp에 만들었다).
  }, skip: has ? null : 'ffmpeg 없음');

  test('자막이 전부 공백이면 그냥 통과(자막 없이 산출)', () async {
    final clip = await makeClip(1.0);
    final out = '${tmp.path}/out2.mp4';
    await VideoEdit.exportScene(
      beats: [
        ExportBeat(
          clips: [clip],
          caption: const ExportCaption(
            cues: [(seconds: 1.0, text: '   ')], // 공백만
            position: 'top',
          ),
        ),
      ],
      width: 128,
      height: 128,
      outPath: out,
    );
    expect(await File(out).exists(), isTrue);
  }, skip: has ? null : 'ffmpeg 없음');
}
