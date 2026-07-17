/// 영상 한 조각(shot). 대사(DialogueBeat) 안에 여러 개가 순서대로 들어간다 — 1대사 = 여러 샷.
/// 한 샷은 시작·끝 두 키프레임에서 FE2V(first-end-to-video)로 영상을 만든다 — 두 장 필수.
/// 같은 대사의 샷들은 그 대사의 음성 길이를 나눠 덮는다(첫 샷 립싱크, 나머지 컷어웨이).
///
/// 저장(JSON)은 개념별로 중첩한다 — startScene/endScene/video — 파일만 봐도 구성이 읽힌다.
/// 미디어는 프로젝트 폴더 안 파일명(상대)만 저장하고, 런타임에는 절대경로로 다룬다.
/// (제작 상태·메모는 샷이 아니라 상위 [DialogueBeat]에 있다.)
class Shot {
  String id;
  String title; // 샷 제목 (비우면 '샷 n' 으로 표시)
  List<String> refCharacterIds; // 이 샷 화면의 참조 인물 id들(FireRed 멀티, 최대 3)
  String startPrompt; // 시작장면 프롬프트
  String endPrompt; // 끝장면 프롬프트
  String videoPrompt; // 영상용 프롬프트
  int videoSeconds; // 이 샷의 영상 길이(초, 1~15)
  String? startImagePath; // 생성된 시작장면 파일 경로(런타임 절대경로)
  String? endImagePath; // 생성된 끝장면 파일 경로
  String? videoPath; // 생성된 영상 파일 경로

  Shot({
    required this.id,
    this.title = '',
    List<String>? refCharacterIds,
    this.startPrompt = '',
    this.endPrompt = '',
    this.videoPrompt = '',
    this.videoSeconds = 5,
    this.startImagePath,
    this.endImagePath,
    this.videoPath,
  }) : refCharacterIds = refCharacterIds ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'refCharacters': refCharacterIds,
        'startScene': {'prompt': startPrompt, 'image': mediaName(startImagePath)},
        'endScene': {
          'prompt': endPrompt,
          'image': mediaName(endImagePath),
        },
        'video': {
          'prompt': videoPrompt,
          'seconds': videoSeconds,
          'file': mediaName(videoPath),
        },
      };

  /// [dir] = 프로젝트 폴더(미디어 파일명을 절대경로로 되살릴 기준).
  factory Shot.fromJson(Map<String, dynamic> j, String dir) {
    final start = (j['startScene'] as Map?)?.cast<String, dynamic>();
    final end = (j['endScene'] as Map?)?.cast<String, dynamic>();
    final video = (j['video'] as Map?)?.cast<String, dynamic>();
    return Shot(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      refCharacterIds: (j['refCharacters'] as List?)?.cast<String>(),
      startPrompt: (start?['prompt'] as String?) ?? '',
      endPrompt: (end?['prompt'] as String?) ?? '',
      videoPrompt: (video?['prompt'] as String?) ?? '',
      videoSeconds: (video?['seconds'] as int?) ?? 5,
      startImagePath: mediaPath(dir, start?['image']),
      endImagePath: mediaPath(dir, end?['image']),
      videoPath: mediaPath(dir, video?['file']),
    );
  }
}

/// 미디어 절대경로 → JSON 저장용 파일명(상대). 미디어는 전부 프로젝트 폴더 안에 있다.
String? mediaName(String? absPath) =>
    (absPath == null || absPath.isEmpty) ? null : absPath.split('/').last;

/// JSON의 파일명 → 현재 프로젝트 폴더 기준 절대경로.
/// 항상 basename만 취해 [dir]에 붙이므로 프로젝트 폴더를 옮겨도 경로가 살아난다.
String? mediaPath(String dir, Object? nameOrPath) {
  if (nameOrPath is! String || nameOrPath.isEmpty) return null;
  return '$dir/${nameOrPath.split('/').last}';
}
