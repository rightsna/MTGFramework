part of '../inspector_panel.dart';

/// 프레임 탭 — 샷의 시작/끝 프레임과 그 부속(영상 생성 방식 · 프레임 섹션).

/// 프레임 탭(샷): 프레임 메모 + 영상 생성 방식 + 시작/끝 프레임.
/// (씬 공통 프롬프트는 씬 탭으로 옮겼다 — 씬 단위 값이라 그쪽이 제자리다.)
class _FrameTab extends StatelessWidget {
  const _FrameTab({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    // 파생 샷도 바로 편집한다 — 어떤 칸을 고치면 그 프레임/프롬프트만 이 트랙 것으로 오버라이드되고
    // 나머지는 기준 트랙을 그대로 상속한다(필드별 자동 분리).
    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 프레임 메모 — 이 샷의 프레임 작업용. 영상 탭에는 별도의 영상 메모가 있다.
          _ShotNote(controller: p.shotNoteCtrl(shot.id)),
          const SizedBox(height: 14),
          // 이 샷의 프레임 생성 설정 — 영상 방식(FE2V/I2V) + 인물 참조를 한 카드에.
          _FrameGenSettings(shot: shot),
          const SizedBox(height: 14),
          // 결과(프레임)가 위, 그 생성에 쓰이는 설정(인물참조)은 아래.
          _FrameSection(
            title: '시작 프레임',
            icon: Icons.first_page,
            path: p.startPathOf(shot),
            busyKey: p.busyKey(shot.id, GenMode.imageStart),
            onLoad: () => p.loadFrame(shot, GenMode.imageStart),
            shot: shot,
            mode: GenMode.imageStart,
          ),
          // 끝 프레임은 FE2V에서만 쓴다 — I2V·스틸컷·IA2V면 숨긴다(파일은 남아 되돌리면 보인다).
          if (p.shotNeedsEndFrame(shot)) ...[
            const SizedBox(height: 16),
            _FrameSection(
              title: '끝 프레임',
              icon: Icons.last_page,
              path: p.shotEndImage(shot),
              busyKey: p.busyKey(shot.id, GenMode.imageEnd),
              onLoad: () => p.loadFrame(shot, GenMode.imageEnd),
              shot: shot,
              mode: GenMode.imageEnd,
            ),
          ],
        ],
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: body,
    );
  }
}
