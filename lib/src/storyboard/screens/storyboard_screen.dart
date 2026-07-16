import 'package:flutter/material.dart';

import '../providers/storyboard_provider.dart';
import '../services/api_service.dart';
import 'canvas/canvas_view.dart';
import 'characters/character_manager_screen.dart';
import 'inspector/inspector_panel.dart';
import 'preview/preview_player.dart';
import 'scene_list/scene_list_sidebar.dart';
import 'settings/settings_dialog.dart';
import 'ui.dart';

/// 한 프로젝트의 영상 제작 화면. 헤더 아래로 [씬 목록 | 플레이어 | 캔버스 | 인스펙터].
/// 모든 상태/로직은 [StoryboardProvider]가 들고, 각 패널은 StoryboardScope로 구독한다.
class StoryboardScreen extends StatefulWidget {
  const StoryboardScreen({
    super.key,
    required this.projectDirPath,
    required this.projectName,
  });

  final String projectDirPath;
  final String projectName;

  @override
  State<StoryboardScreen> createState() => _StoryboardScreenState();
}

class _StoryboardScreenState extends State<StoryboardScreen> {
  late final StoryboardProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = StoryboardProvider(projectDirPath: widget.projectDirPath)
      ..messenger = (msg) {
        if (!mounted) return;
        // fixed 동작으로 — floating은 창이 짧을 때 화면 밖으로 잡혀 assert가 터진다.
        // 직전 스낵바는 숨겨 생성 중 메시지가 쌓이지 않게.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.fixed,
          ));
      };
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoryboardScope(
      notifier: _provider,
      child: AnimatedBuilder(
        animation: _provider,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            // 깔끔한 뒤로가기 — 프로젝트 목록으로.
            leadingWidth: 132,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                label: const Text('프로젝트'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
            // 제목 옆에 (미리보기) 토글 버튼.
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.projectName),
                const SizedBox(width: 16),
                FilledButton.tonalIcon(
                  onPressed: _provider.toggleSceneList,
                  icon: Icon(_provider.sceneListOpen
                      ? Icons.video_library
                      : Icons.video_library_outlined),
                  label: const Text('씬 목록'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _provider.sceneListOpen ? accent : null,
                    foregroundColor: _provider.sceneListOpen ? Colors.white : null,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _provider.togglePlayer,
                  icon: Icon(_provider.playerOpen
                      ? Icons.slideshow
                      : Icons.play_circle_outline),
                  label: const Text('미리보기'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _provider.playerOpen ? accent : null,
                    foregroundColor: _provider.playerOpen ? Colors.white : null,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CharacterManagerScreen(
                          projectDirPath: widget.projectDirPath,
                          projectName: widget.projectName,
                        ),
                      ),
                    );
                    _provider.reloadCharacters(); // 인물 편집 후 참조 피커에 반영
                  },
                  icon: const Icon(Icons.people_alt_outlined),
                  label: const Text('인물 관리'),
                ),
              ],
            ),
            actions: [
              const _ConnStatus(),
              IconButton(
                tooltip: '프로젝트 폴더 열기 (생성된 영상·이미지·음성이 저장되는 곳)',
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: _provider.openProjectFolder,
              ),
              IconButton(
                tooltip: '설정 · 서버 연결',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () async {
                  await showSettingsDialog(context);
                  await _provider.reloadSettings(); // URL 변경 즉시 반영 + 재확인
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 씬 목록 | 플레이어 | 캔버스 | 인스펙터
              if (_provider.sceneListOpen) ...[
                const SizedBox(width: sceneListW, child: SceneListSidebar()),
                Container(width: 1, color: const Color(0x22FFFFFF)),
              ],
              if (_provider.playerOpen) ...[
                const SizedBox(width: playerW, child: PreviewPlayer()),
                Container(width: 1, color: const Color(0x22FFFFFF)),
              ],
              // 가운데: 캔버스(샷 타임라인, 위) + 인스펙터(아래, 일반·샷·배경음).
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: CanvasView()),
                    SizedBox(height: 340, child: InspectorPanel()),
                  ],
                ),
              ),
              Container(width: 1, color: const Color(0x22FFFFFF)),
              // 오른쪽: 클립 편집(장면·영상·공통) — 세로로 긴 편집이라 우측 패널이 적합.
              const SizedBox(width: inspectorW, child: ClipEditorPanel()),
            ],
          ),
        ),
      ),
    );
  }
}

/// 헤더의 service-api 접속 상태 칩(초록=연결, 빨강=끊김). 탭하면 설정 열림.
class _ConnStatus extends StatelessWidget {
  const _ConnStatus();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final ApiStatus s = p.apiStatus;
    final Color dot = s.reachable ? Colors.green : Colors.redAccent;
    final String label = s.reachable ? '서버 연결됨' : '서버 연결 안 됨';
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        await showSettingsDialog(context);
        if (context.mounted) await StoryboardScope.read(context).reloadSettings();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
            if (s.reachable && !s.videoReady) ...[
              const SizedBox(width: 6),
              const Text('· 영상 워크플로 미설치',
                  style: TextStyle(fontSize: 11, color: Colors.orangeAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
