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
              // 씬 미리보기 — 영상 탭의 재생 팝업과 같은 것을 **항상 처음부터** 연다.
              // (영상 탭 것은 누른 그 샷에서 시작한다.)
              _ScenePreviewButton(),
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
                    // 영상 해상도는 트랙별 — 보고 있는 트랙 기준으로 보여 준다.
                    '영상 ${p.selectedTrack?.videoRes.width ?? sc.baseTrack.videoRes.width}'
                    '×${p.selectedTrack?.videoRes.height ?? sc.baseTrack.videoRes.height}'),
                _statePill(Icons.image_outlined,
                    '프레임 ${sc.imageRes.width}×${sc.imageRes.height}'),
                _statePill(Icons.layers_outlined, '트랙 ${p.tracks.length}'),
                _statePill(Icons.view_agenda_outlined,
                    '비트 ${p.baseBeats.length} · 샷 ${sc.shotCount}'),
                // 성우는 트랙별 — 지금 보고 있는 트랙 기준으로 보여 준다('트랙' 탭에서 편집).
                if ((p.selectedTrack?.defaultVoiceName.trim() ?? '').isNotEmpty)
                  _statePill(Icons.record_voice_over_outlined,
                      '성우 ${p.selectedTrack!.defaultVoiceName.trim()}'),
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

/// 씬 제목 바 오른쪽 끝의 미리보기 버튼 — 영상 탭 팝업과 **같은 재생**을 씬 **처음부터** 연다.
/// 뽑은 영상이 하나도 없어도 시작 프레임으로 세워 보여 주므로, 대사만 채운 콘티도 훑을 수 있다.
class _ScenePreviewButton extends StatelessWidget {
  const _ScenePreviewButton();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final playlist = p.scenePlaylist();
    return IconButton(
      tooltip: playlist.isEmpty ? '미리볼 샷이 없습니다' : '씬 미리보기 (처음부터)',
      onPressed: playlist.isEmpty
          ? null
          : () => showVideoPlayDialog(
                context,
                playlist: playlist,
                bgmPath: p.scenePlayBgmPath,
                speed: p.scenePlaySpeed,
              ),
      icon: const Icon(Icons.play_circle_outline, size: 22),
      color: accent2,
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
