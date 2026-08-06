// 자막(캡션) — 비트에 얹는 **시간순 자막 구간들**. 대사/효과음과 함께 비트에 붙는다.
// 각 구간(CaptionCue)은 길이(초)와 텍스트를 갖고, 비트 시작부터 순서대로 흐른다.
// 예: 1초 "완전히" → 3초 공백 → 3초 "다른 사람이 나타났다" (공백 = 텍스트 빈 구간).
// 효과음과 마찬가지로 **트랙끼리 공유**(기준 비트에만 둔다) — 백엔드와 무관하다.

/// 자막이 놓이는 세로 위치.
enum CaptionPosition {
  top('상단'),
  middle('중간'),
  bottom('하단');

  const CaptionPosition(this.label);
  final String label;
}

/// 자막 한 구간 — [seconds]초 동안 [text]를 보여준다. text가 비면 그동안 공백(자막 없음).
class CaptionCue {
  double seconds;
  String text;

  CaptionCue({this.seconds = 1.0, this.text = ''});

  Map<String, dynamic> toJson() => {'seconds': seconds, 'text': text};

  factory CaptionCue.fromJson(Map<String, dynamic> j) => CaptionCue(
        seconds: (j['seconds'] as num?)?.toDouble() ?? 1.0,
        text: (j['text'] as String?) ?? '',
      );
}

/// 자막이 실제로 **글씨를 띄우는** 길이(초) — 마지막 글씨 구간이 끝나는 시각.
/// 뒤에 붙은 빈 구간은 안 센다(아무것도 안 보이는 시간까지 자리를 잡을 이유가 없다).
///
/// 비트가 몇 초짜리인지는 **영상·대사·자막 중 가장 긴 것**으로 정한다. 미리보기(재생 진행
/// 판단)와 내보내기(비트 세그먼트 길이)가 그 판단에 **같은 자**를 쓰도록 여기 한 곳에 둔다.
double captionTextSeconds(Iterable<({double seconds, String text})> cues) {
  var acc = 0.0;
  var end = 0.0;
  for (final c in cues) {
    acc += c.seconds;
    if (c.text.trim().isNotEmpty) end = acc;
  }
  return end;
}

/// 한 비트의 자막 = 구간 목록 + 위치.
class Caption {
  List<CaptionCue> cues;
  CaptionPosition position;

  Caption({List<CaptionCue>? cues, this.position = CaptionPosition.bottom})
      : cues = cues ?? [];

  bool get isEmpty => cues.isEmpty;

  /// 자막 전체 길이(초) = 구간 길이 합.
  double get totalSeconds => cues.fold(0.0, (a, c) => a + c.seconds);

  /// 글씨가 보이는 데까지의 길이(초) — 비트 길이를 정할 때 쓰는 값. [captionTextSeconds] 참고.
  double get textSeconds =>
      captionTextSeconds(cues.map((c) => (seconds: c.seconds, text: c.text)));

  Map<String, dynamic> toJson() => {
        'position': position.name,
        'cues': cues.map((c) => c.toJson()).toList(),
      };

  factory Caption.fromJson(Map<String, dynamic> j) => Caption(
        position: CaptionPosition.values.firstWhere(
          (e) => e.name == j['position'],
          orElse: () => CaptionPosition.bottom,
        ),
        cues: ((j['cues'] as List?) ?? const [])
            .map((e) => CaptionCue.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}
