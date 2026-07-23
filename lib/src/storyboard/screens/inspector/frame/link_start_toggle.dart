part of '../inspector_panel.dart';

/// 시작 프레임 연동 토글 — 켜면 앞 샷의 끝 프레임(이미지·프롬프트)이 따라 들어오고 편집이 잠긴다.
class _LinkStartToggle extends StatelessWidget {
  const _LinkStartToggle({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final prev = p.prevShotOf(shot);
    if (prev == null) return const SizedBox.shrink();
    final on = p.shotLinkStart(shot); // 상속/오버라이드 해석
    final prevName = p.shotLabel(prev);
    final prevHasEnd = p.shotEndImage(prev) != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 6, 2),
      decoration: BoxDecoration(
        color: on ? const Color(0x145BD1C0) : const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: on ? const Color(0x445BD1C0) : const Color(0x14FFFFFF),
        ),
      ),
      child: Row(
        children: [
          Icon(
            on ? Icons.link : Icons.link_off,
            size: 16,
            color: on ? accent2 : Colors.white38,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '앞 샷 끝 프레임 이어받기',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  on
                      ? (prevHasEnd
                          ? '$prevName의 끝 프레임 · 바뀌면 같이 바뀝니다'
                          : '$prevName에 끝 프레임이 아직 없습니다 — 만들면 들어옵니다')
                      : '이 샷의 시작 프레임을 직접 만듭니다',
                  style: TextStyle(
                    fontSize: 11,
                    color: on && !prevHasEnd
                        ? Colors.orangeAccent
                        : Colors.white38,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            onChanged: (v) => p.setLinkStart(shot, v),
          ),
        ],
      ),
    );
  }
}
