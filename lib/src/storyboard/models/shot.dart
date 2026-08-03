import 'sfx.dart';
import 'text_overlay.dart';

/// 영상 생성 방식 — 네 갈래(명시적 상태). 끝 프레임이 필요한 건 FE2V 하나뿐이다.
///  - [fe2v]: 시작·끝 두 장을 고정하고 그 사이를 AI로 생성(기본). 끝 그림이 정해진다.
///  - [i2v]: 시작 한 장만 고정하고 끝은 모델이 자유롭게 — 끝장면은 안 쓴다.
///  - [still]: AI 없이 **시작 프레임 한 장을 그대로** 영상 길이만큼 채운다(로컬 ffmpeg).
///    켄번스([StillEffect])로 줌 인/아웃도 준다.
///  - [ia2v]: 시작 한 장 + **그 비트의 대사 음성**을 함께 넣어, 그 음성에 맞춰 입까지 움직이는
///    영상을 한 번에 만든다(자체 서버 `video-ltx-ia2v`). 끝 프레임은 서버가 시작 프레임으로
///    물려 구도를 잡으므로 따로 만들지 않는다. 대사 음성이 먼저 있어야 한다.
enum VideoMode { fe2v, i2v, still, ia2v }

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
/// ## 트랙 상속(파생 샷)
/// 비트와 **똑같은 규칙**이다 — 첫 트랙(기준)의 샷이 원본이고([baseId]=null), 파생 트랙의 샷은
/// 진짜로 비어 있다. 타입 필드(프롬프트·프레임·길이 등)를 쓰지 않고 **손댄 필드만** [overrides]
/// 맵에 담는다. 읽을 때 overrides에 있으면 그 값, 없으면 기준 샷([base])을 참조(폴백)한다.
/// 그래서 파생 샷이 기준 샷 내용을 복사해 들고 있는 일이 없다 — 기준이 파생 편집으로 바뀔 수 없다.
///
/// 예외 — **영상 결과물**: [videoPath]와 실측 길이 [videoActualSeconds]는 오버라이드가 아니라
/// **언제나 이 샷(트랙) 소유**다. 같은 콘티를 백엔드별로 뽑아 비교하려는 게 트랙을 나눈 이유라,
/// 영상은 트랙마다 따로 갖는다(없으면 상속 영상을 보여 주되, 저장은 자기 것만).
///
/// 저장(JSON): 기준 샷은 개념별 중첩(startScene/endScene/video), 파생 샷은 `overrides`(손댄 것만)
/// + `video`(자기 결과물)만 적는다.
class Shot {
  // ── 오버라이드 키 (파생 샷의 [overrides] 맵에서 쓰는 필드 이름) ──
  static const kTitle = 'title';
  static const kVideoPrompt = 'videoPrompt';
  static const kVideoPromptKo = 'videoPromptKo';
  static const kVideoNeg = 'videoNegativePrompt';
  static const kVideoSeconds = 'videoSeconds';
  static const kStartImage = 'startImage'; // 절대경로(메모리) / 파일명(JSON)
  static const kEndImage = 'endImage';
  static const kVideoMode = 'videoMode';
  static const kStillEffect = 'stillEffect';
  static const kNote = 'note';
  static const kSfx = 'sfx'; // Sfx? (null=명시적 없음)
  static const kTextOverlay = 'textOverlay'; // TextOverlay? (null=명시적 없음)
  static const kVideoNote = 'videoNote';

  String id;

  // ── 기준 샷(baseId==null)의 타입 필드. 파생 샷에서는 쓰지 않는다(overrides로 간다). ──
  String title;
  String videoPrompt; // 생성에 실제로 쓰이는 원문
  String videoPromptKo;
  String videoNegativePrompt; // **빼고 싶은 것만** — 부정은 전부 여기로
  double videoSeconds; // **주문할** 영상 길이(초)
  String? startImagePath; // 생성된 시작장면 파일 경로(런타임 절대경로)
  String? endImagePath;
  VideoMode videoMode;
  StillEffect stillEffect;
  String note; // 장면 탭 메모
  String videoNote; // 영상 탭 메모(장면 메모와 별개)

