part of 'canvas_view.dart';

/// 캔버스의 비트 카드 — 카드 몸통과 그 안(대사 상자·트랙별 샷 줄·샷 썸네일·샷 추가·노트).

/// 대사 카드: [헤더] + [대사] + [트랙별 샷 줄] + [메모].
/// [beat]은 **기준 트랙**의 비트다(구조·대사의 정본). 트랙별 샷은 같은 자리의 비트에서 가져온다.
class _ShotCard extends StatelessWidget {
  const _ShotCard({required this.beat, required this.index});

  final DialogueBeat beat;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final selected = beat.id == p.selectedDialogueId;
    final card = Card(
      elevation: selected ? 8 : 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? accent : const Color(0x14FFFFFF),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2A2550), Color(0xFF1C2030)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
            ),
            padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('비트 ${index + 1}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 1.0,
                              color: Color(0xAAFFFFFF))),
                      if (beat.title.trim().isNotEmpty)
                        Text(beat.title.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
                // 비트 삭제는 **기준 트랙 줄에서만** — 구조를 건드리는 일이라 정본 줄에 둔다
                // (지우면 모든 트랙에서 같이 사라진다).
                if (!beat.isDerived)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () async {
                    if (await confirmDelete(
                      context,
                      title: '비트 삭제',
                      body:
                          '"${beat.title.trim().isEmpty ? '(제목 없음)' : beat.title.trim()}" 비트를 삭제합니다.\n'
                          '샷 ${beat.shots.length}개가 모든 트랙에서 함께 사라집니다. 되돌릴 수 없습니다.',
                    )) {
                      p.removeDialogue(beat);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '비트 삭제',
                ),
              ],
            ),
          ),
          // 대사(0/1)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: _DialogueBox(beat: beat),
          ),
          // 샷들 — 3열 정사각 그리드. 높이는 샷 수(행)에 맞춰 자란다.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            child: _ShotsArea(beat: beat),
          ),
        ],
      ),
    );
    // 메모는 샷 박스 안이 아니라 카드 아래에 독립 라운드박스로 붙인다 —
    // 비트 메모 다음 그 비트의 샷 메모들이 순서대로 이어진다.
    // 모델이 아니라 컨트롤러에서 읽는다: 인스펙터에서 타이핑하는 즉시 따라오게.
    // 탭하면 인스펙터의 그 메모 자리로 간다(탭 번호: 0=비트 1=장면 2=영상).
    final notes = <Widget>[];
    // 메모는 **기준 트랙 줄에만** 붙인다 — 트랙끼리 같은 내용이라
    // 줄마다 반복해 봐야 캔버스만 길어진다.
    if (!beat.isDerived) {
      final beatNote = p.noteCtrl(beat.id).text.trim();
      if (beatNote.isNotEmpty) {
        notes.add(_NoteBox(
          text: beatNote,
          onTap: () {
            p.selectDialogue(beat.id);
            p.openInspectorTab(0);
          },
        ));
      }
      for (var i = 0; i < beat.shots.length; i++) {
        final shot = beat.shots[i];
        final t = shot.title.trim().isEmpty ? '샷 ${i + 1}' : shot.title.trim();
        // 장면 메모와 영상 메모는 별개다 — 있는 것만 각각 한 줄씩.
        final sn = p.shotNoteCtrl(shot.id).text.trim();
        if (sn.isNotEmpty) {
          notes.add(_NoteBox(
            label: '$t · 장면',
            text: sn,
            onTap: () {
              p.selectShot(beat.id, shot.id);
              p.openInspectorTab(1);
            },
          ));
        }
        final vn = p.videoNoteCtrl(shot.id).text.trim();
        if (vn.isNotEmpty) {
          notes.add(_NoteBox(
            label: '$t · 영상',
            text: vn,
            onTap: () {
              p.selectShot(beat.id, shot.id);
              p.openInspectorTab(2);
            },
          ));
        }
      }
    }
    final Widget content = notes.isEmpty
        ? card
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              card,
              for (final n in notes) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: n,
                ),
              ],
            ],
          );
    // 몸통(배경) 탭 → 이 대사 선택. 앞쪽의 샷·상태 스트립·대사·삭제·＋ 버튼은
    // 각자 제스처를 먼저 가져가고(자식 우선), 그 외 빈 배경 탭만 여기로 떨어진다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => p.selectDialogue(beat.id),
      child: content,
    );
  }
}

