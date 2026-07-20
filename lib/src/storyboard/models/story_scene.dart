import 'shot.dart'; // mediaName / mediaPath
import 'dialogue_beat.dart';
import 'video_track.dart';

/// 한 씬(scene) = **트랙들**. 각 트랙이 같은 타임라인(대사의 나열)을 서로 다른 백엔드로 뽑는다.
/// 계층: 씬 > 트랙 > 대사(DialogueBeat: 대사 1개(선택) + 샷 여러 개) > 샷.
/// 첫 트랙이 기준([baseTrack])이고, 구조(비트·샷)는 트랙끼리 항상 같다 — [VideoTrack] 참고.
///
/// 저장은 씬 하나당 `scene<N>.json` 한 파일. 개념별로 묶어서(tracks/bgm/lora) 적어
/// JSON만 봐도 씬 구성이 읽히게 한다. 미디어는 프로젝트 폴더 안 파일명(상대)만 저장한다.
class StoryScene {
  String id;
  String title; // 씬 제목 (비우면 SCENE n 으로 표시)
  String commonPrompt; // 이 씬 공통 프롬프트 — 씬 내 모든 샷 생성에 함께 붙는다
  List<VideoTrack> tracks; // 비교용 트랙들(첫 번째가 기준). 최소 1개는 항상 있다
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
    List<VideoTrack>? tracks,
    this.loraUrl = '',
    this.loraStrength = 0.8,
    this.bgmPrompt = '',
    this.bgmPath,
    this.bgmSeconds = 30,
    this.note = '',
  }) : tracks = (tracks == null || tracks.isEmpty)
            ? [VideoTrack(id: '${id}_track1', name: '트랙 1')]
            : tracks;

  /// 기준 트랙 — 구조(비트·샷)의 정본. 비트/샷 추가·삭제는 여기에만 한다.
  VideoTrack get baseTrack => tracks.first;

  /// 씬의 구조(=기준 트랙의 비트들). 트랙끼리 구조가 같으므로 개수·순서를 물을 땐 이걸 본다.
  List<DialogueBeat> get beats => baseTrack.beats;

  /// 씬 전체 길이(초) — 각 대사의 실제 길이(=샷 길이 합)의 합.
  double get totalSeconds => beats.fold(0, (a, s) => a + s.seconds);

  /// 씬 안 샷 총 개수.
  int get shotCount => beats.fold(0, (a, s) => a + s.shots.length);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'commonPrompt': commonPrompt,
        'tracks': tracks.map((t) => t.toJson()).toList(),
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
      tracks: _readTracks(j, dir),
      loraUrl: (lora?['url'] as String?) ?? '',
      loraStrength: (lora?['strength'] as num?)?.toDouble() ?? 0.8,
      bgmPrompt: (bgm?['prompt'] as String?) ?? '',
      bgmPath: mediaPath(dir, bgm?['file']),
      bgmSeconds: (bgm?['seconds'] as int?) ?? 30,
      note: (j['note'] as String?) ?? '',
    );
  }

  /// 트랙 읽기 — 트랙이 없던 시절의 파일(`dialogues`)은 그 비트들을 **기준 트랙 하나**로 읽는다.
  static List<VideoTrack> _readTracks(Map<String, dynamic> j, String dir) {
    final tracks = (j['tracks'] as List?)
        ?.map((e) => VideoTrack.fromJson((e as Map).cast<String, dynamic>(), dir))
        .toList();
    if (tracks != null && tracks.isNotEmpty) return tracks;
    return [
      VideoTrack(
        id: '${j['id']}_track1',
        name: '트랙 1',
        beats: ((j['dialogues'] as List?) ?? const [])
            .map((e) =>
                DialogueBeat.fromJson((e as Map).cast<String, dynamic>(), dir))
            .toList(),
      ),
    ];
  }
}
