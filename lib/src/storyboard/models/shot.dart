import 'clip.dart';
import 'dialogue.dart';

/// 샷의 제작 진행 상태(순수 편집/워크플로용 — 생성과 무관). 칸반처럼 상태를 추적한다.
enum ShotStatus {
  ready('준비'),
  inProgress('진행'),
  review('검토'),
  rejected('반려'),
  done('완료');

  const ShotStatus(this.label);
  final String label;
}

/// 샷(Shot) = 씬 타임라인의 한 단위(비트). **1개의 대사(선택) + 여러 클립**을 담는다.
///
/// 드라마 제작의 기준은 대본이다 — 한 샷은 보통 대사 한 마디이고, 그 대사를 화면으로
/// 덮는 클립이 여러 개 붙는다(1대사 = 2,3클립). 첫 클립은 입 모양을 맞추고(립싱크),
/// 나머지는 컷어웨이(대사는 계속 흐름). 대사가 없으면([dialogue]=null) 무음 샷(establishing·지문).
///
/// 저장(JSON)은 개념별로 중첩한다 — dialogue / clips — 파일만 봐도 구성이 읽힌다.
class Shot {
  String id;
  String title; // 샷 제목 (비우면 SHOT n 으로 표시)
  String note; // 사용자 메모(특이사항) — 프롬프트와 무관, 생성에 안 쓰임
  ShotStatus status; // 제작 진행 상태 — 사용자가 수동으로 정함(생성과 무관)
  Dialogue? dialogue; // 이 샷의 대사(0 또는 1). null = 무음 샷
  List<VideoClip> clips; // 이 샷을 화면으로 덮는 클립들(순서대로)

  Shot({
    required this.id,
    this.title = '',
    this.note = '',
    this.status = ShotStatus.ready,
    this.dialogue,
    List<VideoClip>? clips,
  }) : clips = clips ?? [];

  bool get hasDialogue => dialogue != null;

  /// 이 샷의 클립 길이 합(초).
  int get clipSeconds => clips.fold(0, (a, c) => a + c.videoSeconds);

  /// 이 샷의 길이(초): 대사 음성이 있으면 그 길이, 없으면 클립 길이 합.
  /// (대사가 타임라인 길이를 정하고, 클립들이 그 시간을 덮는 구조.)
  double get seconds {
    final v = dialogue?.voiceSeconds ?? 0;
    return v > 0 ? v : clipSeconds.toDouble();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'status': status.name,
        'dialogue': dialogue?.toJson(), // null = 무음 샷
        'clips': clips.map((c) => c.toJson()).toList(),
      };

  /// [dir] = 프로젝트 폴더(미디어 파일명을 절대경로로 되살릴 기준).
  factory Shot.fromJson(Map<String, dynamic> j, String dir) {
    final dlg = (j['dialogue'] as Map?)?.cast<String, dynamic>();
    return Shot(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      note: (j['note'] as String?) ?? '',
      status: ShotStatus.values.firstWhere(
        (e) => e.name == j['status'],
        orElse: () => ShotStatus.ready,
      ),
      dialogue: dlg == null ? null : Dialogue.fromJson(dlg, dir),
      clips: ((j['clips'] as List?) ?? const [])
          .map((e) => VideoClip.fromJson((e as Map).cast<String, dynamic>(), dir))
          .toList(),
    );
  }

  /// 구버전 마이그레이션: 씬이 클립(옛 flat 영상 단위) 리스트였을 때, 각 클립을
  /// **클립 1개짜리 무음 샷**으로 감싼다. 옛 status/note는 샷으로 끌어올린다.
  factory Shot.fromLegacyClip(Map<String, dynamic> j, String dir) {
    final clip = VideoClip.fromJson(j, dir);
    return Shot(
      id: 'shot_${clip.id}',
      title: clip.title,
      note: (j['note'] as String?) ?? '',
      status: ShotStatus.values.firstWhere(
        (e) => e.name == j['status'],
        orElse: () => ShotStatus.ready,
      ),
      dialogue: null,
      clips: [clip],
    );
  }
}
