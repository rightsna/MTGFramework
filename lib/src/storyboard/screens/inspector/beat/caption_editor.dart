part of '../inspector_panel.dart';

/// 자막(캡션) 편집 — 시간순 구간 목록(길이·텍스트) + 위치(상단/중간/하단).
/// 대사·효과음처럼 트랙끼리 공유(기준 비트 소유). 비트 재생 시 시작부터 순서대로 흐른다.
class _CaptionEditor extends StatelessWidget {
  const _CaptionEditor({super.key, required this.beat});

  final DialogueBeat beat;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final cap = p.captionOf(beat);
    final cues = cap?.cues ?? const <CaptionCue>[];
    final pos = cap?.position ?? CaptionPosition.bottom;

    return _GroupCard(
      icon: Icons.subtitles_outlined,
      title: '자막',
      done: cues.any((c) => c.text.trim().isNotEmpty),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 위치 — 상단/중간/하단.
          Row(
            children: [
              const _SectionLabel('위치'),
              const SizedBox(width: 8),
              for (final e in CaptionPosition.values) ...[
                ChoiceChip(
                  label: Text(e.label, style: _chipLabel),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  selected: pos == e,
                  onSelected: (_) => p.setCaptionPosition(beat, e),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (cues.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('자막 없음 — 아래 [+ 자막 추가]로 구간을 넣으세요',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
            )
          else
            // 구간 목록: [초] [텍스트] [삭제]. 위에서부터 순서대로 재생된다.
            for (final cue in cues)
              _CaptionCueRow(key: ObjectKey(cue), beat: beat, cue: cue),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => p.addCaptionCue(beat),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('자막 추가'),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '텍스트를 비우면 그 길이만큼 공백(자막 없음) 구간이 됩니다.',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

/// 자막 구간 한 줄 — 길이(초) + 텍스트 + 삭제. cue 객체를 직접 고친다(ObjectKey로 상태 유지).
class _CaptionCueRow extends StatefulWidget {
  const _CaptionCueRow(
      {required super.key, required this.beat, required this.cue});

  final DialogueBeat beat;
  final CaptionCue cue;

  @override
  State<_CaptionCueRow> createState() => _CaptionCueRowState();
}

class _CaptionCueRowState extends State<_CaptionCueRow> {
  late final TextEditingController _secs = TextEditingController(
    text: _fmt(widget.cue.seconds),
  );
  late final TextEditingController _text = TextEditingController(
    text: widget.cue.text,
  );

  static String _fmt(double s) =>
      s == s.roundToDouble() ? s.toInt().toString() : s.toStringAsFixed(1);

  @override
  void dispose() {
    _secs.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 길이(초).
          SizedBox(
            width: 52,
            child: TextField(
              controller: _secs,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                suffixText: '초',
                suffixStyle: TextStyle(fontSize: 10, color: Colors.white38),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                final d = double.tryParse(v.trim());
                if (d != null) p.setCaptionCueSeconds(widget.beat, widget.cue, d);
              },
            ),
          ),
          const SizedBox(width: 8),
          // 텍스트(비우면 공백 구간).
          Expanded(
            child: TextField(
              controller: _text,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '자막 텍스트 (비우면 공백)',
                hintStyle: _hintStyle,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  p.setCaptionCueText(widget.beat, widget.cue, v),
            ),
          ),
          IconButton(
            tooltip: '이 구간 삭제',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: Colors.redAccent,
            onPressed: () => p.removeCaptionCue(widget.beat, widget.cue),
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }
}
