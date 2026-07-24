import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:framework/src/storyboard/services/video_edit.dart';

/// 효과음(SFX)이 대사와 함께 실제로 **섞이는지**, 그리고 효과음 비트 뒤 대사가 살아 있는지.
/// 대사·효과음을 서로 다른 주파수 톤(mp3)으로 만들어, 산출물의 각 구간에서 그 주파수 대역
/// 에너지를 재서 "정말 그 소리가 들어갔는지"를 본다.
void main() {
  final has = VideoEdit.available;
  late Directory tmp;
  final ff = VideoEdit.toolPath('ffmpeg');

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audio_export');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> colorClip(String name, double sec) async {
    final path = '${tmp.path}/$name.mp4';
    final r = await Process.run(ff!, [
      '-y',
      '-f', 'lavfi', '-i', 'color=c=black:size=128x128:rate=24:duration=$sec',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', path,
    ]);
    expect(r.exitCode, 0, reason: '클립 실패: ${r.stderr}');
    return path;
  }

  // 실제 앱처럼 mp3로. channels=1(대사 모노) / 2(효과음 스테레오).
  Future<String> tone(String name, int freq, double sec, int channels) async {
    final path = '${tmp.path}/$name.mp3';
    final r = await Process.run(ff!, [
      '-y',
      '-f', 'lavfi', '-i', 'sine=frequency=$freq:duration=$sec',
      '-ac', '$channels', '-c:a', 'libmp3lame', path,
    ]);
    expect(r.exitCode, 0, reason: '톤 실패: ${r.stderr}');
    return path;
  }

  /// [ss]~[ss+t] 구간에서 [freq]Hz 대역의 최대 음량(dB). 그 톤이 없으면 아주 작다(-70 이하).
  Future<double> bandDb(String path, double ss, double t, int freq) async {
    final r = await Process.run(ff!, [
      '-ss', '$ss', '-t', '$t', '-i', path,
      '-map', '0:a',
      '-af', 'bandpass=f=$freq:width_type=h:width=60,volumedetect',
      '-f', 'null', '-',
    ]);
    final m = RegExp(r'max_volume:\s*(-?[\d.]+) dB')
        .firstMatch(r.stderr as String);
    if (m == null) return -99; // 트랙에 오디오가 아예 없으면 측정 불가 → 없음으로
    return double.parse(m.group(1)!);
  }

  test('효과음이 대사와 섞이고, 효과음 비트 뒤 대사도 살아 있다', () async {
    final clip1 = await colorClip('c1', 1.0);
    final clip2 = await colorClip('c2', 1.0);
    final voice1 = await tone('v1', 300, 1.0, 1); // 대사(모노) 300Hz
    final sfx1 = await tone('s1', 900, 1.0, 2); // 효과음(스테레오) 900Hz
    final voice2 = await tone('v2', 500, 1.0, 1); // 다음 비트 대사 500Hz

    final out = '${tmp.path}/out.mp4';
    await VideoEdit.exportScene(
      beats: [
        ExportBeat(clips: [clip1], voice: voice1, sfx: sfx1), // 0~1s
        ExportBeat(clips: [clip2], voice: voice2), // 1~2s
      ],
      width: 128,
      height: 128,
      outPath: out,
    );
    expect(await File(out).exists(), isTrue);

    // 비트1: 대사(300)와 효과음(900)이 **둘 다** 들어가 있어야 한다.
    expect(await bandDb(out, 0.1, 0.7, 300), greaterThan(-45),
        reason: '비트1에 대사(300Hz)가 있어야 한다');
    expect(await bandDb(out, 0.1, 0.7, 900), greaterThan(-45),
        reason: '★ 비트1에 효과음(900Hz)이 섞여 있어야 한다');
    // 비트2: 대사(500)가 살아 있어야 한다(효과음 비트 뒤라고 사라지면 안 됨).
    expect(await bandDb(out, 1.15, 0.7, 500), greaterThan(-45),
        reason: '★ 효과음 비트 다음 대사(500Hz)가 살아 있어야 한다');
  }, skip: has ? null : 'ffmpeg 없음');

  test('2배속 — 길이가 절반이 되고 대사·효과음은 그대로 들린다', () async {
    final clip1 = await colorClip('c1', 1.0);
    final clip2 = await colorClip('c2', 1.0);
    final voice1 = await tone('v1', 300, 1.0, 1);
    final sfx1 = await tone('s1', 900, 1.0, 2);
    final voice2 = await tone('v2', 500, 1.0, 1);

    final out = '${tmp.path}/fast.mp4';
    await VideoEdit.exportScene(
      beats: [
        ExportBeat(clips: [clip1], voice: voice1, sfx: sfx1),
        ExportBeat(clips: [clip2], voice: voice2),
      ],
      width: 128,
      height: 128,
      outPath: out,
      speed: 2.0,
    );

    final info = await VideoEdit.probe(out);
    expect(info, isNotNull);
    // 원본 2초 → 2배속이면 1초.
    expect(info!.duration, closeTo(1.0, 0.2), reason: '★ 2배속이면 길이가 절반');

    // atempo는 음정을 유지하므로 주파수는 그대로 — 각 구간에 소리가 남아 있어야 한다.
    expect(await bandDb(out, 0.05, 0.35, 300), greaterThan(-45),
        reason: '2배속에서도 비트1 대사가 들린다');
    expect(await bandDb(out, 0.05, 0.35, 900), greaterThan(-45),
        reason: '2배속에서도 효과음이 섞여 있다');
    expect(await bandDb(out, 0.6, 0.35, 500), greaterThan(-45),
        reason: '2배속에서도 비트2 대사가 들린다');
  }, skip: has ? null : 'ffmpeg 없음');
}
