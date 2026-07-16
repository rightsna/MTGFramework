import 'clip.dart'; // mediaName / mediaPath
import 'shot.dart';

/// 한 씬(scene) = **샷들의 나열**(타임라인). 각 샷(Shot)은 대사 1개(선택) + 클립 여러 개를 담는다.
/// 스토리보드는 씬들의 리스트이고, 각 씬이 [shots]를 순서대로 담는다.
///
/// 저장은 씬 하나당 `scene<N>.json` 한 파일. 개념별로 묶어서(shots/bgm/lora) 적어
/// JSON만 봐도 씬 구성이 읽히게 한다. 미디어는 프로젝트 폴더 안 파일명(상대)만 저장한다.
class StoryScene {
  String id;
  String title; // 씬 제목 (비우면 SCENE n 으로 표시)
  String commonPrompt; // 이 씬 공통 프롬프트 — 씬 내 모든 클립 생성에 함께 붙는다
  List<Shot> shots; // 타임라인 = 샷의 나열(각 샷 = 대사? + 클립들)
  String loraUrl; // 이 씬의 LoRA URL (씬 안 클립들끼리 공유, 씬끼리 별개)
  double loraStrength; // 이 씬의 LoRA 강도
  String bgmPrompt; // 이 씬의 배경음 스타일 태그(장르·분위기·악기) — ACE-Step BGM 생성용
  String? bgmPath; // 생성된 배경음(mp3) 파일 경로(런타임 절대경로)
  int bgmSeconds; // 배경음 길이(초)

  StoryScene({
    required this.id,
    this.title = '',
    this.commonPrompt = '',
    List<Shot>? shots,
    this.loraUrl = '',
    this.loraStrength = 0.8,
    this.bgmPrompt = '',
    this.bgmPath,
    this.bgmSeconds = 30,
  }) : shots = shots ?? [];

  /// 씬 전체 길이(초) — 각 샷 길이의 합.
  double get totalSeconds => shots.fold(0, (a, s) => a + s.seconds);

  /// 씬 안 클립 총 개수.
  int get clipCount => shots.fold(0, (a, s) => a + s.clips.length);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'commonPrompt': commonPrompt,
        'shots': shots.map((s) => s.toJson()).toList(),
        'bgm': {
          'prompt': bgmPrompt,
          'seconds': bgmSeconds,
          'file': mediaName(bgmPath),
        },
        'lora': {
          'url': loraUrl,
          'strength': loraStrength,
        },
      };

  /// [dir] = 프로젝트 폴더(미디어 파일명을 절대경로로 되살릴 기준).
  factory StoryScene.fromJson(Map<String, dynamic> j, String dir) {
    final bgm = (j['bgm'] as Map?)?.cast<String, dynamic>();
    final lora = (j['lora'] as Map?)?.cast<String, dynamic>();
    return StoryScene(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      commonPrompt: (j['commonPrompt'] as String?) ?? '',
      shots: _readShots(j, dir),
      loraUrl: (lora?['url'] as String?) ?? (j['loraUrl'] as String?) ?? '',
      loraStrength: (lora?['strength'] as num?)?.toDouble() ??
          (j['loraStrength'] as num?)?.toDouble() ??
          0.8,
      bgmPrompt:
          (bgm?['prompt'] as String?) ?? (j['bgmPrompt'] as String?) ?? '',
      bgmPath: mediaPath(dir, bgm?['file'] ?? j['bgmPath']),
      bgmSeconds: (bgm?['seconds'] as int?) ?? (j['bgmSeconds'] as int?) ?? 30,
    );
  }

  /// 샷 리스트 읽기 + 구버전 마이그레이션.
  ///  - 신 스키마: `shots`[] = Shot 객체(내부에 clips/dialogue).
  ///  - 옛 스키마: `shots`[] 또는 `clips`[] = flat 영상 단위 → 각각 "클립 1개짜리 무음 샷"으로 감싼다.
  /// (원소에 `clips`/`dialogue` 키가 있으면 신 Shot, 없으면 옛 flat 클립으로 판별.)
  static List<Shot> _readShots(Map<String, dynamic> j, String dir) {
    final raw = (j['shots'] as List?) ?? (j['clips'] as List?) ?? const [];
    return raw.map((e) {
      final m = (e as Map).cast<String, dynamic>();
      final isNewShot = m.containsKey('clips') || m.containsKey('dialogue');
      return isNewShot ? Shot.fromJson(m, dir) : Shot.fromLegacyClip(m, dir);
    }).toList();
  }
}
