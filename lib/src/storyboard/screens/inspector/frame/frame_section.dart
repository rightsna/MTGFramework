part of '../inspector_panel.dart';

/// 프레임(시작·끝) 한 칸 — 결과(프레임) + 프롬프트 + 생성/불러오기.
/// 시작 프레임엔 '앞 샷 끝 프레임으로 생성'이 하나 더 붙는다(컷 잇기).
class _FrameSection extends StatelessWidget {
  const _FrameSection({
    required this.title,
    required this.controller,
    required this.koController,
    required this.hint,
    required this.genLabel,
    required this.genIcon,
    required this.path,
    required this.busyKey,
    required this.onGen,
    required this.onLoad,
    required this.shot,
    required this.mode,
  });

  /// 이 프레임이 속한 샷 + 어느 프레임인지 — 삭제 버튼이 대상을 알기 위해.
  final Shot shot;
  final GenMode mode;

  final String title;
  final TextEditingController controller;
  final TextEditingController koController;
  final String hint;
  final String genLabel;
  final IconData genIcon;
  final String? path;
  final String busyKey;
  final VoidCallback onGen;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final busy = p.isBusy(busyKey);
    // 앞 샷에서 가져오기는 시작 프레임에만 있다 — 끝 프레임은 가져올 대상이 아니라 만드는 것이다.
    final isStart = mode == GenMode.imageStart;
    final hasPrev = isStart && p.prevShotOf(shot) != null;
    return _GroupCard(
      icon: genIcon,
      title: title,
      done: path != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 결과(프레임)가 위, 그걸 만드는 수단(프롬프트·생성/불러오기)이 아래.
          _OutputBlock(
            title: title,
            path: path,
            busyKey: busyKey,
            deleteTarget: (shot: shot, mode: mode),
          ),
          const SizedBox(height: 14),
          _PromptPair(
            label: '프롬프트',
            controller: controller,
            koController: koController,
            hint: hint,
            trailing: IconButton(
              tooltip: '프롬프트 복사 (씬 공통 포함)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                // 생성에 실제로 들어가는 형태 그대로 — 씬 공통 + 이 프레임 프롬프트.
                final t =
                    p.composedFramePrompt(shot, controller.text, mode).trim();
                if (t.isEmpty) {
                  p.messenger?.call('복사할 프롬프트가 없습니다');
                  return;
                }
                Clipboard.setData(ClipboardData(text: t));
                p.messenger?.call('$title 프롬프트 복사됨 (씬 공통 포함)');
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _GenButton(
                  label: genLabel,
                  icon: genIcon,
                  busyKey: busyKey,
                  onGen: onGen,
                  enabled: p.imageReady,
                  disabledHint: p.imageBlockReason,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : onLoad,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('불러오기'),
              ),
            ],
          ),
          // 컷 잇기 — 앞 샷의 끝 프레임(FE2V)이나 그 영상의 마지막 프레임을 이 샷의 시작으로.
          // AI 생성이 아니라 **가져오기**라 서버·키가 필요 없다.
          if (hasPrev) ...[
            const SizedBox(height: 8),
            Tooltip(
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
          ],
        ],
      ),
    );
  }
}
