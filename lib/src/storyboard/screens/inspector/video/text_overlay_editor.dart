part of '../inspector_panel.dart';

/// 샷에 **구워 넣는 글씨** 편집기 — 타이틀 카드·썸네일 프레임.
///
/// 채널마다 "스틸 위에 문구를 얹은 첫 프레임"이 필요한데(머서=훅 문구, 루나리·베로니카=
/// 타이틀 카드), 그때마다 임시 스크립트로 합성해 두면 문구를 고칠 때 그림을 다시 만들어야 했다.
/// 여기서 문구를 고치면 **구워 둔 클립이 낡은 것으로 표시**되고 다음 내보내기에서 다시 구워진다.
class _TextOverlayEditor extends StatefulWidget {
  const _TextOverlayEditor({super.key, required this.shot});

  final Shot shot;

  @override
  State<_TextOverlayEditor> createState() => _TextOverlayEditorState();
}

class _TextOverlayEditorState extends State<_TextOverlayEditor> {
  late final TextEditingController _text = TextEditingController(
    text: StoryboardScope.read(context).textOverlayOf(widget.shot)?.text ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// 지금 값(없으면 기본값)에 [edit]을 적용해 저장한다. 문구가 비면 통째로 지운다 —
  /// 빈 글씨를 들고 있으면 내보낼 때 쓸데없이 필터를 태우게 된다.
  void _update(StoryboardProvider p, void Function(TextOverlay o) edit) {
    final o = p.textOverlayOf(widget.shot)?.copy() ?? TextOverlay();
    edit(o);
    p.setTextOverlay(widget.shot, o.hasText ? o : null);
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final o = p.textOverlayOf(widget.shot);
    final on = o != null && o.hasText;
    // (아래 상세 손잡이는 `on`이 참일 때만 그리는데, `on`으로는 o가 널 아님으로 승격되지
    //  않으므로 여기서 한 번 확정해 둔다.)
    final cur = on ? o : null;

    return _GroupCard(
      icon: Icons.title,
      title: '얹는 글씨',
      done: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: const InputDecoration(
              hintText: '타이틀 카드·썸네일 문구 — 비워 두면 안 얹습니다',
              hintStyle: _hintStyle,
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _update(p, (x) => x.text = v),
          ),
          const SizedBox(height: 6),
          const Text(
            '줄바꿈을 넣으면 그대로 나뉘고, 안 넣으면 폭에 맞춰 어절 단위로 접힙니다. '
            '편 맨 앞 샷에 얹으면 그 프레임이 곧 유튜브 썸네일이 됩니다.',
            style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.4),
          ),
          if (cur != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _SectionLabel('위치'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final pos in CaptionPosition.values)
                  ChoiceChip(
                    label: Text(pos.label),
                    selected: cur.position == pos,
                    onSelected: (_) => _update(p, (x) => x.position = pos),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _SectionLabel('색'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final c in _overlayColors)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: cur.color.toUpperCase() == c.hex,
                    onSelected: (_) => _update(p, (x) => x.color = c.hex),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _SfxSlider(
              label: '글씨 크기',
              value: cur.sizeRatio.clamp(0.03, 0.12),
              min: 0.03,
              max: 0.12,
              divisions: 18,
              text: '화면 높이의 ${(cur.sizeRatio * 100).toStringAsFixed(1)}%',
              onChanged: (v) => _update(p, (x) => x.sizeRatio = v),
              onChangeEnd: (v) => _update(p, (x) => x.sizeRatio = v),
            ),
            const SizedBox(height: 8),
            _SfxSlider(
              label: '뒤 어둠',
              value: cur.scrim.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              divisions: 20,
              text: cur.scrim < 0.005
                  ? '없음'
                  : '${(cur.scrim * 100).round()}%',
              onChanged: (v) => _update(p, (x) => x.scrim = v),
              onChangeEnd: (v) => _update(p, (x) => x.scrim = v),
            ),
            const SizedBox(height: 4),
            const Text(
              '글씨가 붙는 쪽에서 부드럽게 사라지는 어둠입니다 — 밝은 배경에서 글씨를 띄웁니다. '
              '가운데 정렬에는 깔리지 않습니다.',
              style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

/// 얹는 글씨 색 — 채널이 실제로 쓰는 것만 둔다(머서=노랑 훅, 나머지=흰 타이틀).
const _overlayColors = [
  (label: '흰색', hex: 'FFFFFF'),
  (label: '노랑', hex: 'FFD400'),
  (label: '검정', hex: '141416'),
];
