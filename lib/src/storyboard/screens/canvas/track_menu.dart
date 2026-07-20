part of 'canvas_view.dart';

/// 트랙 줄의 ⋯ 메뉴 — 이름 바꾸기 · 백엔드 고르기. (삭제는 옆의 휴지통 버튼)
///
/// 트랙을 고르는 별도 UI는 없다(캔버스가 모든 트랙을 펼쳐 두고, 누른 샷의 트랙이 곧 선택 트랙).
/// 그래서 트랙 자체를 손보는 자리도 **그 트랙 줄 안**에 둔다.
class _TrackMenu extends StatelessWidget {
  const _TrackMenu({required this.track});

  final VideoTrack track;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return SizedBox(
      width: 20,
      height: 20,
      child: PopupMenuButton<String>(
        tooltip: '트랙 설정',
        padding: EdgeInsets.zero,
        iconSize: 14,
        icon: const Icon(Icons.more_vert, color: Color(0x66FFFFFF)),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'rename', child: Text('이름 바꾸기')),
          const PopupMenuDivider(),
          // 백엔드가 트랙을 가르는 기준 — 이 트랙의 영상은 전부 이걸로 뽑힌다.
          ...VideoBackend.values.map((b) => PopupMenuItem(
                value: 'backend:${b.name}',
                child: Row(
                  children: [
                    Icon(
                        track.backend == b
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 15),
                    const SizedBox(width: 8),
                    Text(b.label),
                  ],
                ),
              )),
        ],
        onSelected: (v) async {
          if (v == 'rename') {
            final name = await _askName(context, p.trackLabel(track));
            if (name != null) p.setTrackName(track, name);
            return;
          }
          if (v.startsWith('backend:')) {
            p.setTrackBackend(
              track,
              VideoBackend.values.firstWhere(
                (e) => e.name == v.substring('backend:'.length),
              ),
            );
            return;
          }
        },
      ),
    );
  }

  Future<String?> _askName(BuildContext context, String current) {
    final ctrl = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('트랙 이름'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 자체서버 / Veo 3.1'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('확인')),
        ],
      ),
    );
  }
}
