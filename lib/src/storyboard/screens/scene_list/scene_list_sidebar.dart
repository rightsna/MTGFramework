import 'package:flutter/material.dart';

import '../../providers/storyboard_provider.dart';
import '../ui.dart';

/// 좌측 씬 목록 사이드: 씬(대사 그룹) 추가/선택/삭제/제목 편집.
class SceneListSidebar extends StatelessWidget {
  const SceneListSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final scenes = p.scenes;
    return Container(
      color: panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더 + 접기
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.movie_creation_outlined, size: 18, color: accent2),
                const SizedBox(width: 8),
                const Text('씬 목록',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const Spacer(),
                IconButton(
                  tooltip: '접기',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: p.toggleSceneList,
                ),
              ],
            ),
          ),
          // 씬 리스트
          Expanded(
            child: scenes.isEmpty
                ? const Center(
                    child: Text('씬을 추가하세요',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: scenes.length,
                    itemBuilder: (context, i) {
                      final scene = scenes[i];
                      final sel = scene.id == p.selectedSceneId;
                      final title = scene.title.trim().isEmpty
                          ? '(제목 없음)'
                          : scene.title.trim();
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        color: sel ? const Color(0x222B7BFF) : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: sel ? accent : const Color(0x14FFFFFF),
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          onTap: () => p.selectScene(scene.id),
                          title: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      sel ? FontWeight.w800 : FontWeight.w600)),
                          subtitle: Text(
                              '${scene.beats.length} 비트 · ${scene.shotCount} 샷',
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0x99FFFFFF))),
                          // 삭제는 우측 '씬' 탭 최하단으로 옮겼다 — 목록에서 실수로 누르기 쉬웠다.
                        ),
                      );
                    },
                  ),
          ),
          // (씬 제목 편집은 우측 '씬' 탭으로 옮겼다.)
          // 선택 씬 조작 — 복제 | 위로 | 아래로 | 씬 무비 내보내기. 아이콘만.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: _SceneOpButton(
                    // 선택된 씬을 그대로 최하단에 복제.
                    icon: Icons.copy_all_outlined,
                    tooltip: '선택 씬 복제',
                    onPressed: p.selectedScene == null
                        ? null
                        : () => p.duplicateScene(),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SceneOpButton(
                    icon: Icons.keyboard_arrow_up,
                    tooltip: '위로',
                    onPressed: p.canMoveSceneUp ? () => p.moveScene(-1) : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SceneOpButton(
                    icon: Icons.keyboard_arrow_down,
                    tooltip: '아래로',
                    onPressed: p.canMoveSceneDown ? () => p.moveScene(1) : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SceneOpButton(
                    // 씬의 클립을 샷 순서대로 하나의 mp4로 합쳐 저장한다.
                    icon: Icons.movie_outlined,
                    tooltip: '씬 무비 내보내기',
                    onPressed: p.selectedScene == null
                        ? null
                        : () => p.exportSceneMovie(),
                  ),
                ),
              ],
            ),
          ),
          // 씬 추가
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: FilledButton.icon(
              onPressed: p.addScene,
              icon: const Icon(Icons.add),
              label: const Text('씬 추가'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 씬 목록 하단의 아이콘 전용 조작 버튼(복제·위·아래) — 생김새를 한 군데로 모은다.
class _SceneOpButton extends StatelessWidget {
  const _SceneOpButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
        ),
        child: Tooltip(message: tooltip, child: Icon(icon, size: 18)),
      );
}
