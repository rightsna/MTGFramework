part of '../inspector_panel.dart';

/// 트랙 재생 배속 슬라이더(1.0~2.0, 0.1 단위). 미리보기·내보내기에 똑같이 걸린다.
class _TrackSpeedField extends StatefulWidget {
  const _TrackSpeedField({required super.key, required this.track});

  final VideoTrack track;

  @override
  State<_TrackSpeedField> createState() => _TrackSpeedFieldState();
}

class _TrackSpeedFieldState extends State<_TrackSpeedField> {
  late double _val = widget.track.speed.clamp(1.0, 2.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: _val,
            min: 1.0,
            max: 2.0,
            divisions: 10, // 0.1 단위
            label: '${_val.toStringAsFixed(1)}배',
            onChanged: (v) => setState(() => _val = v),
            onChangeEnd: (v) => p.setTrackSpeed(widget.track, v),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${_val.toStringAsFixed(1)}배',
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
