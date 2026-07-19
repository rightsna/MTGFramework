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
  String startPromptKo; // 위 프롬프트의 한국어 번역 — 확인용, 생성엔 안 쓰임
  String endPrompt; // 끝장면 프롬프트
  String endPromptKo; // 위 프롬프트의 한국어 번역 — 확인용, 생성엔 안 쓰임
  String videoPrompt; // 영상용 프롬프트(생성에 실제로 쓰이는 원문)
  String videoPromptKo; // 위 프롬프트의 한국어 번역 — 읽고 확인하는 용도, 생성엔 안 쓰임
  int videoSeconds; // 이 샷의 영상 길이(초, 1~15)
  String? startImagePath; // 생성된 시작장면 파일 경로(런타임 절대경로)
  String? endImagePath; // 생성된 끝장면 파일 경로
  String? videoPath; // 생성된 영상 파일 경로

  /// 시작장면을 **앞 샷의 끝장면에 연동**한다(컷이 이어지는 기본 동선).
  /// 켜져 있으면 앞 샷의 끝 이미지·프롬프트가 이 샷의 시작으로 따라 들어오고,
  /// 시작장면은 직접 만들거나 고칠 수 없다(읽기 전용).
  ///
  /// 이미지는 참조가 아니라 **복사**한다 — 앞 샷 파일을 지워도 이 샷이 깨지지 않고,
  /// FE2V 입력·미리보기 등 경로를 읽는 쪽이 전부 그대로 동작한다.
  /// 씬의 첫 샷은 물려받을 앞이 없어 항상 꺼진 상태다.
  bool linkStart;

  /// 영상 생성 방식. 같은 모델·같은 그래프고, 끝 프레임을 박느냐만 다르다.
  ///  - false = **FE2V**(기본): 시작·끝 두 장을 고정하고 그 사이를 생성. 끝 그림이 정해진다.
  ///  - true  = **I2V**: 시작 한 장만 고정하고 끝은 모델이 자유롭게 — 끝장면은 안 쓴다.
  bool i2v;

  Shot({
    required this.id,
    this.title = '',
    List<String>? refCharacterIds,
    this.startPrompt = '',
    this.startPromptKo = '',
    this.endPrompt = '',
    this.endPromptKo = '',
    this.videoPrompt = '',
    this.videoPromptKo = '',
    this.videoSeconds = 5,
    this.startImagePath,
    this.endImagePath,
    this.videoPath,
    this.linkStart = false,
    this.i2v = false,
  }) : refCharacterIds = refCharacterIds ?? [];

  /// 이 샷이 영상을 뽑을 준비가 됐는지 — I2V는 시작만, FE2V는 시작·끝 둘 다 필요.
  bool get videoInputsReady =>
      (startImagePath?.isNotEmpty ?? false) &&
      (i2v || (endImagePath?.isNotEmpty ?? false));

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'refCharacters': refCharacterIds,
        'startScene': {
          'prompt': startPrompt,
          'promptKo': startPromptKo,
          'image': mediaName(startImagePath),
          'inherit': linkStart,
        },
        'endScene': {
          'prompt': endPrompt,
          'promptKo': endPromptKo,
          'image': mediaName(endImagePath),
        },
        'video': {
          'prompt': videoPrompt,
          'promptKo': videoPromptKo,
          'seconds': videoSeconds,
          'file': mediaName(videoPath),
          'i2v': i2v,
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
      startPromptKo: (start?['promptKo'] as String?) ?? '',
      endPrompt: (end?['prompt'] as String?) ?? '',
      endPromptKo: (end?['promptKo'] as String?) ?? '',
      videoPrompt: (video?['prompt'] as String?) ?? '',
      videoPromptKo: (video?['promptKo'] as String?) ?? '',
      videoSeconds: (video?['seconds'] as int?) ?? 5,
      startImagePath: mediaPath(dir, start?['image']),
      endImagePath: mediaPath(dir, end?['image']),
      videoPath: mediaPath(dir, video?['file']),
      // 'inherit'가 없는 옛 데이터는 꺼진 걸로 읽는다 — 켠 걸로 보면 이미 만들어 둔
      // 시작 프레임을 앞 샷 것으로 말없이 갈아치우게 된다.
      linkStart: (start?['inherit'] as bool?) ?? false,
      // 'i2v'가 없는 옛 데이터는 FE2V(끝 프레임 사용)로 읽는다 — 지금까지 만든 게 전부 그거다.
      i2v: (video?['i2v'] as bool?) ?? false,
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
