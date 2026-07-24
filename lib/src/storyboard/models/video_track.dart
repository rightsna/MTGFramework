import '../services/movie_settings.dart'; // VideoBackend
import 'dialogue_beat.dart';

/// 한 씬을 **같은 구성으로 여러 번 뽑아 비교하는 단위**. 계층: 씬 > **트랙** > 비트 > 샷.
///
/// 트랙을 나누는 이유는 하나다 — 같은 콘티를 자체 서버(LTX)로도 뽑고 Veo로도 뽑아
/// 나란히 놓고 보기 위해서. 그래서 **구조(비트 수·샷 수)는 트랙끼리 항상 같고**,
/// 트랙마다 달라지는 건 [backend]와 각 샷의 영상 파일뿐이다.
///
/// 첫 번째 트랙이 **기준 트랙**이다. 비트·샷을 더하고 지우는 건 기준 트랙에서만 하고,
/// 파생 트랙은 그 구조를 그대로 비춘다([DialogueBeat.baseId] / [Shot.baseId]).
/// 파생 트랙의 샷은 손대기 전까지 기준 샷의 내용(프롬프트·프레임·길이)을 그대로 따라가므로,
/// **트랙을 추가하고 아무것도 안 하면 트랙 1과 똑같이 보인다** — 영상만 비어 있고,
/// 거기서 영상을 다시 뽑으면 그 트랙의 영상만 채워진다.
class VideoTrack {
  String id;
  String name; // 트랙 이름 (비우면 '트랙 n' 으로 표시)
  VideoBackend backend; // 이 트랙의 영상을 뽑을 백엔드 — 트랙을 가르는 기준
  List<DialogueBeat> beats; // 이 트랙의 비트들(기준 트랙과 개수·순서가 항상 같다)

  // ── 생성 설정도 **트랙별**이다 — 트랙마다 다른 LoRA·성우로 뽑아 비교한다(예전엔 씬 단위였다). ──
  String loraUrl; // 이 트랙의 LoRA URL (LTX-2.3용)
  double loraStrength; // 이 트랙의 LoRA 강도
  String defaultVoiceId; // 이 트랙의 기본 성우(내레이션·화자 미지정 대사용). 비면 미지정
  String defaultVoiceName; // 사람이 읽는 기본 성우 이름(라벨)

  /// 이 트랙의 재생 배속(1.0~2.0). 미리보기와 내보내기에 똑같이 걸린다 —
  /// 영상·대사·효과음이 함께 빨라지고(배경음은 그대로 전체에 깔린다), 길이는 1/배속이 된다.
  double speed;

  VideoTrack({
    required this.id,
    this.name = '',
    this.backend = VideoBackend.serviceApi,
    List<DialogueBeat>? beats,
    this.loraUrl = '',
    this.loraStrength = 0.8,
    this.defaultVoiceId = '',
    this.defaultVoiceName = '',
    this.speed = 1.0,
  }) : beats = beats ?? [];

  /// 이 트랙의 샷 총 개수(트랙끼리 같다).
  int get shotCount => beats.fold(0, (a, b) => a + b.shots.length);

  /// 영상이 실제로 채워진 샷 수 — 트랙별 진행도(비교 대상이 얼마나 뽑혔는지).
  int get filledCount =>
      beats.fold(0, (a, b) => a + b.shots.where((s) => s.videoPath != null).length);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'backend': backend.name,
        'lora': {'url': loraUrl, 'strength': loraStrength},
        'voice': {'id': defaultVoiceId, 'name': defaultVoiceName},
        'speed': speed,
        'beats': beats.map((b) => b.toJson()).toList(),
      };

  /// [dir] = 프로젝트 폴더(미디어 파일명을 절대경로로 되살릴 기준).
  factory VideoTrack.fromJson(Map<String, dynamic> j, String dir) {
    final lora = (j['lora'] as Map?)?.cast<String, dynamic>();
    final voice = (j['voice'] as Map?)?.cast<String, dynamic>();
    return VideoTrack(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? '',
      backend: VideoBackend.values.firstWhere(
        (e) => e.name == j['backend'],
        orElse: () => VideoBackend.serviceApi,
      ),
      loraUrl: (lora?['url'] as String?) ?? '',
      loraStrength: (lora?['strength'] as num?)?.toDouble() ?? 0.8,
      defaultVoiceId: (voice?['id'] as String?) ?? '',
      defaultVoiceName: (voice?['name'] as String?) ?? '',
      // 배속 없던 옛 데이터는 1배속.
      speed: ((j['speed'] as num?)?.toDouble() ?? 1.0).clamp(1.0, 2.0),
      beats: ((j['beats'] as List?) ?? const [])
          .map((e) =>
              DialogueBeat.fromJson((e as Map).cast<String, dynamic>(), dir))
          .toList(),
    );
  }
}
