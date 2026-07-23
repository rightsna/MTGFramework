part of '../inspector_panel.dart';

/// 샷별 영상 길이(초) 슬라이더. 1~15초.
class _SecondsField extends StatefulWidget {
  const _SecondsField({super.key});

  @override
  State<_SecondsField> createState() => _SecondsFieldState();
}

class _SecondsFieldState extends State<_SecondsField> {
  late double _val =
      (StoryboardScope.read(context).selectedShot?.videoSeconds ?? 5)
          .toDouble()
          .clamp(1, 15);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: _val,
            min: 1,
            max: 15,
            divisions: 14,
            label: '${_val.round()}초',
            onChanged: (v) => setState(() => _val = v),
            onChangeEnd: (v) {
              final p = StoryboardScope.read(context);
              final c = p.selectedShot;
              if (c != null) p.setShotSeconds(c, v.round());
            },
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${_val.round()}초',
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
