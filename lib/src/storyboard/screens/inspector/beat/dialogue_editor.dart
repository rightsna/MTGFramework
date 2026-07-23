part of '../inspector_panel.dart';

/// 대사 내용 편집 — 화자 + 텍스트 + 음성(TTS). 입력은 즉시 저장된다(별도 저장 버튼 없음).
class _DialogueEditor extends StatefulWidget {
  const _DialogueEditor({super.key, required this.beat});

  final DialogueBeat beat;

  @override
  State<_DialogueEditor> createState() => _DialogueEditorState();
}

class _DialogueEditorState extends State<_DialogueEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.beat.dialogue?.text ?? '',
  );
  bool _genning = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final beat = widget.beat;
    final d = beat.dialogue;
    final speaker = d?.speakerId;
    final speakerChar = p.characterById(speaker);
    // 보이스가 지정된 화자면 그 보이스, 아니면(내레이션·화자 미지정) **씬 기본 성우**.
    final sceneVoice = p.selectedScene?.defaultVoiceName.trim() ?? '';
    final hasSceneVoice =
        (p.selectedScene?.defaultVoiceId.trim() ?? '').isNotEmpty;
    final target = (speakerChar != null && speakerChar.hasVoice)
        ? '${speakerChar.name.trim().isEmpty ? '화자' : speakerChar.name.trim()} 보이스'
        : hasSceneVoice
        ? '씬 기본 성우${sceneVoice.isEmpty ? '' : '($sceneVoice)'}'
        : null;
    final ownVoice = p.hasOwnVoice(beat);
    final has = p.hasAnyVoice(beat); // 자기 것이든 기준 트랙 상속이든
    final canGen =
        p.voiceReady && _text.text.trim().isNotEmpty && target != null;

    return _GroupCard(
      icon: Icons.record_voice_over_outlined,
      title: '대사 내용',
      done: has,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel('화자'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            initialValue: speaker,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('내레이션 (화자 없음)'),
              ),
              for (final c in p.characters)
                DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text(
                    '${c.name.trim().isEmpty ? '(이름 없음)' : c.name.trim()}'
                    '${c.hasVoice ? '  · 🎙 ${c.voiceName.isEmpty ? '보이스' : c.voiceName}' : '  · 보이스 없음'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => p.setShotDialogueSpeaker(beat, v),
          ),
          const SizedBox(height: 14),
          _SectionLabel('대사'),
          const SizedBox(height: 6),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: const InputDecoration(
              hintText: '이 비트에서 말할 내용(또는 내레이션). 비우면 무음',
              hintStyle: _hintStyle,
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              p.setShotDialogueText(beat, v);
              setState(() {}); // 음성 버튼 활성 갱신
            },
          ),
          const SizedBox(height: 6),
          const Text(
            '감정 표현: 문장 앞에 [crying] [whispers] [sighs] [shouts] 같은 '
            '영어 대괄호 태그 (일레븐랩스 v3)',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _SectionLabel('음성'),
          const SizedBox(height: 6),
          // 지금 설정된 음성이 먼저 — 결과가 위, 그걸 바꾸는 수단(불러오기/생성)이 아래.
          // 배경음과 **같은 AudioBox**를 쓴다(같은 오디오인데 UI가 다를 이유가 없다).
          if (!ownVoice && has) ...[
            Text(
              '${p.trackLabel(p.tracks.first)}의 음성입니다 — 여기서 생성하면 이 트랙 것이 됩니다',
              style: const TextStyle(fontSize: 11, color: Color(0x88FFFFFF)),
            ),
            const SizedBox(height: 6),
          ],
          AudioBox(
            path: p.voicePathOf(beat), // 상속 포함(자기 것 없으면 기준 트랙 음성)
            emptyText: '음성 없음 — 불러오거나 생성하세요',
            busy: _genning || p.isBusy(p.voiceBusyKey(beat.id)),
            version: p.verOf(p.voiceBusyKey(beat.id)),
            extraActions: [
              if (d != null)
                IconButton(
                  tooltip: '대사 지우기 (무음으로)',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  color: Colors.redAccent,
                  onPressed: () {
                    p.removeShotDialogue(beat);
                    _text.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
            footer: has ? _CoverageBadge(beat: beat) : null,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _genning ? null : () => p.loadVoice(beat),
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
          // ── 부가: AI(일레븐랩스)로 생성 ──
          Row(
            children: [
              const Icon(Icons.graphic_eq, size: 14, color: accent2),
              const SizedBox(width: 6),
              const Text(
                'AI로 생성 (선택)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            !p.voiceReady
                ? '설정에서 일레븐랩스 키를 넣어야 음성을 만들 수 있어요'
                : target == null
                ? '보이스 없음 — 화자에 목소리를 지정하거나, 씬 탭에서 기본 성우를 정하세요'
                : '$target 으로 위 대사를 읽습니다',
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: (_genning || !canGen)
                ? null
                : () async {
                    setState(() => _genning = true);
                    await p.genVoice(beat);
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
                  ? '음성 재생성'
                  : '음성 생성',
            ),
          ),
        ],
      ),
    );
  }
}
