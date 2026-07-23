part of '../inspector_panel.dart';

/// 스틸컷 길이(초) 슬라이더 — **0.1초 단위**. 0.1~15초.
/// AI 방식은 정수 초([_SecondsField])지만 스틸컷은 로컬 ffmpeg라 소수 초까지 자유롭다.
class _StillSecondsField extends StatefulWidget {
  const _StillSecondsField({required super.key});

  @override
  State<_StillSecondsField> createState() => _StillSecondsFieldState();
}

class _StillSecondsFieldState extends State<_StillSecondsField> {
  late double _val =
      (StoryboardScope.read(context).selectedShot?.stillSeconds ?? 1.0)
          .clamp(0.1, 15);

  String get _label => '${_val.toStringAsFixed(1)}초';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: _val,
            min: 0.1,
            max: 15,
            // 0.1 단위 = (15-0.1)/0.1 = 149 스텝.
            divisions: 149,
            label: _label,
            onChanged: (v) => setState(() => _val = v),
            onChangeEnd: (v) {
              final p = StoryboardScope.read(context);
              final c = p.selectedShot;
              if (c != null) p.setStillSeconds(c, v);
            },
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            _label,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
