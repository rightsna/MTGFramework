part of '../inspector_panel.dart';

/// 프레임 탭 — 샷의 시작/끝 프레임과 그 부속(생성 방식 토글·인물참조·프레임 섹션).

/// 프레임 탭(샷): 프레임 메모 + 생성 설정 + 시작/끝 프레임.
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
            controller: p.startCtrl(shot.id),
            koController: p.startKoCtrl(shot.id),
            hint: '샷의 첫 프레임(시작)을 묘사',
            genLabel: '시작 프레임 생성',
            genIcon: Icons.first_page,
            path: p.startPathOf(shot),
            busyKey: p.busyKey(shot.id, GenMode.imageStart),
            onGen: () => p.gen(shot, GenMode.imageStart),
            onLoad: () => p.loadFrame(shot, GenMode.imageStart),
            shot: shot,
            mode: GenMode.imageStart,
          ),
          // 끝 프레임은 FE2V에서만 쓴다 — I2V·스틸컷이면 숨긴다(파일은 남아 되돌리면 보인다).
          if (p.shotNeedsEndFrame(shot)) ...[
            const SizedBox(height: 16),
            _FrameSection(
              title: '끝 프레임',
              controller: p.endCtrl(shot.id),
              koController: p.endKoCtrl(shot.id),
              hint: '샷의 마지막 프레임(끝)을 묘사',
              genLabel: '끝 프레임 생성',
              genIcon: Icons.last_page,
              path: p.shotEndImage(shot),
              busyKey: p.busyKey(shot.id, GenMode.imageEnd),
              onGen: () => p.gen(shot, GenMode.imageEnd),
              onLoad: () => p.loadFrame(shot, GenMode.imageEnd),
              shot: shot,
              mode: GenMode.imageEnd,
            ),
          ],
          // 인물 참조는 위 '프레임 설정' 카드로 합쳤다.
          // 해상도(프레임·영상)는 씬 탭의 '생성 설정'에 모아 뒀다 — 여기선 이 샷의 것만 다룬다.
          const SizedBox(height: 16),
          _GroupCard(
            icon: Icons.layers_outlined,
            title: '씬 공통 프롬프트',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '이 씬의 모든 샷 **장면 생성**에 함께 붙습니다 ([씬] + [샷] 순).\n'
                  '영상 생성에는 붙지 않습니다 — 세계관·복장·룩은 이미 프레임이 들고 있습니다.',
                  style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.4),
                ),
                const SizedBox(height: 8),
                _SceneCommonField(
                    key: ValueKey('common_${p.selectedSceneId ?? ''}')),
              ],
            ),
          ),
        ],
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: body,
    );
  }
}
