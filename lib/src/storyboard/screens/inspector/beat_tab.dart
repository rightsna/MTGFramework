part of 'inspector_panel.dart';

/// 비트 탭 — 비트 정보(메모·제목·연출 노트·대사)와 그 부속.

/// 비트 탭 — 선택 비트 정보(제목·비트 연출 노트·메모·대사).
class _BeatTab extends StatelessWidget {
  const _BeatTab();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final beat = p.selectedDialogue;
    if (beat == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, color: Colors.white24, size: 40),
            SizedBox(height: 10),
            Text('왼쪽에서 비트를 선택하세요', style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 비트 메모 — 영상·장면 탭과 마찬가지로 최상단에서 먼저 보인다.
          _ShotNote(controller: p.noteCtrl(beat.id)),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: accent2,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '비트 ${p.dialogues.indexOf(beat) + 1}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: Color(0xAAFFFFFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: p.titleCtrl(beat.id),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: '비트 제목 (선택)',
              isDense: true,
              filled: true,
              fillColor: previewBg,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => p.noteEdited(),
          ),
          const SizedBox(height: 12),
          _DirectionNote(dialogueId: beat.id),
          const SizedBox(height: 14),
          // 대사 내용·화자·음성은 팝업 대신 이 탭에서 바로 편집한다.
          _DialogueEditor(key: ValueKey('dlg_${beat.id}'), beat: beat),
        ],
      ),
    );
  }
}

/// 샷 길이 합(실제) vs 음성 길이(목표) 비교 — 부족하면 채우라고, 맞으면 초록으로.
/// 실제 재생되는 건 영상이므로 대사 길이 = 샷 합계이고, 음성은 그 위에 얹히는 목표치다.
class _CoverageBadge extends StatelessWidget {
  const _CoverageBadge({required this.beat});

  final DialogueBeat beat;

  @override
  Widget build(BuildContext context) {
    final gap = beat.coverageGap;
    if (gap == null) return const SizedBox.shrink();
    final short = gap < -0.05; // 영상이 음성보다 짧다 = 대사가 잘림
    final over = gap > 0.05; // 영상이 더 길다 = 음성 뒤 여백
    final c = short
        ? Colors.orangeAccent
        : over
            ? Colors.white54
            : Colors.greenAccent;
    final msg = short
        ? '샷 ${fmtSeconds(beat.seconds)} · 음성보다 ${fmtSeconds(-gap)} 짧음 — 대사가 잘립니다'
        : over
            ? '샷 ${fmtSeconds(beat.seconds)} · 음성 뒤 ${fmtSeconds(gap)} 여백'
            : '샷 ${fmtSeconds(beat.seconds)} · 음성과 맞음';
    return Row(
      children: [
        Icon(
          short
              ? Icons.warning_amber_rounded
              : over
                  ? Icons.more_horiz
                  : Icons.check_circle_outline,
          size: 13,
          color: c,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(msg, style: TextStyle(fontSize: 11, color: c)),
        ),
      ],
    );
  }
}

/// 대사 내용 편집 — 화자 + 텍스트 + 음성(TTS). 입력은 즉시 저장된다(별도 저장 버튼 없음).
class _DialogueEditor extends StatefulWidget {
  const _DialogueEditor({super.key, required this.beat});

  final DialogueBeat beat;

  @override
  State<_DialogueEditor> createState() => _DialogueEditorState();
}

class _DialogueEditorState extends State<_DialogueEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.beat.dialogue?.text ?? '');
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
    final canGen = p.voiceReady && _text.text.trim().isNotEmpty && target != null;

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
            Text('${p.trackLabel(p.tracks.first)}의 음성입니다 — 여기서 생성하면 이 트랙 것이 됩니다',
                style: const TextStyle(fontSize: 11, color: Color(0x88FFFFFF))),
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
              const Text('AI로 생성 (선택)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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

/// 비트 연출 노트 = 이 비트에서 **무엇을 표현할지**. 비트는 표현 단위이고, 대사는 그 표현을
/// 이루는 요소 중 하나일 뿐이다(대사 없이 연출만으로도 성립).
/// 메모(특이사항)와 달리 제작 지시에 해당하지만, 프롬프트로 자동으로 물리지는 않는다.
class _DirectionNote extends StatelessWidget {
  const _DirectionNote({required this.dialogueId});

  final String dialogueId;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0x145BD1C0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x335BD1C0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_filter_outlined, size: 15, color: accent2),
              const SizedBox(width: 6),
              const Text(
                '비트 연출 노트',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: accent2,
                ),
              ),
              const Spacer(),
              const Text(
                '무엇을 표현할지',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: p.directionCtrl(dialogueId),
            minLines: 6,
            maxLines: 30,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: const InputDecoration(
              hintText: '이 비트에서 무엇을 표현할지 (대사는 그중 하나)',
              isDense: true,
              filled: true,
              fillColor: previewBg,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => p.save(),
          ),
        ],
      ),
    );
  }
}
