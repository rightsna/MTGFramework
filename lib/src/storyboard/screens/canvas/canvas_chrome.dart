part of 'canvas_view.dart';

/// 캔버스 자체를 꾸미는 정적 위젯 — 씬 제목 바, 카드 사이 화살표, 도트 그리드 배경.

/// 캔버스 상단 고정 바 — 선택 씬의 제목을 보여주고 바로 수정한다. 씬 탭 제목칸과 **같은
/// 컨트롤러**를 써서 한쪽을 고치면 다른 쪽도 바뀐다(줌/팬에 안 딸려 가도록 캔버스 밖에 둔다).
class _SceneTitleBar extends StatelessWidget {
  const _SceneTitleBar();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    if (sc == null) return const SizedBox.shrink();
    final n = p.scenes.indexOf(sc) + 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: const BoxDecoration(
        color: panelBg,
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_filter_outlined, size: 18, color: accent2),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: ValueKey('canvas_scene_title_${sc.id}'),
                  controller: p.sceneTitleCtrl(sc.id),
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'SCENE $n (제목 없음)',
                    hintStyle: const TextStyle(
                        color: Colors.white38, fontWeight: FontWeight.w600),
                  ),
                  onChanged: (_) => p.noteEdited(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 제목 밑 현재 씬 상태 — 해상도·구성·설정을 한눈에(읽기 전용, 편집은 씬 탭).
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _statePill(Icons.aspect_ratio,
                    '영상 ${sc.videoRes.width}×${sc.videoRes.height}'),
                _statePill(Icons.image_outlined,
                    '프레임 ${sc.imageRes.width}×${sc.imageRes.height}'),
                _statePill(Icons.layers_outlined, '트랙 ${p.tracks.length}'),
                _statePill(Icons.view_agenda_outlined,
                    '비트 ${p.baseBeats.length} · 샷 ${sc.shotCount}'),
                if (sc.defaultVoiceName.trim().isNotEmpty)
                  _statePill(Icons.record_voice_over_outlined,
                      '성우 ${sc.defaultVoiceName.trim()}'),
                if (sc.loraUrl.trim().isNotEmpty)
                  _statePill(Icons.tune, 'LoRA'),
                if (sc.bgmPath != null || sc.bgmPrompt.trim().isNotEmpty)
                  _statePill(Icons.music_note, 'BGM'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 상태 한 조각 — 아이콘 + 값. 작고 흐릿하게(읽는 정보라 튀지 않게).
  static Widget _statePill(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white38),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ],
      );
}

/// 샷 사이 흐름 화살표 — 카드 상단 근처(헤더/대사 높이)에 맞춰 배치.

/// 샷 사이 흐름 화살표 — 카드 상단 근처(헤더/대사 높이)에 맞춰 배치.
class _ShotArrow extends StatelessWidget {
  const _ShotArrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 40, left: 4, right: 4),
      child: Icon(Icons.arrow_right_alt, color: accent, size: 30),
    );
  }
}

/// 캔버스 도트 그리드 배경.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const _step = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0x0AFFFFFF);
    for (var x = 0.0; x < size.width; x += _step) {
      for (var y = 0.0; y < size.height; y += _step) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
