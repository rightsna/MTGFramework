import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:framework/src/storyboard/models/caption.dart';
import 'package:framework/src/storyboard/models/shot.dart';
import 'package:framework/src/storyboard/models/text_overlay.dart';
import 'package:framework/src/storyboard/services/video_edit.dart';

/// 샷에 **구워 넣는 글씨**(타이틀 카드·썸네일 프레임).
/// 채널마다 임시 스크립트로 하던 일을 엔진으로 올린 것이라, 세 채널이 쓰는 스타일이
/// 전부 데이터로 표현되는지 + 실제로 프레임에 구워지는지까지 본다.
void main() {
  group('저장/복원', () {
    test('샷에 붙어 왕복한다', () {
      final shot = Shot(
        id: 's1',
        videoMode: VideoMode.still,
        textOverlay: TextOverlay(
          text: '나는 왜 이렇게\n뒤처진 걸까요?',
          position: CaptionPosition.top,
          color: 'FFD400',
          sizeRatio: 0.075,
          outlineRatio: 0.14,
          scrim: 0.5,
        ),
      );
      final back = Shot.fromJson(shot.toJson(), '/tmp');
      final o = back.textOverlay!;
      expect(o.text, '나는 왜 이렇게\n뒤처진 걸까요?');
      expect(o.position, CaptionPosition.top);
      expect(o.color, 'FFD400');
      expect(o.sizeRatio, 0.075);
      expect(o.outlineRatio, 0.14);
      expect(o.scrim, 0.5);
    });

    test('글씨 없는 샷은 null 로 남는다 — 빈 껍데기를 만들지 않는다', () {
      final back = Shot.fromJson(Shot(id: 's1').toJson(), '/tmp');
      expect(back.textOverlay, isNull);
    });

    test('파생 샷은 기준 것을 상속하되, 손대면 자기 것이 된다', () {
      final base = Shot(id: 's1', textOverlay: TextOverlay(text: '한국어 훅'));
      final derived = Shot(id: 's1_t2', baseId: 's1');
      expect(derived.resolvedTextOverlay(base)!.text, '한국어 훅');

      derived.overrides[Shot.kTextOverlay] = TextOverlay(text: 'English hook');
      expect(derived.resolvedTextOverlay(base)!.text, 'English hook');
      expect(base.textOverlay!.text, '한국어 훅'); // 기준은 안 바뀐다

      // 명시적 '없음'도 상속과 구분된다(키가 있으면 오버라이드).
      derived.overrides[Shot.kTextOverlay] = null;
      expect(derived.resolvedTextOverlay(base), isNull);
    });

    test('오버라이드도 JSON을 왕복한다', () {
      final derived = Shot(id: 's1_t2', baseId: 's1');
      derived.overrides[Shot.kTextOverlay] = TextOverlay(text: 'English hook');
      final back = Shot.fromJson(derived.toJson(), '/tmp');
      expect(
          (back.overrides[Shot.kTextOverlay] as TextOverlay).text, 'English hook');
    });
  });

  group('실제로 프레임에 구워진다', () {
    final has = VideoEdit.available;
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('overlay_burn');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    /// 단색 배경 한 장 — 글씨가 얹히면 픽셀이 달라진다.
    Future<String> makeImage() async {
      final path = '${tmp.path}/bg.png';
      final r = await Process.run(VideoEdit.toolPath('ffmpeg')!, [
        '-y', '-f', 'lavfi',
        '-i', 'color=c=gray:size=544x960',
        '-frames:v', '1', path,
      ]);
      expect(r.exitCode, 0, reason: r.stderr as String);
      return path;
    }

    /// 클립 첫 프레임의 위쪽 띠 평균 밝기 — 어둠(scrim)과 글씨가 여기서 드러난다.
    Future<double> topBrightness(String clip) async {
      final r = await Process.run(VideoEdit.toolPath('ffmpeg')!, [
        '-v', 'error', '-i', clip,
        '-vf', 'crop=544:180:0:0,signalstats,'
            'metadata=print:key=lavfi.signalstats.YAVG:file=-',
        '-frames:v', '1', '-f', 'null', '-',
      ]);
      final m = RegExp(r'YAVG=([\d.]+)').firstMatch(r.stdout as String);
      expect(m, isNotNull, reason: '밝기를 못 쟀다: ${r.stderr}');
      return double.parse(m!.group(1)!);
    }

    test('글씨를 얹으면 프레임이 달라지고, 안 얹으면 그대로다', () async {
      final img = await makeImage();
      final plain = '${tmp.path}/plain.mp4';
      final carded = '${tmp.path}/carded.mp4';

      await VideoEdit.stillClip(
        image: img, outPath: plain, seconds: 0.5,
        effect: StillEffect.none, width: 544, height: 960,
      );
      await VideoEdit.stillClip(
        image: img, outPath: carded, seconds: 0.5,
        effect: StillEffect.none, width: 544, height: 960,
        overlay: TextOverlay(text: '나는 왜 이렇게 뒤처진 걸까요?'),
      );

      expect(File(plain).existsSync(), isTrue);
      expect(File(carded).existsSync(), isTrue);
      // 위쪽에 어둠 + 흰 글씨가 들어갔으니 평균 밝기가 눈에 띄게 달라야 한다.
      final before = await topBrightness(plain);
      final after = await topBrightness(carded);
      expect((after - before).abs(), greaterThan(5),
          reason: '글씨가 안 구워진 것 같다 (before=$before after=$after)');
    }, skip: has ? false : 'ffmpeg 없음');

    test('빈 문구는 아무것도 굽지 않는다', () async {
      final img = await makeImage();
      final a = '${tmp.path}/a.mp4';
      final b = '${tmp.path}/b.mp4';
      await VideoEdit.stillClip(
        image: img, outPath: a, seconds: 0.5,
        effect: StillEffect.none, width: 544, height: 960,
      );
      await VideoEdit.stillClip(
        image: img, outPath: b, seconds: 0.5,
        effect: StillEffect.none, width: 544, height: 960,
        overlay: TextOverlay(text: '   '),
      );
      expect((await topBrightness(b)) - (await topBrightness(a)),
          closeTo(0, 0.5));
    }, skip: has ? false : 'ffmpeg 없음');

    test('켄번스와 같이 써도 글씨는 확대되지 않는다', () async {
      // 글씨를 zoompan 앞에 얹으면 같이 확대돼 흔들린다 → 뒤에 얹는지 확인.
      // 확대되면 첫 프레임과 끝 프레임의 글씨 크기가 달라져 위쪽 밝기가 벌어진다.
      final img = await makeImage();
      final clip = '${tmp.path}/kb.mp4';
      await VideoEdit.stillClip(
        image: img, outPath: clip, seconds: 1.0,
        effect: StillEffect.zoomIn, width: 544, height: 960,
        overlay: TextOverlay(text: '고정되어야 하는 글씨'),
      );
      final first = '${tmp.path}/f.png';
      final last = '${tmp.path}/l.png';
      for (final (out, seek) in [(first, '0'), (last, '0.9')]) {
        final r = await Process.run(VideoEdit.toolPath('ffmpeg')!,
            ['-y', '-v', 'error', '-ss', seek, '-i', clip, '-frames:v', '1', out]);
        expect(r.exitCode, 0, reason: r.stderr as String);
      }
      final a = await topBrightness(first);
      final b = await topBrightness(last);
      expect((a - b).abs(), lessThan(2.0),
          reason: '글씨가 켄번스에 같이 딸려간다 (첫=$a 끝=$b)');
    }, skip: has ? false : 'ffmpeg 없음');
  });
}
