import 'store_shot_params.dart';

export 'store_shot_params.dart';

/// 테두리(베젤) 색 프리셋.
typedef BezelPreset = ({String name, int r, int g, int b});

const List<BezelPreset> kBezelPresets = [
  (name: '검정', r: 17, g: 19, b: 22),
  (name: '진회색', r: 43, g: 43, b: 46),
  (name: '회색', r: 138, g: 138, b: 141), // 진회색·흰색 중간색
  (name: '흰색', r: 233, g: 233, b: 236),
  (name: '브라운', r: 58, g: 44, b: 26),
];

/// 내보내기 크기 프리셋 (App Store 스크린샷 규격 — Apple이 허용하는 정확한 크기).
typedef ExportPreset = ({String label, int w, int h});

const List<ExportPreset> kExportPresets = [
  (label: 'iPhone 6.5" (1242×2688)', w: 1242, h: 2688),
  (label: 'iPhone 6.7" (1290×2796)', w: 1290, h: 2796),
  (label: 'iPad 12.9" (2048×2732)', w: 2048, h: 2732),
  (label: 'Mac (2880×1800)', w: 2880, h: 1800),
];

/// 스샷 문서의 레이아웃(비율) 상태 — `doc.json`으로 직렬화되는 형태이자
/// 합성 파라미터([StoreShotParams])로 변환되는 단일 출처. 베젤 색은 인덱스로만
/// 저장하고, [toParams]에서 [kBezelPresets]를 참조해 실제 RGB로 푼다.
class StoreShotDoc {
  /// 출력 프레임(캔버스) 크기 — 곧 내보내기 픽셀 크기. 모든 레이아웃 비율의 기준.
  final int frameW;
  final int frameH;

  /// 배경을 프레임에 채우는 방식(cover/fill).
  final BgFit bgFit;

  final double widthFraction;
  final double topFraction;
  final double centerXFraction;
  final double topRadiusFraction;
  final double bezelFraction;
  final int bezelIndex;
  final bool noBezel;

  /// 오브젝트(추가 이미지) 레이아웃 목록 — 이미지 자체는 obj_0.png… 로 따로 저장.
  final List<ObjectLayout> objects;

  const StoreShotDoc({
    this.frameW = 1242,
    this.frameH = 2688,
    this.bgFit = BgFit.cover,
    this.widthFraction = 0.72,
    this.topFraction = 0.30,
    this.centerXFraction = 0.5,
    this.topRadiusFraction = 0.06,
    this.bezelFraction = 0.022,
    this.bezelIndex = 0,
    this.noBezel = false,
    this.objects = const [],
  });

  /// 저장된 doc.json을 파싱. 누락된 키는 기본값을 쓰고, bezelIndex는 프리셋
  /// 범위로 클램프한다.
  factory StoreShotDoc.fromJson(Map<String, dynamic> j) {
    const d = StoreShotDoc();
    double f(String k, double fallback) => (j[k] as num?)?.toDouble() ?? fallback;
    return StoreShotDoc(
      // 프레임 정보가 없는 옛 문서는 0(센티넬)로 둬 로드 시 배경 원본 크기로
      // 마이그레이션한다.
      frameW: (j['frameW'] as num?)?.toInt() ?? 0,
      frameH: (j['frameH'] as num?)?.toInt() ?? 0,
      bgFit: BgFit.values.firstWhere(
        (e) => e.name == j['bgFit'],
        orElse: () => BgFit.cover,
      ),
      widthFraction: f('widthFraction', d.widthFraction),
      topFraction: f('topFraction', d.topFraction),
      centerXFraction: f('centerXFraction', d.centerXFraction),
      topRadiusFraction: f('topRadiusFraction', d.topRadiusFraction),
      bezelFraction: f('bezelFraction', d.bezelFraction),
      bezelIndex: (j['bezelIndex'] as int? ?? d.bezelIndex)
          .clamp(0, kBezelPresets.length - 1),
      noBezel: j['noBezel'] as bool? ?? d.noBezel,
      objects: ((j['objects'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => ObjectLayout.fromJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'frameW': frameW,
        'frameH': frameH,
        'bgFit': bgFit.name,
        'widthFraction': widthFraction,
        'topFraction': topFraction,
        'centerXFraction': centerXFraction,
        'topRadiusFraction': topRadiusFraction,
        'bezelFraction': bezelFraction,
        'bezelIndex': bezelIndex,
        'noBezel': noBezel,
        'objects': objects.map((o) => o.toJson()).toList(),
      };

  StoreShotDoc copyWith({
    int? frameW,
    int? frameH,
    BgFit? bgFit,
    double? widthFraction,
    double? topFraction,
    double? centerXFraction,
    double? topRadiusFraction,
    double? bezelFraction,
    int? bezelIndex,
    bool? noBezel,
    List<ObjectLayout>? objects,
  }) =>
      StoreShotDoc(
        frameW: frameW ?? this.frameW,
        frameH: frameH ?? this.frameH,
        bgFit: bgFit ?? this.bgFit,
        widthFraction: widthFraction ?? this.widthFraction,
        topFraction: topFraction ?? this.topFraction,
        centerXFraction: centerXFraction ?? this.centerXFraction,
        topRadiusFraction: topRadiusFraction ?? this.topRadiusFraction,
        bezelFraction: bezelFraction ?? this.bezelFraction,
        bezelIndex: bezelIndex ?? this.bezelIndex,
        noBezel: noBezel ?? this.noBezel,
        objects: objects ?? this.objects,
      );

  /// 폰 프레임 합성 파라미터로 변환(베젤 인덱스 → RGB, 베젤없음 → 두께 0).
  /// 오브젝트 레이아웃은 [objects]로 별도 전달한다.
  StoreShotParams toParams() {
    final b = kBezelPresets[bezelIndex.clamp(0, kBezelPresets.length - 1)];
    return StoreShotParams(
      widthFraction: widthFraction,
      topFraction: topFraction,
      centerXFraction: centerXFraction,
      topRadiusFraction: topRadiusFraction,
      bezelFraction: noBezel ? 0.0 : bezelFraction,
      bezelR: b.r,
      bezelG: b.g,
      bezelB: b.b,
    );
  }
}