  /// 이 샷의 효과음(0 또는 1). null = 없음.
  /// 효과음은 백엔드와 무관하므로 **트랙끼리 공유**한다(기준 샷에 두고 파생은 상속).
  /// 비트가 아니라 샷에 붙는다 — 한 대사를 여러 샷이 덮을 때 소리가 나야 할 자리는
  /// 대사 전체가 아니라 특정 컷이라서.
  Sfx? sfx;

  /// 이 샷에 **구워 넣는 글씨**(0 또는 1). null = 없음.
  /// 타이틀 카드·썸네일 프레임이 이걸 쓴다 — 내보낼 때 프레임에 구워진다.
  TextOverlay? textOverlay;

  // ── 언제나 이 샷(트랙) 소유 — 오버라이드/상속 대상이 아니다 ──
  double? videoActualSeconds; // 뽑힌 영상의 실제 길이(초). 없으면 아직 안 뽑음
  String? videoPath; // 생성된 영상 파일 경로
  // 비동기 생성 진행 중인 서버 job_id. 있으면 '아직 생성 중'(결과 대기) — 앱을 껐다 켜도
  // 이 값이 저장돼 있어 리컨실러가 다시 주워서 완성분을 받아온다. 완료되면 videoPath로 바뀌고 null.
  String? videoJobId;

  /// 파생 트랙(트랙2…)에서 이 샷이 비추고 있는 **기준 트랙 샷의 id**. null = 기준 트랙 자신.
  String? baseId;

  /// 파생 샷이 **손댄 필드만** 담는 스파스 맵. 키 있으면 오버라이드, 없으면 기준 샷 상속.
  Map<String, Object?> overrides;

  Shot({
    required this.id,
    this.title = '',
    this.videoPrompt = '',
    this.videoPromptKo = '',
    this.videoNegativePrompt = '',
    this.videoSeconds = 5,
    this.videoActualSeconds,
    this.startImagePath,
    this.endImagePath,
    this.videoPath,
    this.videoJobId,
    this.videoMode = VideoMode.fe2v,
    this.stillEffect = StillEffect.none,
    this.note = '',
    this.videoNote = '',
    this.sfx,
    this.textOverlay,
    this.baseId,
    Map<String, Object?>? overrides,
  }) : overrides = overrides ?? {};

  /// 파생 트랙의 샷인지(기준 트랙이면 false).
  bool get isDerived => baseId != null;

  /// 이 필드가 이 샷에서 **자기 것으로 오버라이드**됐는지(파생 샷에서만 의미).
  bool overrode(String key) => overrides.containsKey(key);

  // ───────── 리졸버: [base] = 이 샷이 비추는 기준 샷(기준 샷이면 null을 넘긴다) ─────────
  // 기준 샷은 자기 타입 필드를, 파생 샷은 overrides에 있으면 그 값·없으면 base 값을 준다.

  V _r<V>(String key, Shot? base, V Function(Shot) pick) {
    if (!isDerived) return pick(this);
    if (overrides.containsKey(key)) return overrides[key] as V;
    return pick(base ?? this);
  }

  String resolvedTitle(Shot? b) => _r(kTitle, b, (s) => s.title);
  String resolvedVideoPrompt(Shot? b) => _r(kVideoPrompt, b, (s) => s.videoPrompt);
  String resolvedVideoPromptKo(Shot? b) =>
      _r(kVideoPromptKo, b, (s) => s.videoPromptKo);
  String resolvedVideoNeg(Shot? b) => _r(kVideoNeg, b, (s) => s.videoNegativePrompt);
  double resolvedVideoSeconds(Shot? b) => _r(kVideoSeconds, b, (s) => s.videoSeconds);
  String? resolvedStartImage(Shot? b) =>
      _r(kStartImage, b, (s) => s.startImagePath);
  String? resolvedEndImage(Shot? b) => _r(kEndImage, b, (s) => s.endImagePath);
  VideoMode resolvedVideoMode(Shot? b) => _r(kVideoMode, b, (s) => s.videoMode);
  StillEffect resolvedStillEffect(Shot? b) =>
      _r(kStillEffect, b, (s) => s.stillEffect);
  String resolvedNote(Shot? b) => _r(kNote, b, (s) => s.note);
  String resolvedVideoNote(Shot? b) => _r(kVideoNote, b, (s) => s.videoNote);

