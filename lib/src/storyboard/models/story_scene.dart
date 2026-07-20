import 'shot.dart'; // mediaName / mediaPath
import 'dialogue_beat.dart';

/// 한 씬(scene) = **대사들의 나열**(타임라인). 각 대사(DialogueBeat)은 대사 1개(선택) + 샷 여러 개를 담는다.
/// 스토리보드는 씬들의 리스트이고, 각 씬이 [dialogues]를 순서대로 담는다.
///
/// 저장은 씬 하나당 `scene<N>.json` 한 파일. 개념별로 묶어서(dialogues/bgm/lora) 적어
/// JSON만 봐도 씬 구성이 읽히게 한다. 미디어는 프로젝트 폴더 안 파일명(상대)만 저장한다.
class StoryScene {
  String id;
  String title; // 씬 제목 (비우면 SCENE n 으로 표시)
  String commonPrompt; // 이 씬 공통 프롬프트 — 씬 내 모든 샷 생성에 함께 붙는다
  List<DialogueBeat> dialogues; // 타임라인 = 대사의 나열(각 대사 = 대사? + 샷들)
  String loraUrl; // 이 씬의 LoRA URL (씬 안 샷들끼리 공유, 씬끼리 별개)
  double loraStrength; // 이 씬의 LoRA 강도
  String bgmPrompt; // 이 씬의 배경음 스타일 태그(장르·분위기·악기) — ACE-Step BGM 생성용
  String? bgmPath; // 생성된 배경음(mp3) 파일 경로(런타임 절대경로)
  int bgmSeconds; // 배경음 길이(초)
  String note; // 씬 메모(특이사항) — 프롬프트와 무관, 생성에 안 쓰임

  StoryScene({
    required this.id,
    this.title = '',
    this.commonPrompt = '',
    List<DialogueBeat>? dialogues,
    this.loraUrl = '',
    this.loraStrength = 0.8,
    this.bgmPrompt = '',
    this.bgmPath,
    this.bgmSeconds = 30,
    this.note = '',
  }) : dialogues = dialogues ?? [];

  /// 씬 전체 길이(초) — 각 대사의 실제 길이(=샷 길이 합)의 합.
  double get totalSeconds => dialogues.fold(0, (a, s) => a + s.seconds);

  /// 씬 안 샷 총 개수.
  int get shotCount => dialogues.fold(0, (a, s) => a + s.shots.length);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'commonPrompt': commonPrompt,
        'dialogues': dialogues.map((s) => s.toJson()).toList(),
        'bgm': {
          'prompt': bgmPrompt,
          'seconds': bgmSeconds,
          'file': mediaName(bgmPath),
        },
        'lora': {
          'url': loraUrl,
          'strength': loraStrength,
        },
        'note': note,
      };

  /// [dir] = 프로젝트 폴더(미디어 파일명을 절대경로로 되살릴 기준).
  factory StoryScene.fromJson(Map<String, dynamic> j, String dir) {
    final bgm = (j['bgm'] as Map?)?.cast<String, dynamic>();
    final lora = (j['lora'] as Map?)?.cast<String, dynamic>();
    return StoryScene(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      commonPrompt: (j['commonPrompt'] as String?) ?? '',
      dialogues: ((j['dialogues'] as List?) ?? const [])
          .map((e) =>
              DialogueBeat.fromJson((e as Map).cast<String, dynamic>(), dir))
          .toList(),
      loraUrl: (lora?['url'] as String?) ?? '',
      loraStrength: (lora?['strength'] as num?)?.toDouble() ?? 0.8,
      bgmPrompt: (bgm?['prompt'] as String?) ?? '',
      bgmPath: mediaPath(dir, bgm?['file']),
      bgmSeconds: (bgm?['seconds'] as int?) ?? 30,
      note: (j['note'] as String?) ?? '',
    );
  }
}
