part of '../inspector_panel.dart';

/// 효과음(SFX) 편집 — 소리 묘사 + 길이·충실도 + 생성/불러오기. 대사와 달리 **화자가 없다**.
/// 효과음은 트랙끼리 공유(기준 비트 소유)라 어느 트랙에서 편집하든 같이 바뀐다.
class _SfxEditor extends StatefulWidget {
  const _SfxEditor({super.key, required this.beat});

  final DialogueBeat beat;

  @override
  State<_SfxEditor> createState() => _SfxEditorState();
}

class _SfxEditorState extends State<_SfxEditor> {
  late final TextEditingController _prompt = TextEditingController(
    text: StoryboardScope.read(context).sfxOf(widget.beat)?.prompt ?? '',
  );
  late double _dur =
      (StoryboardScope.read(context).sfxOf(widget.beat)?.durationSeconds ?? 2.0)
          .clamp(0.5, 22);
  late double _infl =
      (StoryboardScope.read(context).sfxOf(widget.beat)?.promptInfluence ?? 0.3)
          .clamp(0.0, 1.0);
  bool _genning = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final beat = widget.beat;
    final has = p.hasSfx(beat);
    final canGen = p.voiceReady && _prompt.text.trim().isNotEmpty;

    return _GroupCard(
      icon: Icons.graphic_eq,
      title: '효과음',
      done: has,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel('소리 묘사'),
          const SizedBox(height: 6),
          TextField(
            controller: _prompt,
            minLines: 2,
            maxLines: 6,
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: const InputDecoration(
              hintText: '예: deep cinematic impact boom, sub-bass rumble, tense',
              hintStyle: _hintStyle,
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              p.setSfxPrompt(beat, v);
              setState(() {}); // 생성 버튼 활성 갱신
            },
          ),
          const SizedBox(height: 6),
          const Text(
            '상황·질감을 영어로 묘사할수록 잘 나옵니다 (일레븐랩스 효과음)',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 14),
          // 길이(초) — 일레븐랩스 0.5~22초.
          Row(
            children: [
              const _SectionLabel('길이'),
              const Spacer(),
              Text('${_dur.toStringAsFixed(1)}초',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: _dur,
            min: 0.5,
            max: 22,
            divisions: 215, // 0.1초 단위
            label: '${_dur.toStringAsFixed(1)}초',
            onChanged: (v) => setState(() => _dur = v),
            onChangeEnd: (v) => p.setSfxDuration(beat, v),
          ),
          // 프롬프트 충실도(0~1) — 높을수록 묘사에 충실, 낮을수록 다양.
          Row(
            children: [
              const _SectionLabel('프롬프트 충실도'),
              const Spacer(),
              Text(_infl.toStringAsFixed(2),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: _infl,
            min: 0,
            max: 1,
            divisions: 20,
            label: _infl.toStringAsFixed(2),
            onChanged: (v) => setState(() => _infl = v),
            onChangeEnd: (v) => p.setSfxInfluence(beat, v),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _SectionLabel('효과음'),
          const SizedBox(height: 6),
          AudioBox(
            path: p.sfxPathOf(beat),
            emptyText: '효과음 없음 — 불러오거나 생성하세요',
            busy: _genning || p.isBusy(p.sfxBusyKey(beat.id)),
            version: p.verOf(p.sfxBusyKey(beat.id)),
            extraActions: [
              if (has)
                IconButton(
                  tooltip: '효과음 지우기',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  color: Colors.redAccent,
                  onPressed: () => p.clearSfxSound(beat),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _genning ? null : () => p.loadSfx(beat),
            icon: const Icon(Icons.audio_file_outlined, size: 18),
            label: Text(has ? '다른 파일 불러오기' : '오디오 파일 불러오기'),
          ),
          const SizedBox(height: 2),
          const Text(
            'mp3 · wav · m4a · aac · flac · ogg — 길이는 자동으로 측정됩니다',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: const [
              Icon(Icons.graphic_eq, size: 14, color: accent2),
              SizedBox(width: 6),
              Text('AI로 생성 (선택)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            !p.voiceReady
                ? '설정에서 일레븐랩스 키를 넣어야 효과음을 만들 수 있어요'
                : '위 묘사로 ${_dur.toStringAsFixed(1)}초 효과음을 만듭니다',
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: (_genning || !canGen)
                ? null
                : () async {
                    setState(() => _genning = true);
                    await p.genSfx(beat);
                    if (mounted) setState(() => _genning = false);
                  },
            icon: _genning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(has ? Icons.refresh : Icons.graphic_eq, size: 18),
            label: Text(
              _genning
                  ? '생성 중…'
                  : has
                      ? '효과음 재생성'
                      : '효과음 생성',
            ),
          ),
        ],
      ),
    );
  }
}
