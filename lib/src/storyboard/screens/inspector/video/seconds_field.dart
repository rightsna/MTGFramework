part of '../inspector_panel.dart';

/// 샷별 영상 길이(초) 슬라이더. 하나의 값([Shot.videoSeconds])을 다루되 단위만 방식별로 다르다:
///  - AI(FE2V/I2V): **1초 단위**(백엔드가 정수 초만 받는다).
///  - 스틸컷: **0.1초 단위**(로컬 ffmpeg라 소수 초까지 자유롭다).
class _SecondsField extends StatefulWidget {
  const _SecondsField({required super.key, required this.still});

  /// 스틸컷이면 0.1초 단위, 아니면 1초 단위.
  final bool still;

  @override
  State<_SecondsField> createState() => _SecondsFieldState();
}

class _SecondsFieldState extends State<_SecondsField> {
  late double _val =
      (StoryboardScope.read(context).selectedShot?.videoSeconds ?? 5)
          .clamp(widget.still ? 0.1 : 1, 15);

  String get _label =>
      widget.still ? '${_val.toStringAsFixed(1)}초' : '${_val.round()}초';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: _val,
            min: widget.still ? 0.1 : 1,
            max: 15,
            // 스틸컷 0.1초 = (15-0.1)/0.1 ≈ 149스텝, AI 1초 = 14스텝.
            divisions: widget.still ? 149 : 14,
            label: _label,
            onChanged: (v) => setState(() => _val = v),
            onChangeEnd: (v) {
              final p = StoryboardScope.read(context);
              final c = p.selectedShot;
              // AI는 정수로 스냅해 넘긴다(백엔드가 정수 초).
              if (c != null) {
                p.setShotSeconds(c, widget.still ? v : v.roundToDouble());
              }
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
