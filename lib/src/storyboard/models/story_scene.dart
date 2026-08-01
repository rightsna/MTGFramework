import 'shot.dart'; // mediaName / mediaPath
import 'dialogue_beat.dart';
import 'video_track.dart';
import '../services/movie_settings.dart'; // ImageRes / VideoRes

/// 한 씬(scene) = **트랙들**. 각 트랙이 같은 타임라인(대사의 나열)을 서로 다른 백엔드로 뽑는다.
/// 계층: 씬 > 트랙 > 대사(DialogueBeat: 대사 1개(선택) + 샷 여러 개) > 샷.
/// 첫 트랙이 기준([baseTrack])이고, 구조(비트·샷)는 트랙끼리 항상 같다 — [VideoTrack] 참고.
///
/// 저장은 씬 하나당 `scene<N>.json` 한 파일. 개념별로 묶어서(tracks/bgm/res) 적어
/// JSON만 봐도 씬 구성이 읽히게 한다. 미디어는 프로젝트 폴더 안 파일명(상대)만 저장한다.
class StoryScene {
  String id;
  String title; // 씬 제목 (비우면 SCENE n 으로 표시)
  String commonPrompt; // 이 씬 공통 프롬프트 — 씬 내 모든 샷 생성에 함께 붙는다
  List<VideoTrack> tracks; // 비교용 트랙들(첫 번째가 기준). 최소 1개는 항상 있다
  // 기본 성우는 **트랙별**로 옮겼다([VideoTrack.defaultVoiceId]).
  String bgmPrompt; // 이 씬의 배경음 스타일 태그(장르·분위기·악기) — ACE-Step BGM 생성용
  String? bgmPath; // 생성된 배경음(mp3) 파일 경로(런타임 절대경로)
  int bgmSeconds; // 배경음 길이(초)
  String note; // 씬 메모(특이사항) — 프롬프트와 무관, 생성에 안 쓰임
  ImageRes imageRes; // 이 씬의 프레임(시작·끝) 생성 해상도 — **씬별**
  // 영상 해상도는 **트랙별**로 옮겼다([VideoTrack.videoRes]) — 백엔드가 트랙마다 다르니
  // 뽑히는 크기도 트랙마다 다른 게 사실이다.

  StoryScene({
    required this.id,
    this.title = '',
    this.commonPrompt = '',
    List<VideoTrack>? tracks,
    this.bgmPrompt = '',
    this.bgmPath,
    this.bgmSeconds = 30,
    this.note = '',
    this.imageRes = ImageRes.p704x1280,
  }) : tracks = (tracks == null || tracks.isEmpty)
            ? [VideoTrack(id: '${id}_track1', name: '트랙 1')]
            : tracks;

  /// 기준 트랙 — 구조(비트·샷)의 정본. 비트/샷 추가·삭제는 여기에만 한다.
  VideoTrack get baseTrack => tracks.first;

  /// 씬의 구조(=기준 트랙의 비트들). 트랙끼리 구조가 같으므로 개수·순서를 물을 땐 이걸 본다.
  List<DialogueBeat> get beats => baseTrack.beats;

  /// 씬 전체 길이(초) — 각 대사의 실제 길이(=샷 길이 합)의 합. 기준 트랙 기준이라 샷은 모두
  /// 기준 샷(base=null)이므로 자기 길이로 계산된다.
  double get totalSeconds => beats.fold(
      0.0,
      (a, b) =>
          a + b.shots.fold(0.0, (x, s) => x + s.playSecondsWith(null)));

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
        // 기본 성우는 트랙별로 옮겨 각 트랙 JSON에 적힌다(여기서 안 적는다).
        'res': {'image': imageRes.name}, // 영상 해상도는 각 트랙 JSON에 적힌다
        'note': note,
      };

  /// [dir] = 프로젝트 폴더(미디어 파일명을 절대경로로 되살릴 기준).
  factory StoryScene.fromJson(Map<String, dynamic> j, String dir) {
    final bgm = (j['bgm'] as Map?)?.cast<String, dynamic>();
    final res = (j['res'] as Map?)?.cast<String, dynamic>();
    // 옛 형식(씬 단위 해상도·성우, 트랙 없던 시절의 dialogues) 마이그레이션은 없다 —
    // 데이터를 새 형식으로 한 번에 옮기고 걷어냈다. 정본 스키마만 읽는다.
    return StoryScene(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      commonPrompt: (j['commonPrompt'] as String?) ?? '',
      tracks: (j['tracks'] as List?)
          ?.map((e) =>
              VideoTrack.fromJson((e as Map).cast<String, dynamic>(), dir))
          .toList(),
      bgmPrompt: (bgm?['prompt'] as String?) ?? '',
      bgmPath: mediaPath(dir, bgm?['file']),
      bgmSeconds: (bgm?['seconds'] as int?) ?? 30,
      note: (j['note'] as String?) ?? '',
      imageRes: ImageRes.values.firstWhere(
        (e) => e.name == res?['image'],
        orElse: () => ImageRes.p704x1280,
      ),
    );
  }
}
