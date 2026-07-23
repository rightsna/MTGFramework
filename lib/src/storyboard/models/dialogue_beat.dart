import 'shot.dart';
import 'dialogue.dart';
import 'sfx.dart';
import 'caption.dart';

/// 대사(DialogueBeat) = 씬 타임라인의 한 단위. **대사 내용 1개(선택) + 샷 여러 개**를 담는다.
/// 계층: 씬 > **대사** > 샷.
///
/// 드라마 제작의 기준은 대본이다 — 한 대사(한 마디)를 화면으로 덮는 샷이 여러 개 붙는다
/// (1대사 = 2~3샷). 첫 샷은 입 모양을 맞추고(립싱크), 나머지는 컷어웨이(대사는 계속 흐름).
/// 대사 내용이 없으면([dialogue]=null) 무음 대사(establishing·지문).
///
/// ## 트랙 상속(파생 비트)
/// 첫 트랙이 **기준 트랙**이고, 그 비트가 대본·연출의 원본이다([baseId]=null).
/// 트랙을 추가하면 파생 비트가 생기는데 — **파생 비트는 진짜로 비어 있다**. 타입 필드
/// (title/note/direction/dialogue의 대본/sfx/caption)를 쓰지 않고, 사용자가 **손댄 필드만**
/// [overrides] 맵에 하나씩 담는다({} → {'text': '...'}). 그래서 파생 비트가 기준 비트의
/// 값을 **복사해 들고 있는 일이 없다** — 트랙1이 파생 편집으로 바뀌는 사고가 구조적으로 불가능.
///
/// 읽을 때는 [overrides]에 있으면 그 값, 없으면 기준 비트([base])를 참조한다(폴백). 이 해석은
/// [resolvedTitle] 등 리졸버 메서드가 담당하며, `containsKey`로 판단하므로 **"명시적 없음"**
/// (예: 이 트랙은 효과음 없음 = 키는 있고 값이 null)과 **"안 건드림(상속)"**(키 없음)을 구분한다.
///
/// 예외 — **음성(TTS mp3)**: 대본과 달리 트랙마다 따로 뽑아 비교하는 결과물이라, 파생 비트도
/// **자기 음성**을 [dialogue](voice 전용)에 직접 갖는다(오버라이드가 아니라 트랙별 소유).
///
/// 저장(JSON): 기준 비트는 개념별 중첩(dialogue/sfx/caption), 파생 비트는 `overrides`(손댄 것만)
/// + `voice` + `shots`만 적는다 — 파일만 봐도 무엇이 트랙 고유인지 읽힌다.
class DialogueBeat {
  // ── 오버라이드 키 (파생 비트의 [overrides] 맵에서 쓰는 필드 이름) ──
  static const kTitle = 'title';
  static const kNote = 'note';
  static const kDirection = 'direction';
  static const kText = 'text'; // 대사 텍스트
  static const kSpeaker = 'speaker'; // 화자(Character.id, null=내레이션)
  static const kSilent = 'silent'; // true = 이 트랙은 무음(기준이 말해도 대사 없음)
  static const kSfx = 'sfx'; // Sfx? (null=명시적 없음)
  static const kCaption = 'caption'; // Caption? (null=명시적 없음)

  String id;

  // ── 기준 비트(baseId==null)의 타입 필드 — 대본·연출의 원본. 파생 비트에서는 쓰지 않는다. ──
  String title; // 대사 제목 (비우면 '대사 n' 으로 표시)
  String note; // 사용자 메모(특이사항) — 프롬프트와 무관, 생성에 안 쓰임
  String direction; // 연출 노트 — 이 비트에서 무엇을 표현할지. 자동 생성엔 안 물림
  Dialogue? dialogue; // 이 대사의 내용(0 또는 1). null = 무음 대사
  Sfx? sfx; // 이 비트의 효과음(0 또는 1). null = 없음
  Caption? caption; // 이 비트의 자막(0 또는 1). null = 없음

  List<Shot> shots; // 이 대사를 화면으로 덮는 샷들(순서대로) — 각 샷 = FE2V 1회

  /// 파생 트랙(트랙2…)에서 이 비트가 비추고 있는 **기준 트랙 비트의 id**. null = 기준 트랙 자신.
  String? baseId;

  /// 파생 비트가 **손댄 필드만** 담는 스파스 맵(키 = [kTitle] 등). 기준 비트에서는 비어 있다.
  /// 키가 있으면 오버라이드(값이 null이어도 '명시적 없음'), 키가 없으면 기준 비트를 상속.
  Map<String, Object?> overrides;

