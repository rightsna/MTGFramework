/// 영상 생성 방식 — 세 갈래(명시적 상태). 끝 프레임이 필요한 건 FE2V 하나뿐이다.
///  - [fe2v]: 시작·끝 두 장을 고정하고 그 사이를 AI로 생성(기본). 끝 그림이 정해진다.
///  - [i2v]: 시작 한 장만 고정하고 끝은 모델이 자유롭게 — 끝장면은 안 쓴다.
///  - [still]: AI 없이 **시작 프레임 한 장을 그대로** 영상 길이만큼 채운다(로컬 ffmpeg).
///    켄번스([StillEffect])로 줌 인/아웃도 준다.
enum VideoMode { fe2v, i2v, still }

/// 스틸컷의 켄번스 효과 — 사진첩 앨범 미리보기처럼 천천히 줌.
enum StillEffect {
  none('없음'),
  zoomIn('줌 인'),
  zoomOut('줌 아웃');

  const StillEffect(this.label);
  final String label;
}

/// 영상 한 조각(shot). 대사(DialogueBeat) 안에 여러 개가 순서대로 들어간다 — 1대사 = 여러 샷.
/// 한 샷은 시작·끝 두 키프레임에서 FE2V(first-end-to-video)로 영상을 만든다 — 두 장 필수.
/// 같은 대사의 샷들은 그 대사의 음성 길이를 나눠 덮는다(첫 샷 립싱크, 나머지 컷어웨이).
///
/// 저장(JSON)은 개념별로 중첩한다 — startScene/endScene/video — 파일만 봐도 구성이 읽힌다.
/// 미디어는 프로젝트 폴더 안 파일명(상대)만 저장하고, 런타임에는 절대경로로 다룬다.
/// (제작 상태는 상위 [DialogueBeat]에, 샷 자체 메모는 [note]에 있다.)
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

  /// 영상 네거티브 프롬프트 — **빼고 싶은 것만** 여기 적는다.
  /// 프롬프트 본문에 "no hand" 식으로 쓰면 오히려 그게 불려 나오므로(언급이 곧 소환),
  /// 부정은 전부 이 칸으로 보낸다. 비우면 서버 워크플로의 기본 네거티브를 그대로 쓴다.
  String videoNegativePrompt;
  /// 이 샷에 **주문할** 영상 길이(초). 하나로 통일된 값이다 —
  /// AI 방식은 정수 초로 다루고(슬라이더 1초 단위, 백엔드엔 반올림해 보냄),
  /// 스틸컷은 로컬 ffmpeg라 0.1초 단위까지 그대로 쓴다.
  double videoSeconds;

  /// 뽑힌 영상의 **실제 길이(초)**. 주문한 길이([videoSeconds])와 다를 수 있다 —
  /// 백엔드가 지원하는 길이로 내려가거나(Veo는 4·6·8초만), 트림으로 잘리거나,
  /// 모델이 몇 프레임 더 얹기도 한다. 없으면 아직 안 뽑은 것.
  ///
  /// **트랙마다 따로 갖는 값**이다([videoPath]와 한 몸) — 같은 콘티를 백엔드별로 뽑으면
  /// 결과 길이가 서로 다르고, 타임라인은 각 트랙의 실제 길이로 그려져야 한다.
  double? videoActualSeconds;
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

  /// 영상 생성 방식 — [VideoMode] 참고. 기본은 FE2V.
  VideoMode videoMode;

  /// 스틸컷일 때의 켄번스 효과(다른 방식에선 무시).
  StillEffect stillEffect;

  /// 장면 탭 메모(특이사항) — 프레임 작업용 기록. 프롬프트와 무관, 생성에 안 쓰임.
  String note;

  /// 영상 탭 메모 — 장면 메모와 **별개**다. 프레임에 적을 말과 영상에 적을 말이 다르다.
  String videoNote;

  /// 파생 트랙(트랙2…)에서 이 샷이 비추고 있는 **기준 트랙 샷의 id**. null = 기준 트랙의 샷 자신.
  /// 트랙끼리 구조는 항상 같으므로 파생 트랙의 샷은 반드시 짝이 있다.
  String? baseId;

  /// 파생 트랙 샷이 **자기 내용을 갖는지**. false(기본) = 기준 샷 내용을 그대로 따라간다.
  /// 따라가는 동안 자기 것은 [videoPath] 하나뿐 — 트랙을 나눈 이유가 그것뿐이라서다.
  /// 파생 트랙에서 내용을 고치면 그 샷만 true가 되고(기준 내용을 복사해 옴) 이후 독립한다.
  bool detached;

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
    this.videoNegativePrompt = '',
    this.videoSeconds = 5,
    this.videoActualSeconds,
    this.startImagePath,
    this.endImagePath,
    this.videoPath,
    this.linkStart = false,
    this.videoMode = VideoMode.fe2v,
    this.stillEffect = StillEffect.none,
    this.note = '',
    this.videoNote = '',
    this.baseId,
    this.detached = false,
  }) : refCharacterIds = refCharacterIds ?? [];

  /// 타임라인에 쓰는 길이 — **뽑힌 게 있으면 실제 길이**, 없으면 주문한 길이([videoSeconds]).
  /// 재생되는 건 파일이므로 화면·합계는 전부 이걸 봐야 한다.
  /// 실측이 0(측정 실패로 굳은 값)이면 주문값으로 떨어진다 — 0초로 표시되지 않게.
  double get playSeconds => (videoActualSeconds != null && videoActualSeconds! > 0)
      ? videoActualSeconds!
      : videoSeconds;

  /// 끝 프레임이 필요한 방식인지 — FE2V 하나뿐(I2V·스틸컷은 시작 한 장이면 된다).
  bool get needsEndFrame => videoMode == VideoMode.fe2v;

  /// AI 없이 시작 프레임을 그대로 영상화하는 스틸컷인지.
  bool get isStill => videoMode == VideoMode.still;

  /// 파생 트랙의 샷인지(기준 트랙이면 false).
  bool get isDerived => baseId != null;

  /// 기준 샷 내용을 그대로 따라가는 중인지 — 이 상태에서는 내용 편집이 잠긴다.
  bool get inherits => baseId != null && !detached;

  /// 기준 샷 [base]의 내용을 그대로 가져온다 — **영상([videoPath])과 정체성(id/연결정보)은 빼고**.
  /// 따라가는 샷을 기준에 맞추는 데도, 분리(detach)할 때 출발점을 만드는 데도 같은 규칙을 쓴다.
  void adoptContentFrom(Shot base) {
    title = base.title;
    refCharacterIds = [...base.refCharacterIds];
    startPrompt = base.startPrompt;
    startPromptKo = base.startPromptKo;
    endPrompt = base.endPrompt;
    endPromptKo = base.endPromptKo;
    videoPrompt = base.videoPrompt;
    videoPromptKo = base.videoPromptKo;
    videoNegativePrompt = base.videoNegativePrompt;
    videoSeconds = base.videoSeconds;
    startImagePath = base.startImagePath;
    endImagePath = base.endImagePath;
    linkStart = base.linkStart;
    videoMode = base.videoMode;
    stillEffect = base.stillEffect;
    note = base.note;
    videoNote = base.videoNote;
  }

  /// 이 샷이 영상을 뽑을 준비가 됐는지 — 끝 프레임은 FE2V만 필요, 나머지는 시작 한 장이면 된다.
  bool get videoInputsReady =>
      (startImagePath?.isNotEmpty ?? false) &&
      (!needsEndFrame || (endImagePath?.isNotEmpty ?? false));

  Map<String, dynamic> toJson() {
    // 따라가는 샷은 **자기 것만** 적는다 — 내용은 기준 샷 한 곳에만 있어야 둘이 어긋나지 않는다.
    if (inherits) {
      return {
        'id': id,
        'base': baseId,
        'detached': false,
        'video': {
          'file': mediaName(videoPath),
          'actualSeconds': videoActualSeconds,
        },
      };
    }
    return {
      'id': id,
      if (baseId != null) 'base': baseId,
      if (baseId != null) 'detached': true,
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
        'negativePrompt': videoNegativePrompt,
        'seconds': videoSeconds,
        'actualSeconds': videoActualSeconds, // 실제로 뽑힌 길이(주문값과 다를 수 있다)
        'file': mediaName(videoPath),
        'mode': videoMode.name,
        'stillEffect': stillEffect.name,
        'note': videoNote,
      },
      'note': note,
    };
  }

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
      // 'negativePrompt'가 없는 옛 데이터는 빈 값 — 서버 기본 네거티브가 그대로 쓰인다.
      videoNegativePrompt: (video?['negativePrompt'] as String?) ?? '',
      // 옛 데이터는 정수 초였다 — num으로 읽어 double로. (스틸컷은 0.1초까지 담긴다.)
      videoSeconds: (video?['seconds'] as num?)?.toDouble() ?? 5,
      videoActualSeconds: (video?['actualSeconds'] as num?)?.toDouble(),
      startImagePath: mediaPath(dir, start?['image']),
      endImagePath: mediaPath(dir, end?['image']),
      videoPath: mediaPath(dir, video?['file']),
      // 'inherit'가 없는 옛 데이터는 꺼진 걸로 읽는다 — 켠 걸로 보면 이미 만들어 둔
      // 시작 프레임을 앞 샷 것으로 말없이 갈아치우게 된다.
      linkStart: (start?['inherit'] as bool?) ?? false,
      // 'mode'가 새 키. 없는 옛 데이터는 'i2v'(bool)로 읽어 매핑한다 — 그것도 없으면 FE2V.
      videoMode: _readVideoMode(video),
      stillEffect: StillEffect.values.firstWhere(
        (e) => e.name == video?['stillEffect'],
        orElse: () => StillEffect.none,
      ),
      note: (j['note'] as String?) ?? '',
      videoNote: (video?['note'] as String?) ?? '',
      // 'base'가 있으면 파생 트랙의 샷 — 따라가는 중이면 위 내용은 전부 비어 있고,
      // 불러온 뒤 기준 샷에서 채워진다([StoryboardProvider] 트랙 동기화).
      baseId: j['base'] as String?,
      detached: (j['detached'] as bool?) ?? false,
    );
  }
}

/// 영상 방식 읽기 — 새 키 'mode' 우선, 없으면 옛 'i2v'(bool)을 FE2V/I2V로 매핑.
VideoMode _readVideoMode(Map<String, dynamic>? video) {
  final m = video?['mode'] as String?;
  if (m != null) {
    for (final v in VideoMode.values) {
      if (v.name == m) return v;
    }
  }
  return (video?['i2v'] as bool?) ?? false ? VideoMode.i2v : VideoMode.fe2v;
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