/// 대사 박스 — 화자 + 텍스트 + 음성 상태. 탭 → 이 비트를 선택(편집은 우측 '비트' 탭).
class _DialogueBox extends StatelessWidget {
  const _DialogueBox({required this.beat});

  final DialogueBeat beat;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final d = beat.dialogue;
    if (d == null) {
      return InkWell(
        onTap: () => p.selectDialogue(beat.id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x22E0678A)),
          ),
          child: const Row(
            children: [
              Icon(Icons.add, size: 14, color: _voiceColor),
              SizedBox(width: 6),
              Text('대사 입력',
                  style: TextStyle(fontSize: 12, color: _voiceColor)),
            ],
          ),
        ),
      );
    }
    final speaker = p.characterById(d.speakerId);
    final isNarration = d.speakerId == null;
    final busy = p.isBusy(p.voiceBusyKey(beat.id));
    return InkWell(
      onTap: () => p.selectDialogue(beat.id),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: const Color(0x14E0678A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x33E0678A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isNarration ? Icons.menu_book_outlined : Icons.person,
                    size: 12,
                    color: isNarration ? Colors.white38 : _voiceColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isNarration
                        ? '내레이션'
                        : ((speaker?.name.trim().isNotEmpty ?? false)
                            ? speaker!.name.trim()
                            : '(이름 없음)'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isNarration ? Colors.white54 : Colors.white),
                  ),
                ),
                if (busy)
                  const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else if (d.hasVoice)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    VoicePlayButton(
                      key: ValueKey('${d.voicePath}:${d.voiceSeconds}'),
                      path: d.voicePath!,
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    Text(fmtSeconds(d.voiceSeconds),
                        style: const TextStyle(fontSize: 10, color: accent2)),
                  ])
                else
                  const Icon(Icons.mic_none_outlined,
                      size: 12, color: Colors.white24),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              d.text.trim().isEmpty ? '(대사 없음)' : d.text.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: d.text.trim().isEmpty
                      ? Colors.white30
                      : const Color(0xDDFFFFFF)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 대사의 샷들 — **3열 정사각 그리드** + 추가 타일. 탭하면 그 샷 선택(인스펙터가 편집).
/// shrinkWrap이라 그리드 높이가 행 수(샷 수)에 맞춰 자라고 → 대사 카드 높이도 따라 fit 된다.
class _ShotsArea extends StatelessWidget {
  const _ShotsArea({required this.beat});

  final DialogueBeat beat;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('샷',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: accent2)),
            const SizedBox(width: 5),
            Text('${beat.shots.length}',
                style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1, // 정사각
          children: [
            for (var i = 0; i < beat.shots.length; i++)
              _ShotThumb(
                key: ValueKey('shot_${beat.shots[i].id}'),
                beat: beat,
                shot: beat.shots[i],
                index: i,
              ),
            // 샷 추가는 기준 트랙에서만 — 구조는 트랙끼리 같아야 한다.
            if (!beat.isDerived)
              _AddShotTile(key: const ValueKey('addShot'), beat: beat),
          ],
        ),
      ],
    );
  }
}

/// 정사각 샷 썸네일 — 시작이미지 + 오버레이(번호·삭제·하단 영상상태/길이). 그리드 셀을 꽉 채운다.
class _ShotThumb extends StatelessWidget {
  const _ShotThumb(
      {super.key, required this.beat, required this.shot, required this.index});

