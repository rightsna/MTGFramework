part of '../inspector_panel.dart';

/// 배경음 탭 — 선택 씬의 BGM(스타일·길이·생성/불러오기·재생). 씬 탭에서 분리했다.
class _BgmTab extends StatelessWidget {
  const _BgmTab();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    if (p.selectedScene == null) {
      return const Center(
        child: Text('씬을 선택하세요', style: TextStyle(color: Colors.white38)),
      );
    }
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: BgmSection(),
    );
  }
}
