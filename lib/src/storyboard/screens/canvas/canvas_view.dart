import 'package:flutter/material.dart';

import '../../models/shot.dart';
import '../../models/dialogue_beat.dart';
import '../../models/video_track.dart';
import '../../providers/storyboard_provider.dart';
import '../../services/api_service.dart';
import '../../services/movie_settings.dart';
import '../common/output_preview.dart';
import '../common/voice_play_button.dart';
import '../ui.dart';

// 캔버스도 조각별로 파일을 나눠 둔다. private 위젯을 조각들끼리 그대로 쓰려고
// 라이브러리 하나(part)로 묶는다.
part 'beat_card.dart';
part 'canvas_chrome.dart';
part 'track_lane.dart';
part 'track_menu.dart';

/// 대사(TTS·샷) 식별색.
const _voiceColor = Color(0xFFE0678A);

/// 삭제 전 확인. 되돌릴 수 없는 삭제는 전부 이걸 거친다 — 클릭 한 번에 사라지면 안 된다.
/// 삭제하면 참조가 끊긴 미디어 파일도 함께 정리되므로 그 사실을 알린다.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text('$body\n\n(더 이상 안 쓰는 미디어 파일도 함께 삭제됩니다)'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 가운데 캔버스: 선택 씬을 **트랙 줄들**로 그린다 — 트랙 하나가 씬 한 벌(비트 카드의 가로
/// 타임라인)이고, 트랙 수만큼 아래로 쌓여 같은 칸끼리 위아래로 견줄 수 있다.
/// 각 대사 = [헤더] + [대사 내용(0/1)] + [샷들]. 대사 한 마디 아래 샷들이 화면을 덮는다.
class CanvasView extends StatelessWidget {
  const CanvasView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    if (p.selectedScene == null) {
      return _empty(
        '왼쪽에서 씬을 추가/선택하세요',
        FilledButton.icon(
          onPressed: p.addScene,
          icon: const Icon(Icons.add),
          label: const Text('씬 추가'),
        ),
      );
    }
    // 구조(비트 수)는 기준 트랙이 정본 — 트랙끼리 같으므로 비었는지도 이걸로 본다.
    final dialogues = p.baseBeats;
    if (dialogues.isEmpty) {
      return _empty(
        '첫 비트를 추가하세요 (비트 하나 = 샷 여러 개)',
        FilledButton.icon(
          onPressed: p.addDialogue,
          icon: const Icon(Icons.add),
          label: const Text('비트 추가'),
        ),
      );
    }
    // 캔버스: 줌 인/아웃 + 상하좌우 팬(InteractiveViewer). 도트 그리드 배경 위에
    // **트랙 하나가 씬 한 벌**이다 — 비트 카드가 가로로 이어진 줄이 트랙 수만큼 아래로 쌓인다.
    // 카드 높이는 샷 수에 맞춰 fit. 메모(비트·샷)는 각 카드 아래에 흐름 그대로 달린다.
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(600),
      minScale: 0.3,
      maxScale: 1.8,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Padding(
            padding: const EdgeInsets.all(44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var t = 0; t < p.tracks.length; t++) ...[
                  if (t > 0) const SizedBox(height: 26),
                  _TrackLane(track: p.tracks[t], trackIndex: t),
                ],
                const SizedBox(height: 20),
                // 트랙 추가 — 씬을 한 벌 더 깔아 다른 조건으로 뽑아 보는 자리.
                OutlinedButton.icon(
                  onPressed: p.addTrack,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('트랙 추가'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent2,
                    side: const BorderSide(color: Color(0x338B7BFF)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String text, Widget button) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text(text), const SizedBox(height: 12), button],
        ),
      );
}

/// 초 표기(정수면 정수, 아니면 소수 1자리).
String fmtSeconds(double s) =>
    s == s.roundToDouble() ? '${s.toInt()}s' : '${s.toStringAsFixed(1)}s';