  final DialogueBeat beat;
  final Shot shot;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final selected = shot.id == p.selectedShotId && beat.id == p.selectedDialogueId;
    final hasVideo = shot.videoPath != null;
    // 이 샷에서 뭐든 생성 중인지(시작·끝 프레임 · 영상) — 썸네일 테두리를 깜빡여 알린다.
    final busy = p.isBusy(p.busyKey(shot.id, GenMode.imageStart)) ||
        p.isBusy(p.busyKey(shot.id, GenMode.imageEnd)) ||
        p.isBusy(p.busyKey(shot.id, GenMode.videoLow));
    return GestureDetector(
      onTap: () => p.selectShot(beat.id, shot.id),
      child: Container(
        decoration: BoxDecoration(
          color: previewBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? accent : const Color(0x18FFFFFF),
              width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            OutputPreview(
              path: p.startPathOf(shot),
              version: p.verOf(p.busyKey(shot.id, GenMode.imageStart)),
              busy: p.isBusy(p.busyKey(shot.id, GenMode.imageStart)),
            ),
            // 생성 중이면 테두리를 깜빡이고 작은 스피너를 얹는다.
            if (busy) const Positioned.fill(child: _BusyPulse()),
            Positioned(
              left: 3,
              top: 3,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${index + 1}',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ),
            // 분리한 샷 표시 — 이 트랙만의 내용이라는 뜻(따라가는 샷은 표시가 없다 = 트랙 1 그대로).
            if (shot.detached)
              Positioned(
                left: 3,
                bottom: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.edit_outlined,
                      size: 9, color: Color(0xFFE0A94A)),
                ),
              ),
            // 샷 삭제도 기준 트랙에서만 — 지우면 모든 트랙에서 같이 사라지는 구조 변경이다.
            if (!shot.isDerived)
              Positioned(
                right: 1,
                top: 1,
                child: GestureDetector(
                  onTap: () async {
                    if (await confirmDelete(
                      context,
                      title: '샷 삭제',
                      body:
                          '"${shot.title.trim().isEmpty ? '샷 ${index + 1}' : shot.title.trim()}" 을 삭제합니다.\n'
                          '모든 트랙에서 같이 사라집니다. 되돌릴 수 없습니다.',
                    )) {
                      p.removeShot(beat, shot);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Color(0xAA000000), shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        size: 11, color: Colors.white70),
                  ),
                ),
              ),
            // 하단 상태 스트립: 영상 생성 여부 + 길이.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                color: const Color(0x99000000),
                child: Row(
                  children: [
                    Icon(hasVideo ? Icons.check_circle : Icons.movie_outlined,
                        size: 9, color: hasVideo ? accent2 : Colors.white38),
                    const SizedBox(width: 3),
                    // 뽑힌 게 있으면 그 실제 길이, 없으면 주문한 길이([Shot.playSeconds]).
                    Text(fmtSeconds(shot.playSeconds),
                        style: const TextStyle(
                            fontSize: 9, color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 샷 추가 타일 — 그리드 셀 가운데의 원형 + 버튼.
class _AddShotTile extends StatelessWidget {
  const _AddShotTile({super.key, required this.beat});

  final DialogueBeat beat;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Center(
      child: InkWell(
        onTap: () => p.addShot(beat),
        customBorder: const CircleBorder(),
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0x14FFFFFF),
            border: Border.fromBorderSide(BorderSide(color: Color(0x2AFFFFFF))),
          ),
          child: const Icon(Icons.add, size: 14, color: Colors.white54),
        ),
      ),
    );
  }
}

/// 샷 메모(특이사항) — 앰버 톤 라운드 박스.
class _NoteBox extends StatelessWidget {
  const _NoteBox({required this.text, this.label, this.onTap});

  final String text;

  /// 샷 메모면 어느 샷인지(비트 메모는 null — 카드가 곧 그 비트다).
  final String? label;

  /// 탭하면 인스펙터의 그 자리로 데려간다. 카드 배경 탭보다 자식이 먼저 가져간다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0x14E0A94A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33E0A94A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.sticky_note_2_outlined,
                size: 13, color: Color(0xFFE0A94A)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (label != null)
                  TextSpan(
                    text: '$label · ',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE0A94A)),
                  ),
                TextSpan(text: text),
              ]),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, height: 1.35, color: Color(0xCCFFFFFF)),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return box;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: box),
    );
  }
}

/// 생성 중 표시 — 썸네일 테두리를 은은하게 깜빡이고 가운데에 작은 스피너를 얹는다.
/// busy일 때만 스택에 올라가므로, 도는 샷만 컨트롤러를 만든다.
class _BusyPulse extends StatefulWidget {
  const _BusyPulse();

  @override
  State<_BusyPulse> createState() => _BusyPulseState();
}

class _BusyPulseState extends State<_BusyPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = 0.30 + 0.60 * _c.value; // 테두리 밝기 0.3~0.9로 왕복
          return Container(
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent2.withValues(alpha: t), width: 2),
            ),
            child: child,
          );
        },
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: accent2),
          ),
        ),
      ),
    );
  }
}