  DialogueBeat({
    required this.id,
    this.title = '',
    this.note = '',
    this.direction = '',
    this.dialogue,
    this.sfx,
    this.caption,
    List<Shot>? shots,
    this.baseId,
    Map<String, Object?>? overrides,
  })  : shots = shots ?? [],
        overrides = overrides ?? {};

  /// 파생 트랙의 비트인지(기준 트랙이면 false).
  bool get isDerived => baseId != null;

  // ───────── 리졸버: [base] = 이 비트가 비추는 기준 비트(기준 비트면 null을 넘긴다) ─────────
  // 기준 비트는 자기 타입 필드를, 파생 비트는 overrides에 있으면 그 값·없으면 base 값을 준다.

  String resolvedTitle(DialogueBeat? base) => !isDerived
      ? title
      : (overrides.containsKey(kTitle)
          ? (overrides[kTitle] as String? ?? '')
          : (base?.title ?? ''));

  String resolvedNote(DialogueBeat? base) => !isDerived
      ? note
      : (overrides.containsKey(kNote)
          ? (overrides[kNote] as String? ?? '')
          : (base?.note ?? ''));

  String resolvedDirection(DialogueBeat? base) => !isDerived
      ? direction
      : (overrides.containsKey(kDirection)
          ? (overrides[kDirection] as String? ?? '')
          : (base?.direction ?? ''));

  /// 화면에 **보여 줄 대본**(화자·텍스트). 음성은 여기 담지 않는다([resolvedVoice] 참고).
  /// null = 무음 대사(대본 없음).
  ({String? speakerId, String text})? resolvedScript(DialogueBeat? base) {
    if (!isDerived) {
      final d = dialogue;
      return d == null ? null : (speakerId: d.speakerId, text: d.text);
    }
    // 파생: 화자·텍스트를 각각 상속/오버라이드로 해석. 둘 다 상속이고 기준도 무음이면 무음.
    final hasText = overrides.containsKey(kText);
    final hasSpeaker = overrides.containsKey(kSpeaker);
    final baseD = base?.dialogue;
    if (!hasText && !hasSpeaker && baseD == null) return null;
    final text = hasText
        ? (overrides[kText] as String? ?? '')
        : (baseD?.text ?? '');
    final speaker =
        hasSpeaker ? overrides[kSpeaker] as String? : baseD?.speakerId;
    return (speakerId: speaker, text: text);
  }

  /// 이 비트의 효과음(트랙별 오버라이드 해석). null = 없음(상속받은 것도 없거나 명시적 없음).
  Sfx? resolvedSfx(DialogueBeat? base) => !isDerived
      ? sfx
      : (overrides.containsKey(kSfx) ? overrides[kSfx] as Sfx? : base?.sfx);

  /// 이 비트의 자막(트랙별 오버라이드 해석). null = 없음.
  Caption? resolvedCaption(DialogueBeat? base) => !isDerived
      ? caption
      : (overrides.containsKey(kCaption)
          ? overrides[kCaption] as Caption?
          : base?.caption);

  /// 이 비트가 **자기 트랙에서 뽑은** 음성(TTS). 파생·기준 모두 자기 [dialogue]에 직접 갖는다.
  /// 상속하지 않는다 — 트랙마다 다른 take를 비교하려는 게 트랙을 나눈 이유다.
  Dialogue? get voice => dialogue;

  bool get hasDialogue => dialogue != null;

  /// 음성 길이(초). 실제 길이가 아니라 **샷들이 덮어야 할 목표치**다. 0 = 음성 없음.
  /// (음성은 트랙별 소유라 base 참조 없이 자기 것으로 계산된다.)
  double get targetSeconds => dialogue?.voiceSeconds ?? 0;

  /// 이 대사의 **실제 길이(초) = 샷 재생 길이 합**. **기준 비트 문맥**용(자기 샷 값으로 계산).
  /// 파생 비트의 상속 해석 길이는 `StoryboardProvider.beatSeconds`를 써야 정확하다.
  double get seconds => shots.fold(0.0, (a, s) => a + s.playSecondsWith(null));

  /// 이 대사에 **주문한** 샷 길이 합(초). 위와 같이 기준 비트 문맥용.
  double get shotSeconds =>
      shots.fold(0.0, (a, s) => a + s.resolvedVideoSeconds(null));

