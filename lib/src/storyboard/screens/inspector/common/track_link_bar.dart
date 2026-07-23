part of '../inspector_panel.dart';

/// 파생 트랙에서 이 샷이 **기준 트랙을 따라가는 중**인지 알려주는 띠 + 분리/되돌리기 버튼.
/// 기준 트랙이거나 트랙이 하나뿐이면 아무것도 그리지 않는다.
class _TrackLinkBar extends StatelessWidget {
  const _TrackLinkBar({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    if (!shot.isDerived) return const SizedBox.shrink();
    final base = p.tracks.isEmpty ? null : p.tracks.first;
    final baseName = base == null ? '트랙 1' : p.trackLabel(base);
    final linked = shot.inherits;
    final color = linked ? accent : const Color(0xFFE0A94A);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(linked ? Icons.link : Icons.edit_outlined,
                size: 15, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                linked
                    ? '$baseName의 내용을 그대로 씁니다 — 영상만 이 트랙 것입니다'
                    : '이 트랙에서 수정한 샷입니다 — $baseName과 따로 갑니다',
                style: const TextStyle(fontSize: 11.5, height: 1.35),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () =>
                  linked ? p.detachShot(shot) : _confirmRelink(context, p),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: color,
              ),
              child: Text(linked ? '이 트랙에서 수정' : '$baseName로 되돌리기',
                  style: const TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRelink(
      BuildContext context, StoryboardProvider p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('트랙 1로 되돌리기'),
        content: const Text('이 샷의 내용을 트랙 1의 것으로 되돌립니다.\n'
            '이 트랙에서 고친 프롬프트·프레임은 더 이상 쓰이지 않습니다.\n'
            '(이 트랙에서 뽑은 영상은 그대로 남습니다)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('되돌리기')),
        ],
      ),
    );
    if (ok == true) await p.relinkShot(shot);
  }
}

