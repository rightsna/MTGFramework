part of '../inspector_panel.dart';

/// 프레임(시작·끝) 한 칸 — 결과(프레임) + 불러오기.
///
/// 프레임은 **AI로 만들지 않는다**: 밖에서 만든 그림을 불러오거나, 시작 프레임이면
/// '앞 샷 끝 프레임으로 생성'으로 컷을 잇는다(로컬 이미지 생성은 걷어냈다).
class _FrameSection extends StatelessWidget {
  const _FrameSection({
    required this.title,
    required this.icon,
    required this.path,
    required this.busyKey,
    required this.onLoad,
    required this.shot,
    required this.mode,
  });

  /// 이 프레임이 속한 샷 + 어느 프레임인지 — 삭제 버튼이 대상을 알기 위해.
  final Shot shot;
  final GenMode mode;

  final String title;
  final IconData icon;
  final String? path;
  final String busyKey;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final busy = p.isBusy(busyKey);
    // 앞 샷에서 가져오기는 시작 프레임에만 있다 — 끝 프레임은 가져올 대상이 아니다.
    final hasPrev = mode == GenMode.imageStart && p.prevShotOf(shot) != null;
    return _GroupCard(
      icon: icon,
      title: title,
      done: path != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OutputBlock(
            title: title,
            path: path,
            busyKey: busyKey,
            deleteTarget: (shot: shot, mode: mode),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // 불러오기는 글자 폭만큼만 — 남는 자리는 '앞 샷 끝 프레임으로 생성'이 가져간다.
              // (높이·글자 크기는 다른 버튼과 같게 둔다 — 줄이면 눌러야 할 것처럼 안 보인다.)
              OutlinedButton.icon(
                onPressed: busy ? null : onLoad,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('불러오기'),
              ),
              // 컷 잇기 — 앞 샷의 끝 프레임(FE2V)이나 그 영상의 마지막 프레임을 이 샷의 시작으로.
              if (hasPrev) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: p.canStartFromPrevShot(shot)
                        ? '앞 샷의 끝 프레임(없으면 앞 샷 영상의 마지막 프레임)을 가져옵니다'
                        : '앞 샷에 끝 프레임도 영상도 없습니다',
                    child: OutlinedButton.icon(
                      onPressed: (busy || !p.canStartFromPrevShot(shot))
                          ? null
                          : () => p.startFromPrevShot(shot),
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('앞 샷 끝 프레임으로 생성'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
