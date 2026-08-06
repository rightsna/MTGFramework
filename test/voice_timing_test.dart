import 'package:flutter_test/flutter_test.dart';
import 'package:framework/src/storyboard/models/caption.dart';
import 'package:framework/src/storyboard/models/dialogue.dart';
import 'package:framework/src/storyboard/models/dialogue_beat.dart';
import 'package:framework/src/storyboard/models/shot.dart';
import 'package:framework/src/storyboard/services/elevenlabs_service.dart'
    show AlignedWord;
import 'package:framework/src/storyboard/services/voice_timing.dart';

/// 대사 음성에서 화면 길이·자막 큐를 유도하는 규칙([VoiceTiming]).
/// 원래 채널 폴더의 파이썬 스크립트에만 있던 규칙이라 검증이 없었다 — 여기서 못 박는다.
void main() {
  group('화면 길이 = 내림(음성초) + 1', () {
    test('음성보다 항상 길어 비트 끝에 여백이 남는다', () {
      expect(VoiceTiming.beatVideoSeconds(3.0), 4.0); // 딱 떨어져도 1초 더
      expect(VoiceTiming.beatVideoSeconds(3.4), 4.0);
      expect(VoiceTiming.beatVideoSeconds(3.99), 4.0);
      expect(VoiceTiming.beatVideoSeconds(0), 0.0); // 음성 없으면 유도할 게 없다
    });

    test('샷들에 고르게 나눈다(0.01초 단위)', () {
      expect(VoiceTiming.splitAcrossShots(4, 2), [2.0, 2.0]);
      expect(VoiceTiming.splitAcrossShots(4, 3), [1.33, 1.33, 1.33]);
      expect(VoiceTiming.splitAcrossShots(4, 0), isEmpty);
    });

    test('비트에 써 넣고, 바뀐 게 없으면 false', () {
      final beat = DialogueBeat(
        id: 'b1',
        dialogue: Dialogue(text: '대사', voiceSeconds: 3.4),
        shots: [Shot(id: 's1'), Shot(id: 's2')],
      );
      expect(VoiceTiming.applyToBeat(beat), isTrue);
      expect(beat.shots.map((s) => s.videoSeconds), [2.0, 2.0]);
      expect(VoiceTiming.applyToBeat(beat), isFalse); // 두 번째는 그대로
    });

    test('파생 비트는 건드리지 않는다 — 스파스 오버라이드가 깨진다', () {
      final derived = DialogueBeat(
        id: 'b1_t2',
        baseId: 'b1',
        shots: [Shot(id: 's1_t2')],
      );
      expect(VoiceTiming.applyToBeat(derived, voiceSeconds: 3.4), isFalse);
      expect(derived.shots.single.videoSeconds, 5); // 기본값 그대로
    });
  });

  group('자막 큐 = 실제 발화', () {
    // "안녕하세요" 뒤에 0.6초 쉬고 "반갑습니다" — 글자수 비례로 나누면 못 잡는 쉼.
    final words = [
      const AlignedWord(text: '안녕', start: 0.0, end: 0.5),
      const AlignedWord(text: '하세요', start: 0.5, end: 1.2),
      const AlignedWord(text: ' ', start: 1.2, end: 1.8),
      const AlignedWord(text: '반갑습니다', start: 1.8, end: 3.0),
    ];

    test('줄 경계로 잘리고, 줄 끝의 쉼이 앞 큐에 붙는다', () {
      final cues = VoiceTiming.cuesFromWords(words, ['안녕하세요', '반갑습니다']);
      expect(cues.length, 2);
      expect(cues[0].text, '안녕하세요');
      expect(cues[0].seconds, closeTo(1.2, 0.001));
      expect(cues[1].seconds, closeTo(1.8, 0.001)); // 1.2 → 3.0 (쉼 포함)
    });

    test('마지막 큐를 비트 끝까지 늘린다 — 패딩에서 자막만 먼저 사라지지 않게', () {
      final cues =
          VoiceTiming.cuesFromWords(words, ['안녕하세요', '반갑습니다'], beatSeconds: 4);
      expect(cues.fold(0.0, (a, c) => a + c.seconds), closeTo(4.0, 0.001));
      expect(cues.last.seconds, closeTo(2.8, 0.001));
    });

    test('비트가 발화보다 짧으면 늘리지 않는다', () {
      final cues =
          VoiceTiming.cuesFromWords(words, ['안녕하세요', '반갑습니다'], beatSeconds: 2);
      expect(cues.fold(0.0, (a, c) => a + c.seconds), closeTo(3.0, 0.001));
    });

    test('짧은 줄도 최소 노출 시간을 받는다', () {
      final cues = VoiceTiming.cuesFromWords(
        [const AlignedWord(text: '네', start: 0.0, end: 0.2)],
        ['네'],
      );
      expect(cues.single.seconds, VoiceTiming.minCueSeconds);
    });

    test('빈 줄은 큐가 되지 않는다', () {
      expect(VoiceTiming.linesOf('첫 줄\n\n  \n둘째 줄'), ['첫 줄', '둘째 줄']);
    });

    // 비트 길이는 영상·대사·자막 중 **가장 긴 것**으로 정한다. 자막 쪽 자([captionTextSeconds])는
    // 미리보기 진행 판단과 내보내기 세그먼트 길이가 함께 쓰므로 여기서 못 박는다.
    test('자막 길이는 마지막 글씨 구간의 끝 — 중간 공백은 세고, 뒤 공백은 안 센다', () {
      expect(
        captionTextSeconds(const [
          (seconds: 1.0, text: '가'),
          (seconds: 2.0, text: ''), // 중간 공백 — 뒤에 글씨가 또 나오므로 센다
          (seconds: 1.5, text: '나'),
        ]),
        closeTo(4.5, 0.001),
      );
      expect(
        captionTextSeconds(const [
          (seconds: 1.0, text: '가'),
          (seconds: 9.0, text: '  '), // 뒤에 붙은 공백 — 안 센다
        ]),
        closeTo(1.0, 0.001),
      );
      expect(captionTextSeconds(const []), 0.0);
      expect(captionTextSeconds(const [(seconds: 3.0, text: '')]), 0.0);
    });

    test('비트에 써 넣을 때 위치는 기존 값을 지킨다', () {
      final beat = DialogueBeat(
        id: 'b1',
        caption: Caption(position: CaptionPosition.top),
        shots: [Shot(id: 's1')],
      );
      VoiceTiming.applyCaption(beat, [(seconds: 1.234, text: '가')]);
      expect(beat.caption!.position, CaptionPosition.top);
      expect(beat.caption!.cues.single.seconds, 1.23); // 0.01초 단위로 떨군다
    });
  });
}
