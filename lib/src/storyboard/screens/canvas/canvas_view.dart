import 'package:flutter/material.dart';

import '../../models/shot.dart';
import '../../models/dialogue_beat.dart';
import '../../providers/storyboard_provider.dart';
import '../../services/api_service.dart';
import '../common/output_preview.dart';
import '../common/voice_play_button.dart';
import '../ui.dart';

// 캔버스도 조각별로 파일을 나눠 둔다. private 위젯을 조각들끼리 그대로 쓰려고
// 라이브러리 하나(part)로 묶는다.
part 'beat_card.dart';
part 'canvas_chrome.dart';

/// 대사(TTS·샷) 식별색.
const _voiceColor = Color(0xFFE0678A);

/// 삭제 전 확인. 되돌릴 수 없는 삭제는 전부 이걸 거친다 — 클릭 한 번에 사라지면 안 된다.
/// 미디어 파일은 프로젝트 폴더에 남으므로 그 사실도 같이 알린다.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text('$body\n\n(생성된 미디어 파일은 프로젝트 폴더에 남습니다)'),
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

/// 가운데 캔버스: 선택 씬을 **샷들의 가로 타임라인**으로 그린다.
/// 각 대사 = [상태] + [대사 내용(0/1)] + [샷들]. 대사 한 마디 아래 샷들이 화면을 덮는다.
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
    final dialogues = p.dialogues;
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
    // 대사 카드가 가로로 이어지고 사이사이 화살표로 흐름을 표시. 카드 높이는 샷 수에 맞춰 fit.
    // 우상단에는 씬 안의 모든 메모(씬·비트·샷)를 모은 패널이 뜬다(팬/줌과 무관하게 고정).
    return Stack(
      children: [
        Positioned.fill(child: _canvas(p, dialogues)),
        const Positioned(top: 10, right: 10, child: _MemoOverlay()),
      ],
    );
  }

  Widget _canvas(StoryboardProvider p, List<DialogueBeat> dialogues) {
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < dialogues.length; i++) ...[
                  SizedBox(
                      width: 286, child: _ShotCard(beat: dialogues[i], index: i)),
                  if (i < dialogues.length - 1) const _ShotArrow(),
                ],
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
