part of '../inspector_panel.dart';

/// 장면·영상 탭에 편집할 샷이 없을 때의 안내.
///  - 샷 미선택 → 샷을 먼저 선택
///  - 대사는 있으나 샷 0개 → 샷 추가(＋)
///  - 샷은 있으나 선택 안 됨 → 캔버스에서 샷을 클릭하도록 안내
class _NoShot extends StatelessWidget {
  const _NoShot();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final beat = p.selectedDialogue;
    if (beat == null) {
      return const _CenterNote(
        icon: Icons.touch_app_outlined,
        title: '비트를 선택하세요',
      );
    }
    if (beat.shots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_filter_outlined,
              color: Colors.white24,
              size: 40,
            ),
            const SizedBox(height: 10),
            const Text(
              '이 비트에 샷이 없습니다',
              style: TextStyle(color: Colors.white38),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => p.addShot(beat),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('비트 추가'),
            ),
          ],
        ),
      );
    }
    return const _CenterNote(
      icon: Icons.ads_click,
      title: '샷을 선택하세요',
      subtitle: '캔버스에서 편집할 샷을 클릭하면\n그 샷의 장면·영상을 편집할 수 있어요',
    );
  }
}

