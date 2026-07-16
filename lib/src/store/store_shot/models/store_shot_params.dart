/// 배경을 프레임(캔버스)에 채우는 방식.
/// - [cover]: 비율 유지하며 프레임을 가득 채우고 넘치는 부분은 크롭(가운데 기준).
/// - [fill]: 비율 무시하고 프레임 크기에 정확히 늘여 채움.
enum BgFit { cover, fill }

/// 오브젝트(추가 이미지) 한 개의 레이아웃. 모두 캔버스 크기 대비 비율이라
/// 미리보기/내보내기 결과가 동일하다. 투명 PNG 컷아웃을 가정하고 비율 그대로
/// 얹으며, 가로는 중심·세로는 하단(기준선) 기준이다.
class ObjectLayout {
  final double widthFraction; // 오브젝트 너비 ÷ 캔버스 너비
  final double centerXFraction; // 가로 중심 ÷ 캔버스 너비
  final double bottomFraction; // 하단 y ÷ 캔버스 높이 (서 있는 기준선)
  final bool inFront; // true=폰 앞, false=폰 뒤

  const ObjectLayout({
    this.widthFraction = 0.30,
    this.centerXFraction = 0.50,
    this.bottomFraction = 1.0,
    this.inFront = true,
  });

  ObjectLayout copyWith({
    double? widthFraction,
    double? centerXFraction,
    double? bottomFraction,
    bool? inFront,
  }) =>
      ObjectLayout(
        widthFraction: widthFraction ?? this.widthFraction,
        centerXFraction: centerXFraction ?? this.centerXFraction,
        bottomFraction: bottomFraction ?? this.bottomFraction,
        inFront: inFront ?? this.inFront,
      );

  Map<String, dynamic> toJson() => {
        'widthFraction': widthFraction,
        'centerXFraction': centerXFraction,
        'bottomFraction': bottomFraction,
        'inFront': inFront,
      };

  factory ObjectLayout.fromJson(Map<String, dynamic> j) {
    const d = ObjectLayout();
    double f(String k, double fb) => (j[k] as num?)?.toDouble() ?? fb;
    return ObjectLayout(
      widthFraction: f('widthFraction', d.widthFraction),
      centerXFraction: f('centerXFraction', d.centerXFraction),
      bottomFraction: f('bottomFraction', d.bottomFraction),
      inFront: j['inFront'] as bool? ?? d.inFront,
    );
  }
}

/// 스토어 스크린샷 합성 파라미터(배경/폰 프레임 부분). 모든 치수는 비율이라
/// 캔버스(프레임) 픽셀 크기와 무관하게 같은 결과를 낸다 — 축소본(미리보기)과
/// 원본(내보내기)을 같은 값으로 합성하면 픽셀만 다른 동일한 그림이 나온다.
/// 오브젝트들은 별도로 [ObjectLayout] 리스트로 합성기에 넘긴다.
class StoreShotParams {
  final double widthFraction; // 스크린샷 콘텐츠 너비 ÷ 캔버스 너비
  final double topFraction; // 스크린샷(프레임) 상단 y ÷ 캔버스 높이
  final double centerXFraction; // 프레임 가로 중심 ÷ 캔버스 너비 (0.5 = 가운데)
  final double topRadiusFraction; // 상단 모서리 반경 ÷ 스크린샷 너비
  final double bezelFraction; // 테두리 두께 ÷ 스크린샷 너비
  final int bezelR;
  final int bezelG;
  final int bezelB;

  const StoreShotParams({
    required this.widthFraction,
    required this.topFraction,
    this.centerXFraction = 0.5,
    required this.topRadiusFraction,
    required this.bezelFraction,
    required this.bezelR,
    required this.bezelG,
    required this.bezelB,
  });
}
