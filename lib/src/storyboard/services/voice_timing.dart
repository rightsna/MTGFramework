import 'dart:math' as math;

import '../models/caption.dart';
import '../models/dialogue_beat.dart';
import 'elevenlabs_service.dart' show AlignedWord;

/// 대사 음성에서 **화면 길이와 자막 큐를 유도**하는 규칙 — 순수 Dart, 부수효과 없음.
///
/// 이 두 규칙은 원래 채널 폴더의 파이썬 스크립트(`gen_voice.py` · `fix_captions.py`)에만
/// 있었다. 스크립트가 앱 데이터를 밖에서 직접 고치는 구조라, 앱이 켜져 있으면 결과가
/// 덮이고(GENERATION.md 경고) 규칙이 채널마다 갈라졌다. 그래서 **여기 한 벌만 둔다** —
/// GUI(프로바이더)와 CLI(`bin/storyboard_voice.dart`)가 같은 함수를 부른다.
class VoiceTiming {
  /// 큐 하나의 최소 노출 시간(초) — 짧은 줄이 스쳐 지나가지 않게.
  static const minCueSeconds = 0.9;

  /// 음성 길이 → **그 비트의 화면 길이**. 규칙은 `내림(음성초) + 1`.
  ///
  /// 음성보다 화면을 길게 잡아 두면 비트 끝에 여백(패딩)이 생겨 말이 잘리지 않는다.
  /// 올림이 아니라 내림+1인 건 3.0초 음성에 4초를 주기 위해서다(올림이면 3초로 딱 붙는다).
  static double beatVideoSeconds(double voiceSeconds) =>
      voiceSeconds <= 0 ? 0 : voiceSeconds.floorToDouble() + 1;

  /// 비트의 화면 길이를 샷들에 **고르게 나눈** 값(0.01초 단위). 샷이 없으면 빈 목록.
  static List<double> splitAcrossShots(double beatSeconds, int shotCount) {
    if (shotCount <= 0 || beatSeconds <= 0) return const [];
    final each = (beatSeconds / shotCount * 100).round() / 100;
    return List.filled(shotCount, each);
  }

  /// [beat]의 샷 길이를 그 비트의 음성 길이에서 유도해 **써 넣는다**.
  /// 바뀐 게 있으면 true(부르는 쪽이 저장 여부를 정한다).
  ///
  /// 파생 트랙 비트는 건드리지 않는다 — 파생은 손댄 필드만 갖는 스파스 오버라이드라
  /// 여기서 전 샷에 길이를 쓰면 기준 트랙과의 연결이 통째로 끊긴다.
  static bool applyToBeat(DialogueBeat beat, {double? voiceSeconds}) {
    if (beat.isDerived) return false;
    final secs = voiceSeconds ?? beat.dialogue?.voiceSeconds ?? 0;
    final each = splitAcrossShots(beatVideoSeconds(secs), beat.shots.length);
    if (each.isEmpty) return false;
    var changed = false;
    for (var i = 0; i < beat.shots.length; i++) {
      if (beat.shots[i].videoSeconds != each[i]) {
        beat.shots[i].videoSeconds = each[i];
        changed = true;
      }
    }
    return changed;
  }

  /// 정렬된 단어열을 **대사의 줄 경계**로 잘라 자막 큐(지속시간, 텍스트)를 만든다.
  ///
  /// 줄 하나가 큐 하나다(문장 끝에서 넘어간다). 각 줄이 몇 번째 단어까지인지는 **글자 수를
  /// 소비해** 찾는다 — 정렬 응답의 낱말 쪼개기가 대본의 띄어쓰기와 일치하지 않기 때문이다.
  ///
  /// [beatSeconds]를 주면 **마지막 큐를 비트 끝까지 늘린다** — 음성이 끝난 뒤의 패딩
  /// 구간에서 자막만 먼저 사라지는 것을 막는다(실측 2026-08-01).
  static List<({double seconds, String text})> cuesFromWords(
    List<AlignedWord> words,
    List<String> lines, {
    double? beatSeconds,
    double minCue = minCueSeconds,
  }) {
    final seq = [for (final w in words) if (!w.isBlank) w];
    final out = <({double seconds, String text})>[];
    var i = 0;
    var prevEnd = 0.0;
    for (final line in lines) {
      final need = line.replaceAll(' ', '').length;
      var used = 0;
      var end = prevEnd;
      while (i < seq.length && used < need) {
        used += seq[i].text.replaceAll(' ', '').length;
        end = seq[i].end;
        i++;
      }
      out.add((seconds: math.max(minCue, end - prevEnd), text: line));
      prevEnd = end;
    }
    if (beatSeconds != null && out.isNotEmpty) {
      final spoken = out.fold(0.0, (a, c) => a + c.seconds);
      if (beatSeconds > spoken) {
        out[out.length - 1] = (
          seconds: out.last.seconds + (beatSeconds - spoken),
          text: out.last.text,
        );
      }
    }
    return out;
  }

  /// 대사 텍스트를 큐 단위(줄)로 자른다 — 빈 줄은 버린다.
  static List<String> linesOf(String text) => [
        for (final l in text.split('\n'))
          if (l.trim().isNotEmpty) l.trim(),
      ];

  /// [cues]를 비트의 자막으로 써 넣는다(위치는 기존 값 유지, 없으면 [position]).
  static void applyCaption(
    DialogueBeat beat,
    List<({double seconds, String text})> cues, {
    CaptionPosition position = CaptionPosition.bottom,
  }) {
    beat.caption = Caption(
      position: beat.caption?.position ?? position,
      cues: [
        for (final c in cues)
          CaptionCue(
            seconds: (c.seconds * 100).round() / 100,
            text: c.text,
          ),
      ],
    );
  }
}