  /// 목표(음성) 대비 남는/모자란 시간(초). 양수 = 영상 김, 음수 = 영상 짧음. 음성 없으면 null.
  /// 파생 비트는 `StoryboardProvider.beatCoverageGap`을 쓴다.
  double? get coverageGap =>
      targetSeconds > 0 ? seconds - targetSeconds : null;

  Map<String, dynamic> toJson() {
    if (isDerived) {
      // 파생 비트: 손댄 것(overrides) + 자기 음성 + 샷만 적는다. 대본·연출은 기준에만 있다.
      return {
        'id': id,
        'base': baseId,
        'overrides': _overridesToJson(),
        'voice': {
          'file': mediaName(dialogue?.voicePath),
          'seconds': dialogue?.voiceSeconds ?? 0,
        },
        'shots': shots.map((c) => c.toJson()).toList(),
      };
    }
    return {
      'id': id,
      'title': title,
      'note': note,
      'direction': direction,
      'dialogue': dialogue?.toJson(), // null = 무음 대사
      'sfx': sfx?.toJson(), // null = 효과음 없음
      'caption': caption?.toJson(), // null = 자막 없음
      'shots': shots.map((c) => c.toJson()).toList(),
    };
  }

  /// overrides 맵을 JSON으로 — 키는 그대로, 값 객체(Sfx/Caption)는 toJson으로 직렬화.
  /// **키 존재 = 오버라이드**라, 값이 null인 키도 반드시 남긴다(명시적 없음).
  Map<String, dynamic> _overridesToJson() {
    final out = <String, dynamic>{};
    for (final e in overrides.entries) {
      final v = e.value;
      out[e.key] = switch (v) {
        Sfx s => s.toJson(),
        Caption c => c.toJson(),
        _ => v, // String / null
      };
    }
    return out;
  }

  /// [dir] = 프로젝트 폴더(미디어 파일명을 절대경로로 되살릴 기준).
  factory DialogueBeat.fromJson(Map<String, dynamic> j, String dir) {
    final baseId = j['base'] as String?;
    if (baseId != null) {
      // 파생 비트: overrides(손댄 것) + 자기 음성만 읽는다.
      final voice = (j['voice'] as Map?)?.cast<String, dynamic>();
      final vp = mediaPath(dir, voice?['file']);
      return DialogueBeat(
        id: j['id'] as String,
        baseId: baseId,
        overrides: _overridesFromJson(
            (j['overrides'] as Map?)?.cast<String, dynamic>(), dir),
        dialogue: vp == null
            ? null
            : Dialogue(
                voicePath: vp,
                voiceSeconds: (voice?['seconds'] as num?)?.toDouble() ?? 0,
              ),
        shots: ((j['shots'] as List?) ?? const [])
            .map((e) => Shot.fromJson((e as Map).cast<String, dynamic>(), dir))
            .toList(),
      );
    }
    // 기준 비트: 대본·연출 전체.
    final dlg = (j['dialogue'] as Map?)?.cast<String, dynamic>();
    final sx = (j['sfx'] as Map?)?.cast<String, dynamic>();
    final cap = (j['caption'] as Map?)?.cast<String, dynamic>();
    return DialogueBeat(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      note: (j['note'] as String?) ?? '',
      direction: (j['direction'] as String?) ?? '',
      dialogue: dlg == null ? null : Dialogue.fromJson(dlg, dir),
      sfx: sx == null ? null : Sfx.fromJson(sx, dir),
      caption: cap == null ? null : Caption.fromJson(cap),
      shots: ((j['shots'] as List?) ?? const [])
          .map((e) => Shot.fromJson((e as Map).cast<String, dynamic>(), dir))
          .toList(),
    );
  }

  /// overrides JSON을 메모리 맵으로 — Sfx/Caption 키는 값 객체로 되살린다.
  /// 키가 있으면(값이 null이어도) 그대로 담는다(오버라이드 존재 = containsKey).
  static Map<String, Object?> _overridesFromJson(
      Map<String, dynamic>? j, String dir) {
    final out = <String, Object?>{};
    if (j == null) return out;
    for (final e in j.entries) {
      switch (e.key) {
        case kSfx:
          final m = (e.value as Map?)?.cast<String, dynamic>();
          out[e.key] = m == null ? null : Sfx.fromJson(m, dir);
        case kCaption:
          final m = (e.value as Map?)?.cast<String, dynamic>();
          out[e.key] = m == null ? null : Caption.fromJson(m);
        default:
          out[e.key] = e.value; // String / null
      }
    }
    return out;
  }
}
