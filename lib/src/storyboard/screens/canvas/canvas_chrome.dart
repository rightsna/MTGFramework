part of 'canvas_view.dart';

/// 캔버스 자체를 꾸미는 정적 위젯 — 카드 사이 화살표, 도트 그리드 배경, 메모 패널.

/// 샷 사이 흐름 화살표 — 카드 상단 근처(헤더/대사 높이)에 맞춰 배치.
class _ShotArrow extends StatelessWidget {
  const _ShotArrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 40, left: 4, right: 4),
      child: Icon(Icons.arrow_right_alt, color: accent, size: 30),
    );
  }
}

/// 캔버스 도트 그리드 배경.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const _step = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0x0AFFFFFF);
    for (var x = 0.0; x < size.width; x += _step) {
      for (var y = 0.0; y < size.height; y += _step) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

/// 캔버스 우상단 메모 패널 — 이 씬의 씬·비트·샷 메모를 **있는 것만** 한 줄씩 모아 보여준다.
/// 컨트롤러를 직접 읽으므로 인스펙터에서 타이핑하는 즉시([noteEdited]) 따라온다.
class _MemoOverlay extends StatelessWidget {
  const _MemoOverlay();

  static const _amber = Color(0xFFE0A94A);

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    if (sc == null) return const SizedBox.shrink();

    final entries = <(String, String)>[];
    final sceneNote = p.sceneNoteCtrl(sc.id).text.trim();
    if (sceneNote.isNotEmpty) entries.add(('씬', sceneNote));
    for (var i = 0; i < sc.dialogues.length; i++) {
      final beat = sc.dialogues[i];
      final bn = p.noteCtrl(beat.id).text.trim();
      if (bn.isNotEmpty) entries.add(('비트${i + 1}', bn));
      for (var j = 0; j < beat.shots.length; j++) {
        final shot = beat.shots[j];
        final sn = p.shotNoteCtrl(shot.id).text.trim();
        if (sn.isEmpty) continue;
        final t = shot.title.trim();
        entries.add((t.isEmpty ? '비트${i + 1}·샷${j + 1}' : t, sn));
      }
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 280,
      constraints: const BoxConstraints(maxHeight: 280),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xEE22201A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33E0A94A)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined, size: 14, color: _amber),
              const SizedBox(width: 6),
              Text(
                '메모 ${entries.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: _amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (label, text) in entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$label · ',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _amber,
                              ),
                            ),
                            TextSpan(
                              text: text.replaceAll('\n', ' '),
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.35,
                                color: Color(0xCCFFFFFF),
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
