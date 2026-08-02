import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;

import '../../models/shot.dart';
import '../../models/dialogue_beat.dart';
import '../../models/video_track.dart';
import '../../providers/storyboard_provider.dart';
import '../../services/api_service.dart';
import '../../services/movie_settings.dart';
import '../common/output_preview.dart';
import '../common/video_play_dialog.dart';
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

/// 지금 화면에 보이는 캔버스 가로 범위(캔버스 좌표계). 카드가 이걸 보고 **화면 밖이면
/// 속(샷 썸네일)을 만들지 않는다** — 씬 하나에 카드가 수십 장이라 전부 지으면 첫 프레임이
/// 1.5초씩 걸린다(실측). 카드 폭이 고정(286)이라 x 위치가 계산으로 나와 컬링이 정확하다.
class _CanvasViewport extends InheritedWidget {
  const _CanvasViewport({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required super.child,
  });

  final double left;
  final double right;
  final double top;
  final double bottom;

  /// [x]~[x]+[width] 구간이 화면(여유 포함)에 걸치는지. 캔버스 밖에서 부르면 true(다 그린다).
  static bool visible(BuildContext context, double x, double width) {
    final v = context.dependOnInheritedWidgetOfExactType<_CanvasViewport>();
    if (v == null) return true;
    return x + width >= v.left && x <= v.right;
  }

  /// [y]~[y]+[height] 구간(트랙 줄)이 화면 세로 범위에 걸치는지.
  static bool visibleV(BuildContext context, double y, double height) {
    final v = context.dependOnInheritedWidgetOfExactType<_CanvasViewport>();
    if (v == null) return true;
    return y + height >= v.top && y <= v.bottom;
  }

  @override
  bool updateShouldNotify(_CanvasViewport old) =>
      old.left != left ||
      old.right != right ||
      old.top != top ||
      old.bottom != bottom;
}

/// 가운데 캔버스: 선택 씬을 **트랙 줄들**로 그린다 — 트랙 하나가 씬 한 벌(비트 카드의 가로
/// 타임라인)이고, 트랙 수만큼 아래로 쌓여 같은 칸끼리 위아래로 견줄 수 있다.
/// 각 대사 = [헤더] + [대사 내용(0/1)] + [샷들]. 대사 한 마디 아래 샷들이 화면을 덮는다.
class CanvasView extends StatefulWidget {
  const CanvasView({super.key});

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  /// 줌·팬 상태 — **어느 카드가 화면에 있는지** 계산하는 근거다([_CanvasViewport]).
  final TransformationController _tc = TransformationController();

  /// 카드를 그리기 시작했는지 — 프로젝트를 연 직후 **0.5초는 비워 둔다**.
  /// 여는 순간 씬 로드·화면 구성과 카드 수십 장 짓기가 한꺼번에 몰려 버벅였다.
  /// 창을 먼저 띄우고 카드는 그다음에 올린다(그 사이 '불러오는 중' 표시).
  bool _cardsReady = false;
  Timer? _readyTimer;

  @override
  void initState() {
    super.initState();
    _readyTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _cardsReady = true);
    });
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _tc.dispose();
    super.dispose();
  }

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
    // 씬 제목 바는 줌/팬에 안 딸려 가도록 캔버스 위에 고정으로 얹는다.
    return Column(
      children: [
        const _SceneTitleBar(),
        Expanded(
          child: _cardsReady
              ? _canvasBody(context, p)
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(height: 10),
                      Text('불러오는 중…',
                          style:
                              TextStyle(fontSize: 12, color: Colors.white38)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _canvasBody(BuildContext context, StoryboardProvider p) {
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
    return LayoutBuilder(builder: (context, box) {
      return AnimatedBuilder(
        animation: _tc,
        builder: (context, child) {
          // 화면에 보이는 캔버스 x 범위 — 화면좌표 = 배율×캔버스좌표 + 이동.
          // 반 화면만큼 여유를 둔다: 팬 중 미리 지어져 튀어나오지 않으면서, 처음 진입 때
          // 짓는 카드 수는 최소로(카드 하나가 300 element쯤 된다).
          final m = _tc.value;
          final scale = m.getMaxScaleOnAxis();
          final tx = m.getTranslation().x;
          final ty = m.getTranslation().y;
          // 여유는 화면의 1/4씩 — 팬을 시작하면 그 프레임에 바로 지어지므로 이 정도면
          // 튀어나오지 않고, 처음 열 때 짓는 카드 수는 최소가 된다.
          final margin = box.maxWidth / 4;
          final marginV = box.maxHeight / 4;
          return _CanvasViewport(
            left: (-tx) / scale - margin,
            right: (-tx + box.maxWidth) / scale + margin,
            top: (-ty) / scale - marginV,
            bottom: (-ty + box.maxHeight) / scale + marginV,
            child: child!,
          );
        },
        child: _viewer(p),
      );
    });
  }

  /// [t]번째 트랙 줄의 캔버스 y — 앞 줄들의 기억된 높이(없으면 추정)를 더한다.
  double _laneTop(StoryboardProvider p, int t) {
    var y = 44.0; // 캔버스 상단 패딩
    for (var i = 0; i < t; i++) {
      y += _TrackLane.laneHeights[p.tracks[i].id] ?? 460 + 26;
    }
    return y;
  }

  Widget _viewer(StoryboardProvider p) {
    return InteractiveViewer(
      transformationController: _tc,
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
                  _TrackLane(
                    track: p.tracks[t],
                    trackIndex: t,
                    // 이 줄의 캔버스 y — 앞 줄들의 (기억된) 높이 합. 화면 밖 줄은 안 짓는다.
                    canvasY: _laneTop(p, t),
                  ),
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

  static Widget _empty(String text, Widget button) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text(text), const SizedBox(height: 12), button],
        ),
      );
}

/// 초 표기(정수면 정수, 아니면 소수 1자리).
String fmtSeconds(double s) =>
    s == s.roundToDouble() ? '${s.toInt()}s' : '${s.toStringAsFixed(1)}s';
