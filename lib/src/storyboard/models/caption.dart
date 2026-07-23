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

/// 한 비트의 자막 = 구간 목록 + 위치.
class Caption {
  List<CaptionCue> cues;
  CaptionPosition position;

  Caption({List<CaptionCue>? cues, this.position = CaptionPosition.bottom})
      : cues = cues ?? [];

  bool get isEmpty => cues.isEmpty;

  /// 자막 전체 길이(초) = 구간 길이 합.
  double get totalSeconds => cues.fold(0.0, (a, c) => a + c.seconds);

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
