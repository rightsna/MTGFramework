import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard

import '../../models/shot.dart';
import '../../models/dialogue_beat.dart';
import '../../providers/storyboard_provider.dart';
import '../../services/api_service.dart';
import '../../services/movie_settings.dart';
import '../canvas/bgm_section.dart';
import '../canvas/canvas_view.dart' show fmtSeconds;
import '../common/output_preview.dart';
import '../common/audio_box.dart';
import '../common/image_zoom_dialog.dart';
import '../common/video_batch.dart';
import '../common/video_play_dialog.dart';
import '../common/video_trim_dialog.dart';
import '../ui.dart';

// 인스펙터는 탭별로 파일을 나눠 둔다. private 위젯을 탭들끼리 그대로 쓰려고
// 라이브러리 하나(part)로 묶는다 — 파일이 갈려도 이름은 전부 이 라이브러리 안이다.
part 'beat_tab.dart';
part 'scene_tab.dart';
part 'video_tab.dart';
part 'scene_settings_tab.dart';
part 'common_widgets.dart';

/// 캔버스 하단 샷 편집 패널: 탭 [장면 | 영상 | 공통]. 선택 샷을 편집한다.
/// (탭 선택은 settings.inspectorTab에 유지 — 예전 인스펙터 탭 기억을 이어받음.)
class ShotEditorPanel extends StatefulWidget {
  const ShotEditorPanel({super.key});

  @override
  State<ShotEditorPanel> createState() => _ShotEditorPanelState();
}

class _ShotEditorPanelState extends State<ShotEditorPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _restoredTab = false;
  String? _lastDialogueId; // 선택 변경 감지용(샷만 선택 시 '샷' 탭으로 전환)
  String? _lastShotId;

  @override
  void initState() {
    super.initState();
    final p = StoryboardScope.read(context);
    _tab = TabController(
      length: 4,
      vsync: this,
      initialIndex: p.settings.inspectorTab.clamp(0, 3),
    );
    _tab.addListener(() {
      if (!_tab.indexIsChanging) {
        StoryboardScope.read(context).setInspectorTab(_tab.index);
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    if (p.settingsLoaded && !_restoredTab) {
      // 저장된 인스펙터 탭 1회 복원.
      _restoredTab = true;
      _lastDialogueId = p.selectedDialogueId;
      _lastShotId = p.selectedShotId;
      final saved = p.settings.inspectorTab.clamp(0, 3);
      if (saved != _tab.index) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tab.index = saved;
        });
      }
    } else if (_restoredTab) {
      // 선택 변경 감지: '비트만' 선택(샷 없음)되면 '비트' 탭으로 전환.
      final dialogueId = p.selectedDialogueId;
      final shotId = p.selectedShotId;
      if (dialogueId != _lastDialogueId || shotId != _lastShotId) {
        _lastDialogueId = dialogueId;
        _lastShotId = shotId;
        if (dialogueId != null && shotId == null && _tab.index != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _tab.animateTo(0);
          });
        }
      }
    }
    final shot = p.selectedShot;
    return Container(
      color: panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            labelColor: accent2,
            indicatorColor: accent2,
            tabs: const [
              Tab(text: '비트'),
              Tab(text: '장면'),
              Tab(text: '영상'),
              Tab(text: '씬'),
            ],
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _tab,
              builder: (context, _) => IndexedStack(
                index: _tab.index,
                children: [
                  const _ShotInfoTab(),
                  shot == null ? const _NoShot() : _SceneTab(shot: shot),
                  shot == null ? const _NoShot() : _VideoTab(shot: shot),
                  const _SceneSettingsTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
