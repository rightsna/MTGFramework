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
                          ? 'SCENE ${i + 1}'
                          : 'SCENE ${i + 1} · ${scene.title.trim()}';
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
                              '${scene.dialogues.length} 대사 · ${scene.shotCount} 샷',
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0x99FFFFFF))),
                          // 삭제는 우측 '씬' 탭 최하단으로 옮겼다 — 목록에서 실수로 누르기 쉬웠다.
                        ),
                      );
                    },
                  ),
          ),
          // (씬 제목 편집은 우측 '씬' 탭으로 옮겼다.)
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
