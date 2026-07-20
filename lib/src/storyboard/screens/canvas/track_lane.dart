part of 'canvas_view.dart';

/// 트랙 한 줄 = **씬 한 벌**. 머리말(이름·백엔드·진행도·설정·삭제) 아래로 그 트랙의 비트 카드가
/// 가로로 이어진다. 트랙끼리 구조가 같으므로 줄들은 같은 칸에 같은 비트가 놓인다 —
/// 위아래로 견주어 보는 게 트랙의 전부다.
///
/// 트랙을 고르는 자리는 따로 없다: 카드나 샷을 누르면 그 줄이 곧 선택 트랙이 된다.
class _TrackLane extends StatelessWidget {
  const _TrackLane({required this.track, required this.trackIndex});

  final VideoTrack track;
  final int trackIndex;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final beats = track.beats;
    final isBase = trackIndex == 0;
    final active = p.trackIndex == trackIndex;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: active ? const Color(0x0AFFFFFF) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? const Color(0x448B7BFF) : const Color(0x14FFFFFF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TrackHeader(track: track, trackIndex: trackIndex),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < beats.length; i++) ...[
                SizedBox(width: 286, child: _ShotCard(beat: beats[i], index: i)),
                if (i < beats.length - 1) const _ShotArrow(),
              ],
              // 비트 추가는 기준 트랙 줄에서만 — 구조는 트랙끼리 같아야 한다.
              if (isBase) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 34),
                  child: SizedBox(
                    width: 56,
                    child: OutlinedButton(
                      onPressed: p.addDialogue,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        side: const BorderSide(color: Color(0x33FFFFFF)),
                      ),
                      child: const Icon(Icons.add),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 트랙 줄 머리말 — [★] 이름 · 백엔드 · 뽑힌 수/전체 + ⋯(이름·백엔드) + 삭제(파생 트랙만).
/// ★는 기준 트랙(구조의 정본, 비트·샷을 더하고 지우는 줄).
class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.track, required this.trackIndex});

  final VideoTrack track;
  final int trackIndex;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final isBase = trackIndex == 0;
    final active = p.trackIndex == trackIndex;
    final color = active ? accent2 : const Color(0x99FFFFFF);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isBase) ...[
          Icon(Icons.star_rounded, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Text(p.trackLabel(track),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: color,
            )),
        const SizedBox(width: 8),
        // 이 줄의 **기본** 백엔드 — 일괄 생성이 쓰는 값이고, 샷마다 다른 걸로 뽑아도 된다.
        // (그래서 결과가 무엇으로 나왔는지는 영상 탭의 결과 옆에 따로 적힌다.)
        Tooltip(
          message: '이 트랙의 기본 백엔드 (일괄 생성에 쓰임)\n샷마다 다른 백엔드로도 뽑을 수 있습니다',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(track.backend.shortLabel,
                style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
          ),
        ),
        const SizedBox(width: 8),
        Text('영상 ${track.filledCount}/${track.shotCount}',
            style: const TextStyle(fontSize: 10.5, color: Colors.white38)),
        const SizedBox(width: 2),
        _TrackMenu(track: track),
        // 트랙 삭제는 눈에 보이는 자리에 둔다(비트 삭제와 같은 모양) — 메뉴 안에 숨기면 못 찾는다.
        // 기준 트랙은 구조의 정본이라 지울 수 없어 버튼도 없다.
        if (!isBase)
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: '트랙 삭제',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirmDelete(
                context,
                title: '트랙 삭제',
                body: '"${p.trackLabel(track)}" 트랙을 지웁니다.\n'
                    '이 트랙에서 뽑은 영상 ${track.filledCount}개의 연결이 끊깁니다.',
              )) {
                await p.removeTrack(track);
              }
            },
          ),
        if (!isBase)
          const Text('· 트랙 1을 그대로 따라갑니다 (영상만 따로)',
              style: TextStyle(fontSize: 10.5, color: Color(0x55FFFFFF))),
      ],
    );
  }
}
