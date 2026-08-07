// 샷 위에 **구워 넣는 글씨** — 타이틀 카드 / 썸네일 프레임용.
//
// 자막(Caption)과 다른 점: 자막은 대사를 따라 흐르는 시간축 구간이고, 이건 그 샷 내내
// 같은 자리에 붙어 있는 **한 덩어리 타이포**다. 유튜브가 첫 프레임을 미리보기로 집어 가므로,
// 편 맨 앞 샷에 얹으면 그게 곧 썸네일이 된다.
//
// 채널마다 색·위치만 다르고 하는 일은 같아서(머서=노란 글씨 훅, 루나리·베로니카=타이틀 카드)
// **스타일을 데이터로** 둔다. 채널별 스크립트를 다시 만들지 않으려고 만든 필드다.

import 'caption.dart' show CaptionPosition;

/// 샷에 구워 넣는 글씨 한 덩어리. [text]가 비면 없는 것과 같다.
class TextOverlay {
  /// 얹을 문구. 줄바꿈을 넣으면 그대로 나뉘고, 안 넣으면 폭에 맞춰 **어절 단위로 접힌다**.
  String text;

  /// 세로 위치 — 자막과 같은 축을 쓴다(top/middle/bottom).
  CaptionPosition position;

  /// 글씨 색(RRGGBB). 머서는 노랑(`FFD400`), 베로니카·루나리는 흰색.
  String color;

  /// 글씨 크기 = 화면 높이 × 이 비율. 0.06 ≈ 960px 화면에서 58pt.
  double sizeRatio;

  /// 외곽선 두께 = 글씨 크기 × 이 비율. 0이면 외곽선 없음.
  double outlineRatio;

  /// 글씨 뒤에 까는 어둠의 세기(0~1, 0이면 안 깐다).
  /// **사각형으로 깔지 않는다** — 위치 쪽 끝에서 시작해 부드럽게 사라지는 그라데이션이다.
  /// 사각형이면 경계선이 보인다(실측).
  double scrim;

  /// 글꼴 이름. 비우면 엔진 기본(`Arial` — 한글은 시스템 폴백).
  /// 굵은 고딕은 훅·썸네일에 맞지만 추모·헌사 카드에는 무겁다. 그때 명조를 준다.
  String font;

  /// 굵게. 기본은 `true`(훅 글씨의 원래 모양).
  bool bold;

  /// 자간(px). 굵기를 낮춘 글씨는 자간을 벌려야 성기게 읽힌다.
  double spacing;

  TextOverlay({
    this.text = '',
    this.position = CaptionPosition.top,
    this.color = 'FFFFFF',
    this.sizeRatio = 0.06,
    this.outlineRatio = 0.10,
    this.scrim = 0.43,
    this.font = '',
    this.bold = true,
    this.spacing = 0,
  });

  bool get hasText => text.trim().isNotEmpty;

  TextOverlay copy() => TextOverlay(
        text: text,
        position: position,
        color: color,
        sizeRatio: sizeRatio,
        outlineRatio: outlineRatio,
        scrim: scrim,
        font: font,
        bold: bold,
        spacing: spacing,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'position': position.name,
        'color': color,
        'size': sizeRatio,
        'outline': outlineRatio,
        'scrim': scrim,
        'font': font,
        'bold': bold,
        'spacing': spacing,
      };

  factory TextOverlay.fromJson(Map<String, dynamic> j) => TextOverlay(
        text: (j['text'] as String?) ?? '',
        position: CaptionPosition.values.firstWhere(
          (e) => e.name == j['position'],
          orElse: () => CaptionPosition.top,
        ),
        color: (j['color'] as String?) ?? 'FFFFFF',
        sizeRatio: (j['size'] as num?)?.toDouble() ?? 0.06,
        outlineRatio: (j['outline'] as num?)?.toDouble() ?? 0.10,
        scrim: (j['scrim'] as num?)?.toDouble() ?? 0.43,
        // 아래 셋은 나중에 생긴 값이라, 없으면 예전과 같은 모양으로 읽는다.
        font: (j['font'] as String?) ?? '',
        bold: (j['bold'] as bool?) ?? true,
        spacing: (j['spacing'] as num?)?.toDouble() ?? 0,
      );
}