  /// 이 샷 자리의 효과음 — 기준 샷 것을 상속하되, 파생에서 손대면 그것.
  Sfx? resolvedSfx(Shot? b) => !isDerived
      ? sfx
      : (overrides.containsKey(kSfx) ? overrides[kSfx] as Sfx? : b?.sfx);

  /// 이 샷 자리에 구워질 글씨 — 기준 샷 것을 상속하되, 파생에서 손대면 그것.
  /// (언어별 트랙이 같은 카드에 각자 문구를 얹을 수 있어야 해서 오버라이드 대상이다.)
  TextOverlay? resolvedTextOverlay(Shot? b) => !isDerived
      ? textOverlay
      : (overrides.containsKey(kTextOverlay)
          ? overrides[kTextOverlay] as TextOverlay?
          : b?.textOverlay);

  /// 이 샷 자리에 **걸리는 영상** — 자기 트랙에서 뽑았으면 그것, 없으면 기준 샷 것 상속.
  /// 영상은 오버라이드가 아니라 트랙별 소유라 [overrides]를 거치지 않는다(위 주석 참고).
  /// 화면·미리보기·내보내기가 모두 이걸 통해야 셋이 같은 영상을 가리킨다.
  String? resolvedVideoPath(Shot? base) =>
      videoPath ?? (isDerived ? base?.videoPath : null);

  /// 타임라인에 쓰는 길이 — **뽑힌 게 있으면 실제 길이**, 없으면 주문한 길이.
  /// 실측이 0(측정 실패)이면 [orderedSeconds]로 떨어진다. 파생 샷의 주문 길이는 리졸버로
  /// 해석해야 하므로 [base]가 필요하다(자기 영상이 있으면 base 없이도 실측으로 답한다).
  double playSecondsWith(Shot? base) =>
      (videoActualSeconds != null && videoActualSeconds! > 0)
          ? videoActualSeconds!
          : resolvedVideoSeconds(base);

  /// 끝 프레임이 필요한 방식인지 — FE2V 하나뿐.
  bool needsEndFrameWith(Shot? b) => resolvedVideoMode(b) == VideoMode.fe2v;

  /// AI 없이 시작 프레임을 그대로 영상화하는 스틸컷인지.
  bool isStillWith(Shot? b) => resolvedVideoMode(b) == VideoMode.still;

  /// 이 샷이 영상을 뽑을 준비가 됐는지 — 끝 프레임은 FE2V만 필요.
  bool videoInputsReadyWith(Shot? b) {
    final start = resolvedStartImage(b);
    final end = resolvedEndImage(b);
    return (start?.isNotEmpty ?? false) &&
        (!needsEndFrameWith(b) || (end?.isNotEmpty ?? false));
  }

  Map<String, dynamic> toJson() {
    if (isDerived) {
      // 파생 샷: 손댄 것(overrides) + 자기 영상 결과물만.
      return {
        'id': id,
        'base': baseId,
        'overrides': _overridesToJson(),
        'video': {
          'file': mediaName(videoPath),
          'actualSeconds': videoActualSeconds,
          'jobId': videoJobId,
        },
      };
    }
    return {
      'id': id,
      'title': title,
      'startScene': {'image': mediaName(startImagePath)},
      'endScene': {'image': mediaName(endImagePath)},
      'video': {
        'prompt': videoPrompt,
        'promptKo': videoPromptKo,
        'negativePrompt': videoNegativePrompt,
        'seconds': videoSeconds,
        'actualSeconds': videoActualSeconds,
        'file': mediaName(videoPath),
        'jobId': videoJobId,
        'mode': videoMode.name,
        'stillEffect': stillEffect.name,
        'note': videoNote,
      },
      'sfx': sfx?.toJson(), // null = 효과음 없음
      'textOverlay': textOverlay?.toJson(), // null = 얹는 글씨 없음
      'note': note,
    };
  }

