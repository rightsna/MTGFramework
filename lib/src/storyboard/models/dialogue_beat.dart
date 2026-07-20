import 'shot.dart';
import 'dialogue.dart';

/// 대사(DialogueBeat) = 씬 타임라인의 한 단위. **대사 내용 1개(선택) + 샷 여러 개**를 담는다.
/// 계층: 씬 > **대사** > 샷.
///
/// 드라마 제작의 기준은 대본이다 — 한 대사(한 마디)를 화면으로 덮는 샷이 여러 개 붙는다
/// (1대사 = 2~3샷). 첫 샷은 입 모양을 맞추고(립싱크), 나머지는 컷어웨이(대사는 계속 흐름).
/// 대사 내용이 없으면([dialogue]=null) 무음 대사(establishing·지문).
///
/// **길이**: 실제 길이는 [seconds](=샷 길이 합)다 — 재생되는 건 영상이고 음성은 그 위에
/// 얹히는 트랙이다. 음성 길이는 [targetSeconds](샷들이 덮어야 할 목표)이고, 둘의 차이가
/// [coverageGap]. 목표에 맞춰 샷을 채우는 것이 작업 흐름.
///
/// [dialogue]가 값 객체로 분리된 이유: 언어별 더빙 때 **샷은 그대로 두고 이것만 교체**한다.
///
/// 저장(JSON)은 개념별로 중첩한다 — dialogue / shots — 파일만 봐도 구성이 읽힌다.
class DialogueBeat {
  String id;
  String title; // 대사 제목 (비우면 '대사 n' 으로 표시)
  String note; // 사용자 메모(특이사항) — 프롬프트와 무관, 생성에 안 쓰임
  String direction; // 연출 노트 — 이 비트에서 무엇을 표현할지(대사는 그중 하나). 자동 생성엔 안 물림
  Dialogue? dialogue; // 이 대사의 내용(0 또는 1). null = 무음 대사
  List<Shot> shots; // 이 대사를 화면으로 덮는 샷들(순서대로) — 각 샷 = FE2V 1회

  /// 파생 트랙(트랙2…)에서 이 비트가 비추고 있는 **기준 트랙 비트의 id**. null = 기준 트랙 자신.
  /// 비트 내용(대본·연출·음성)은 트랙이 갈라도 같은 것이라 **항상 기준을 따라간다** —
  /// 트랙마다 달라지는 건 샷의 영상뿐이다([Shot.detached]).
  String? baseId;

  DialogueBeat({
    required this.id,
    this.title = '',
    this.note = '',
    this.direction = '',
    this.dialogue,
    List<Shot>? shots,
    this.baseId,
  }) : shots = shots ?? [];

  bool get hasDialogue => dialogue != null;

  /// 파생 트랙의 비트인지(기준 트랙이면 false).
  bool get isDerived => baseId != null;

  /// 기준 비트 [base]의 내용을 따라간다(샷 목록은 트랙별로 따로 관리하므로 건드리지 않는다).
  /// 대사는 같은 객체를 공유한다 — 대본도 음성도 트랙 사이에서 하나여야 한다.
  void adoptContentFrom(DialogueBeat base) {
    title = base.title;
    note = base.note;
    direction = base.direction;
    dialogue = base.dialogue;
  }

  /// 이 대사에 **주문한** 샷 길이 합(초).
  int get shotSeconds => shots.fold(0, (a, c) => a + c.videoSeconds);

  /// 이 대사의 **실제 길이(초) = 샷 길이 합**. 재생되는 건 영상이고, 음성은 그 위에 얹히는
  /// 트랙일 뿐이라 영상 합계가 진짜 길이다. 뽑힌 샷은 주문값이 아니라 **실제 길이**로 센다
  /// (백엔드마다 지원 길이가 달라 주문대로 안 나오는 일이 흔하다).
  double get seconds => shots.fold(0.0, (a, c) => a + c.playSeconds);

  /// 음성 길이(초). 실제 길이가 아니라 **샷들이 덮어야 할 목표치**다. 0 = 음성 없음.
  double get targetSeconds => dialogue?.voiceSeconds ?? 0;

  /// 목표(음성) 대비 남는/모자란 시간(초). 양수 = 영상이 김(음성 뒤 여백),
  /// 음수 = 영상이 짧음(대사가 잘림). 음성이 없으면 null.
  double? get coverageGap =>
      targetSeconds > 0 ? seconds - targetSeconds : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (baseId != null) 'base': baseId,
        // 파생 트랙의 비트는 내용을 안 적는다 — 기준 비트 한 곳에만 둔다(샷은 트랙별로 다르다).
        if (baseId == null) ...{
          'title': title,
          'note': note,
          'direction': direction,
          'dialogue': dialogue?.toJson(), // null = 무음 대사
        },
        'shots': shots.map((c) => c.toJson()).toList(),
      };

  /// [dir] = 프로젝트 폴더(미디어 파일명을 절대경로로 되살릴 기준).
  factory DialogueBeat.fromJson(Map<String, dynamic> j, String dir) {
    final dlg = (j['dialogue'] as Map?)?.cast<String, dynamic>();
    return DialogueBeat(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      note: (j['note'] as String?) ?? '',
      direction: (j['direction'] as String?) ?? '',
      dialogue: dlg == null ? null : Dialogue.fromJson(dlg, dir),
      shots: ((j['shots'] as List?) ?? const [])
          .map((e) => Shot.fromJson((e as Map).cast<String, dynamic>(), dir))
          .toList(),
      baseId: j['base'] as String?,
    );
  }
}
