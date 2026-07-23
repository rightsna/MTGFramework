part of '../inspector_panel.dart';

/// 샷 길이 합(실제) vs 음성 길이(목표) 비교 — 부족하면 채우라고, 맞으면 초록으로.
/// 실제 재생되는 건 영상이므로 대사 길이 = 샷 합계이고, 음성은 그 위에 얹히는 목표치다.
class _CoverageBadge extends StatelessWidget {
  const _CoverageBadge({required this.beat});

  final DialogueBeat beat;

  @override
  Widget build(BuildContext context) {
    final gap = beat.coverageGap;
    if (gap == null) return const SizedBox.shrink();
    final short = gap < -0.05; // 영상이 음성보다 짧다 = 대사가 잘림
    final over = gap > 0.05; // 영상이 더 길다 = 음성 뒤 여백
    final c = short
        ? Colors.orangeAccent
        : over
        ? Colors.white54
        : Colors.greenAccent;
    final msg = short
        ? '샷 ${fmtSeconds(beat.seconds)} · 음성보다 ${fmtSeconds(-gap)} 짧음 — 대사가 잘립니다'
        : over
        ? '샷 ${fmtSeconds(beat.seconds)} · 음성 뒤 ${fmtSeconds(gap)} 여백'
        : '샷 ${fmtSeconds(beat.seconds)} · 음성과 맞음';
    return Row(
      children: [
        Icon(
          short
              ? Icons.warning_amber_rounded
              : over
              ? Icons.more_horiz
              : Icons.check_circle_outline,
          size: 13,
          color: c,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(msg, style: TextStyle(fontSize: 11, color: c)),
        ),
      ],
    );
  }
}
