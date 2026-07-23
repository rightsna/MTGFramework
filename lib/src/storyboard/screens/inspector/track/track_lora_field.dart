part of '../inspector_panel.dart';

/// LoRA URL 입력 + 강도 슬라이더 (**트랙 단위** — 트랙마다 다른 LoRA로 뽑아 비교).
class _TrackLoraField extends StatefulWidget {
  const _TrackLoraField({required super.key, required this.track});

  final VideoTrack track;

  @override
  State<_TrackLoraField> createState() => _TrackLoraFieldState();
}

class _TrackLoraFieldState extends State<_TrackLoraField> {
  late final TextEditingController _url =
      TextEditingController(text: widget.track.loraUrl);
  late double _strength = widget.track.loraStrength.clamp(0.0, 1.5).toDouble();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _url,
          onSubmitted: (v) => p.setTrackLoraUrl(widget.track, v),
          onTapOutside: (_) {
            p.setTrackLoraUrl(widget.track, _url.text);
            FocusManager.instance.primaryFocus?.unfocus();
          },
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: 'LoRA URL (비우면 미적용)',
            hintStyle: _hintStyle.copyWith(fontSize: 12),
            helperText: '트랙 단위 · LTX-2.3용만 · civitai 페이지 URL 가능(토큰은 설정에)',
            suffixIcon: IconButton(
              tooltip: 'URL 복사',
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                final t = _url.text.trim();
                if (t.isEmpty) {
                  p.messenger?.call('복사할 LoRA URL이 없습니다');
                  return;
                }
                Clipboard.setData(ClipboardData(text: t));
                p.messenger?.call('LoRA URL 복사됨');
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('강도', style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: _strength,
                min: 0,
                max: 1.5,
                divisions: 15,
                label: _strength.toStringAsFixed(1),
                onChanged: (v) => setState(() => _strength = v),
                onChangeEnd: (v) => p.setTrackLoraStrength(widget.track, v),
              ),
            ),
            SizedBox(
              width: 30,
              child: Text(
                _strength.toStringAsFixed(1),
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