  /// overrides 맵을 JSON으로 — 이미지 경로는 파일명으로, enum은 name으로 직렬화.
  /// **키 존재 = 오버라이드**라, 값이 null인 키(명시적 없음)도 남긴다.
  Map<String, dynamic> _overridesToJson() {
    final out = <String, dynamic>{};
    for (final e in overrides.entries) {
      final v = e.value;
      out[e.key] = switch (e.key) {
        kStartImage || kEndImage => mediaName(v as String?),
        kVideoMode => (v as VideoMode).name,
        kStillEffect => (v as StillEffect).name,
        kSfx => (v as Sfx?)?.toJson(),
        kTextOverlay => (v as TextOverlay?)?.toJson(),
        _ => v, // String / double / bool / List<String> / null
      };
    }
    return out;
  }

  /// [dir] = 프로젝트 폴더(미디어 파일명을 절대경로로 되살릴 기준).
  factory Shot.fromJson(Map<String, dynamic> j, String dir) {
    final baseId = j['base'] as String?;
    if (baseId != null) {
      final video = (j['video'] as Map?)?.cast<String, dynamic>();
      return Shot(
        id: j['id'] as String,
        baseId: baseId,
        overrides: _overridesFromJson(
            (j['overrides'] as Map?)?.cast<String, dynamic>(), dir),
        videoActualSeconds: (video?['actualSeconds'] as num?)?.toDouble(),
        videoPath: mediaPath(dir, video?['file']),
        videoJobId: video?['jobId'] as String?,
      );
    }
    final start = (j['startScene'] as Map?)?.cast<String, dynamic>();
    final end = (j['endScene'] as Map?)?.cast<String, dynamic>();
    final video = (j['video'] as Map?)?.cast<String, dynamic>();
    final sfxJson = (j['sfx'] as Map?)?.cast<String, dynamic>();
    final overlayJson = (j['textOverlay'] as Map?)?.cast<String, dynamic>();
    return Shot(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      videoPrompt: (video?['prompt'] as String?) ?? '',
      videoPromptKo: (video?['promptKo'] as String?) ?? '',
      videoNegativePrompt: (video?['negativePrompt'] as String?) ?? '',
      videoSeconds: (video?['seconds'] as num?)?.toDouble() ?? 5,
      videoActualSeconds: (video?['actualSeconds'] as num?)?.toDouble(),
      startImagePath: mediaPath(dir, start?['image']),
      endImagePath: mediaPath(dir, end?['image']),
      videoPath: mediaPath(dir, video?['file']),
      videoJobId: video?['jobId'] as String?,
      videoMode: _readVideoMode(video),
      stillEffect: StillEffect.values.firstWhere(
        (e) => e.name == video?['stillEffect'],
        orElse: () => StillEffect.none,
      ),
      note: (j['note'] as String?) ?? '',
      videoNote: (video?['note'] as String?) ?? '',
      sfx: sfxJson == null ? null : Sfx.fromJson(sfxJson, dir),
      textOverlay: overlayJson == null ? null : TextOverlay.fromJson(overlayJson),
    );
  }

  static Map<String, Object?> _overridesFromJson(
      Map<String, dynamic>? j, String dir) {
    final out = <String, Object?>{};
    if (j == null) return out;
    for (final e in j.entries) {
      switch (e.key) {
        case kStartImage:
        case kEndImage:
          out[e.key] = mediaPath(dir, e.value);
        case kVideoMode:
          out[e.key] = VideoMode.values.firstWhere(
              (v) => v.name == e.value,
              orElse: () => VideoMode.fe2v);
        case kStillEffect:
          out[e.key] = StillEffect.values.firstWhere(
              (v) => v.name == e.value,
              orElse: () => StillEffect.none);
        case kVideoSeconds:
          out[e.key] = (e.value as num?)?.toDouble();
        case kSfx:
          final m = (e.value as Map?)?.cast<String, dynamic>();
          out[e.key] = m == null ? null : Sfx.fromJson(m, dir);
        case kTextOverlay:
          final m = (e.value as Map?)?.cast<String, dynamic>();
          out[e.key] = m == null ? null : TextOverlay.fromJson(m);
        default:
          out[e.key] = e.value; // String / bool / null
      }
    }
    return out;
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
String? mediaPath(String dir, Object? nameOrPath) {
  if (nameOrPath is! String || nameOrPath.isEmpty) return null;
  return '$dir/${nameOrPath.split('/').last}';
}
