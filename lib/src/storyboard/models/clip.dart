/// 영상 한 조각(clip). 샷(Shot) 안에 여러 개가 순서대로 들어간다 — 1샷 = 여러 클립.
/// 한 클립은 시작·끝 두 키프레임에서 FE2V(first-end-to-video)로 영상을 만든다 — 두 장 필수.
/// 같은 샷의 클립들은 그 샷의 대사(음성) 시간을 나눠 덮는다(첫 클립 립싱크, 나머지 컷어웨이).
///
/// 저장(JSON)은 개념별로 중첩한다 — startScene/endScene/video — 파일만 봐도 구성이 읽힌다.
/// 미디어는 프로젝트 폴더 안 파일명(상대)만 저장하고, 런타임에는 절대경로로 다룬다.
/// (제작 상태·메모는 클립이 아니라 상위 [Shot]에 있다.)
class VideoClip {
  String id;
  String title; // 클립 제목 (비우면 CLIP n 으로 표시)
  List<String> refCharacterIds; // 이 클립 화면의 참조 인물 id들(FireRed 멀티, 최대 3)
  String startPrompt; // 시작장면 프롬프트
  String endPrompt; // 끝장면 프롬프트
  String videoPrompt; // 영상용 프롬프트
  int videoSeconds; // 이 클립의 영상 길이(초, 1~15)
  String? startImagePath; // 생성된 시작장면 파일 경로(런타임 절대경로)
  String? endImagePath; // 생성된 끝장면 파일 경로
  String? videoPath; // 생성된 영상 파일 경로

  VideoClip({
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
  /// 신 스키마(중첩)를 우선 읽고, 없으면 구 스키마(플랫)로 폴백한다.
  factory VideoClip.fromJson(Map<String, dynamic> j, String dir) {
    final start = (j['startScene'] as Map?)?.cast<String, dynamic>();
    final end = (j['endScene'] as Map?)?.cast<String, dynamic>();
    final video = (j['video'] as Map?)?.cast<String, dynamic>();
    // 신 스키마: video.file. 구 스키마: video.low.file(업스케일 시절).
    final low = (video?['low'] as Map?)?.cast<String, dynamic>();
    final endPrompt =
        (end?['prompt'] as String?) ?? (j['endPrompt'] as String?) ?? '';
    final endImagePath = mediaPath(dir, end?['image'] ?? j['endImagePath']);
    return VideoClip(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      // 신 스키마(refCharacters 리스트) 우선, 구 스키마(refCharacter 단일)는 감싸서 흡수.
      refCharacterIds: ((j['refCharacters'] as List?)?.cast<String>()) ??
          (j['refCharacter'] != null ? [j['refCharacter'] as String] : null),
      // 구버전(prompt/imagePath 단일)은 시작장면으로 옮겨 받는다.
      startPrompt: (start?['prompt'] as String?) ??
          (j['startPrompt'] as String?) ??
          (j['prompt'] as String?) ??
          '',
      endPrompt: endPrompt,
      videoPrompt:
          (video?['prompt'] as String?) ?? (j['videoPrompt'] as String?) ?? '',
      videoSeconds:
          (video?['seconds'] as int?) ?? (j['videoSeconds'] as int?) ?? 5,
      startImagePath: mediaPath(
          dir, start?['image'] ?? j['startImagePath'] ?? j['imagePath']),
      endImagePath: endImagePath,
      videoPath: mediaPath(
          dir, video?['file'] ?? low?['file'] ?? j['videoLowPath']),
    );
  }
}

/// 미디어 절대경로 → JSON 저장용 파일명(상대). 미디어는 전부 프로젝트 폴더 안에 있다.
String? mediaName(String? absPath) =>
    (absPath == null || absPath.isEmpty) ? null : absPath.split('/').last;

/// JSON의 파일명(또는 구버전 절대경로) → 현재 프로젝트 폴더 기준 절대경로.
/// 항상 basename만 취해 [dir]에 붙이므로 프로젝트 폴더를 옮겨도 경로가 살아난다.
String? mediaPath(String dir, Object? nameOrPath) {
  if (nameOrPath is! String || nameOrPath.isEmpty) return null;
  return '$dir/${nameOrPath.split('/').last}';
}
