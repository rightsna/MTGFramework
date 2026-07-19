import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard

import '../../models/shot.dart';
import '../../models/dialogue_beat.dart';
import '../../providers/storyboard_provider.dart';
import '../../services/api_service.dart';
import '../../services/movie_settings.dart';
import '../canvas/bgm_section.dart';
import '../canvas/canvas_view.dart' show fmtSeconds;
import '../common/output_preview.dart';
import '../common/audio_box.dart';
import '../common/image_zoom_dialog.dart';
import '../common/video_batch.dart';
import '../common/video_play_dialog.dart';
import '../common/video_trim_dialog.dart';
import '../ui.dart';

/// 비트 탭 — 선택 비트 정보(제목·비트 연출 노트·메모·대사).
class _ShotInfoTab extends StatelessWidget {
  const _ShotInfoTab();

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
          _ShotNote(dialogueId: beat.id),
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
    final target = (speakerChar != null && speakerChar.hasVoice)
        ? '${speakerChar.name.trim().isEmpty ? '화자' : speakerChar.name.trim()} 보이스'
        : (p.settings.elevenVoiceId.trim().isNotEmpty
            ? '기본 보이스${p.settings.elevenVoiceName.trim().isEmpty ? '' : '(${p.settings.elevenVoiceName.trim()})'}'
            : null);
    final has = d?.hasVoice ?? false;
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
          AudioBox(
            path: d?.voicePath,
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
                    ? '보이스 없음 — 화자에 보이스를 지정하거나 설정에서 기본 보이스를 정하세요'
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

/// 캔버스 하단 샷 편집 패널: 탭 [장면 | 영상 | 공통]. 선택 샷을 편집한다.
/// (탭 선택은 settings.inspectorTab에 유지 — 예전 인스펙터 탭 기억을 이어받음.)
class ShotEditorPanel extends StatefulWidget {
  const ShotEditorPanel({super.key});

  @override
  State<ShotEditorPanel> createState() => _ShotEditorPanelState();
}

class _ShotEditorPanelState extends State<ShotEditorPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _restoredTab = false;
  String? _lastDialogueId; // 선택 변경 감지용(샷만 선택 시 '샷' 탭으로 전환)
  String? _lastShotId;

  @override
  void initState() {
    super.initState();
    final p = StoryboardScope.read(context);
    _tab = TabController(
      length: 4,
      vsync: this,
      initialIndex: p.settings.inspectorTab.clamp(0, 3),
    );
    _tab.addListener(() {
      if (!_tab.indexIsChanging) {
        StoryboardScope.read(context).setInspectorTab(_tab.index);
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    if (p.settingsLoaded && !_restoredTab) {
      // 저장된 인스펙터 탭 1회 복원.
      _restoredTab = true;
      _lastDialogueId = p.selectedDialogueId;
      _lastShotId = p.selectedShotId;
      final saved = p.settings.inspectorTab.clamp(0, 3);
      if (saved != _tab.index) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tab.index = saved;
        });
      }
    } else if (_restoredTab) {
      // 선택 변경 감지: '비트만' 선택(샷 없음)되면 '비트' 탭으로 전환.
      final dialogueId = p.selectedDialogueId;
      final shotId = p.selectedShotId;
      if (dialogueId != _lastDialogueId || shotId != _lastShotId) {
        _lastDialogueId = dialogueId;
        _lastShotId = shotId;
        if (dialogueId != null && shotId == null && _tab.index != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _tab.animateTo(0);
          });
        }
      }
    }
    final shot = p.selectedShot;
    return Container(
      color: panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            labelColor: accent2,
            indicatorColor: accent2,
            tabs: const [
              Tab(text: '비트'),
              Tab(text: '장면'),
              Tab(text: '영상'),
              Tab(text: '씬'),
            ],
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _tab,
              builder: (context, _) => IndexedStack(
                index: _tab.index,
                children: [
                  const _ShotInfoTab(),
                  shot == null ? const _NoShot() : _SceneTab(shot: shot),
                  shot == null ? const _NoShot() : _VideoTab(shot: shot),
                  const _SceneSettingsTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 장면·영상 탭에 편집할 샷이 없을 때의 안내.
///  - 샷 미선택 → 샷을 먼저 선택
///  - 대사는 있으나 샷 0개 → 샷 추가(＋)
///  - 샷은 있으나 선택 안 됨 → 캔버스에서 샷을 클릭하도록 안내
class _NoShot extends StatelessWidget {
  const _NoShot();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final beat = p.selectedDialogue;
    if (beat == null) {
      return const _CenterNote(
        icon: Icons.touch_app_outlined,
        title: '비트를 선택하세요',
      );
    }
    if (beat.shots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_filter_outlined,
              color: Colors.white24,
              size: 40,
            ),
            const SizedBox(height: 10),
            const Text(
              '이 비트에 샷이 없습니다',
              style: TextStyle(color: Colors.white38),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => p.addShot(beat),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('비트 추가'),
            ),
          ],
        ),
      );
    }
    return const _CenterNote(
      icon: Icons.ads_click,
      title: '샷을 선택하세요',
      subtitle: '캔버스에서 편집할 샷을 클릭하면\n그 샷의 장면·영상을 편집할 수 있어요',
    );
  }
}

/// 가운데 안내(아이콘 + 제목 + 선택 부제) — 인스펙터 빈 상태 공용.
class _CenterNote extends StatelessWidget {
  const _CenterNote({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 40),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: Colors.white38)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white24),
            ),
          ],
        ],
      ),
    );
  }
}

/// 영상 생성 방식 토글(샷) — I2V / FE2V.
/// 같은 모델·같은 그래프고 끝 프레임을 박느냐만 다르다. FE2V는 끝 그림이 정해지는 대신
/// 양끝이 멀면 중간이 깨지고, I2V는 끝이 자유로운 대신 어디로 갈지 통제가 안 된다.
class _VideoModeToggle extends StatelessWidget {
  const _VideoModeToggle({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final i2v = shot.i2v;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0x148B7BFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x338B7BFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_creation_outlined, size: 15, color: accent),
              const SizedBox(width: 6),
              const Text(
                '영상 생성 방식',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('FE2V'),
                icon: Icon(Icons.compare_arrows, size: 15),
              ),
              ButtonSegment(
                value: true,
                label: Text('I2V'),
                icon: Icon(Icons.play_arrow, size: 15),
              ),
            ],
            selected: {i2v},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
            onSelectionChanged: (s) => p.setI2v(shot, s.first),
          ),
          const SizedBox(height: 6),
          Text(
            i2v
                ? '시작장면 한 장만 쓰고, 끝은 모델이 만든다 — 끝장면은 생성/사용하지 않음'
                : '시작·끝 두 장을 고정하고 그 사이를 만든다 — 끝장면이 필요함',
            style: const TextStyle(fontSize: 11, color: Colors.white54, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// 장면 탭(샷): 대사 메모 + 인물참조 + 시작/끝장면 프레임.
class _SceneTab extends StatelessWidget {
  const _SceneTab({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VideoModeToggle(shot: shot),
          const SizedBox(height: 14),
          // 결과(프레임)가 위, 그 생성에 쓰이는 설정(인물참조)은 아래.
          _FrameSection(
            title: '시작장면',
            controller: p.startCtrl(shot.id),
            koController: p.startKoCtrl(shot.id),
            hint: '샷의 첫 프레임(시작 장면)을 묘사',
            genLabel: '시작장면 생성',
            genIcon: Icons.first_page,
            path: p.startPathOf(shot),
            busyKey: p.busyKey(shot.id, GenMode.imageStart),
            onGen: () => p.gen(shot, GenMode.imageStart),
            onLoad: () => p.loadFrame(shot, GenMode.imageStart),
            shot: shot,
            mode: GenMode.imageStart,
          ),
          // I2V면 끝장면은 안 쓴다 — 숨긴다(파일은 남아 있어 FE2V로 되돌리면 그대로 보인다).
          if (!shot.i2v) ...[
            const SizedBox(height: 16),
            _FrameSection(
              title: '끝장면',
              controller: p.endCtrl(shot.id),
              koController: p.endKoCtrl(shot.id),
              hint: '샷의 마지막 프레임(끝 장면)을 묘사',
              genLabel: '끝장면 생성',
              genIcon: Icons.last_page,
              path: shot.endImagePath,
              busyKey: p.busyKey(shot.id, GenMode.imageEnd),
              onGen: () => p.gen(shot, GenMode.imageEnd),
              onLoad: () => p.loadFrame(shot, GenMode.imageEnd),
              shot: shot,
              mode: GenMode.imageEnd,
            ),
          ],
          const SizedBox(height: 16),
          _RefCharacterPicker(shot: shot),
          const SizedBox(height: 16),
          _GroupCard(
            icon: Icons.tune,
            title: '설정',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('생성 해상도'),
                const SizedBox(height: 2),
                const Text(
                  'FE2V 입력이라 영상과 비율을 맞추세요.',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in ImageRes.values)
                      ChoiceChip(
                        label: Text(r.label),
                        selected: p.settings.imageRes == r,
                        onSelected: (_) => p.setImageRes(r),
                      ),
                  ],
                ),
                if (shot.refCharacterIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 13, color: Colors.orangeAccent),
                      SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '인물참조가 있으면 이 해상도가 무시되고 참조 사진 크기로 나옵니다',
                          style: TextStyle(
                              fontSize: 11, color: Colors.orangeAccent),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _GroupCard(
            icon: Icons.layers_outlined,
            title: '씬 공통 프롬프트',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '이 씬의 모든 샷 **장면 생성**에 함께 붙습니다 ([씬] + [샷] 순).\n'
                  '영상 생성에는 붙지 않습니다 — 세계관·복장·룩은 이미 프레임이 들고 있습니다.',
                  style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.4),
                ),
                const SizedBox(height: 8),
                _SceneCommonField(
                    key: ValueKey('common_${p.selectedSceneId ?? ''}')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 샷 메모(특이사항). 프롬프트와 무관한 자유 기록 — 생성에 쓰이지 않는다.
class _ShotNote extends StatelessWidget {
  const _ShotNote({required this.dialogueId});

  final String dialogueId;

  static const _amber = Color(0xFFE0A94A);

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0x14E0A94A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33E0A94A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined, size: 15, color: _amber),
              const SizedBox(width: 6),
              const Text(
                '메모 · 특이사항',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: _amber,
                ),
              ),
              const Spacer(),
              const Text(
                '생성에 안 쓰임',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: p.noteCtrl(dialogueId),
            minLines: 2,
            maxLines: 6,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: const InputDecoration(
              hintText: '이 샷의 특이사항·참고를 자유롭게 기록 (프롬프트 아님)',
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

/// 인물 참조 피커(샷). 선택 시 이 샷의 장면 생성이 인물 대표사진을 레퍼런스로 정체성 유지 생성.
class _RefCharacterPicker extends StatelessWidget {
  const _RefCharacterPicker({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final chars = p.characters;
    final sel = shot.refCharacterIds;
    final atCap = sel.length >= 3;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.face_retouching_natural,
                size: 16,
                color: accent2,
              ),
              const SizedBox(width: 6),
              const Text(
                '인물 참조',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: accent2,
                ),
              ),
              const Spacer(),
              Text(
                '${sel.length}/3',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
          if (chars.isNotEmpty) ...[
            const SizedBox(height: 3),
            const Text(
              '각 인물의 대표이미지를 레퍼런스로 사용합니다 · 대표는 인물 관리에서 변경',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
          const SizedBox(height: 8),
          if (chars.isEmpty)
            const Text(
              '인물 관리에서 인물을 먼저 추가하세요',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final c in chars)
                  FilterChip(
                    label: Text(c.name.isEmpty ? '(이름 없음)' : c.name),
                    selected: sel.contains(c.id),
                    onSelected: (atCap && !sel.contains(c.id))
                        ? null
                        : (_) => p.toggleShotRefCharacter(shot, c.id),
                  ),
              ],
            ),
          if (sel.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              '선택 인물들 대표사진을 레퍼런스로 정체성 유지 생성 (FireRed 멀티)',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }
}

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

/// LoRA URL 입력 + 강도 슬라이더 (씬 단위 — 같은 씬 샷들끼리 공유).
class _LoraField extends StatefulWidget {
  const _LoraField({super.key});

  @override
  State<_LoraField> createState() => _LoraFieldState();
}

class _LoraFieldState extends State<_LoraField> {
  late final TextEditingController _url = TextEditingController(
    text: StoryboardScope.read(context).selectedScene?.loraUrl ?? '',
  );
  late double _strength =
      (StoryboardScope.read(context).selectedScene?.loraStrength ?? 0.8).clamp(
        0.0,
        1.5,
      );

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
          onSubmitted: (v) => p.setSceneLoraUrl(v),
          onTapOutside: (_) {
            p.setSceneLoraUrl(_url.text);
            FocusManager.instance.primaryFocus?.unfocus();
          },
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: 'LoRA URL (비우면 미적용)',
            helperText: '씬 단위 · LTX-2.3용만 · civitai 페이지 URL 가능(토큰은 설정에)',
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
                onChangeEnd: (v) => p.setSceneLoraStrength(v),
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

/// 영상 탭(샷): 설정(해상도·LoRA) + 영상.
class _VideoTab extends StatelessWidget {
  const _VideoTab({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final c = shot;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 결과(영상)가 위, 그걸 만드는 수단(프롬프트·생성) 다음, 설정은 맨 아래.
          _GroupCard(
            icon: Icons.movie_outlined,
            title: '영상',
            done: c.videoPath != null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OutputBlock(
                  title: '영상',
                  path: c.videoPath,
                  busyKey: p.busyKey(c.id, GenMode.videoLow),
                  isVideo: true,
                  deleteTarget: (shot: c, mode: GenMode.videoLow),
                  trimTarget: c,
                ),
                const SizedBox(height: 14),
                _SectionLabel('프롬프트'),
                const SizedBox(height: 6),
                _PromptField(
                  controller: p.videoCtrl(c.id),
                  hint: '움직임/카메라 등 영상 묘사',
                ),
                const SizedBox(height: 10),
                _SectionLabel('프롬프트 번역 (한국어)'),
                const SizedBox(height: 6),
                _PromptField(
                  controller: p.videoKoCtrl(c.id),
                  hint: '위 프롬프트를 한국어로 — 확인용이고 생성엔 안 쓰임',
                ),
                const SizedBox(height: 14),
                _SectionLabel('길이 (초 · 이 샷)'),
                const SizedBox(height: 6),
                _SecondsField(key: ValueKey('sec_${c.id}')),
                const SizedBox(height: 10),
                // 백엔드를 버튼에서 직접 고른다(설정 안 들어가도 됨).
                // 결과 슬롯은 하나라 다른 백엔드로 다시 뽑으면 덮어쓴다.
                _GenButton(
                  label: 'Veo로 생성',
                  icon: Icons.auto_awesome_outlined,
                  busyKey: p.busyKey(c.id, GenMode.videoLow),
                  onGen: () =>
                      p.gen(c, GenMode.videoLow, backend: VideoBackend.veo),
                  enabled: p.videoReadyOf(VideoBackend.veo),
                  disabledHint: p.videoBlockReasonOf(VideoBackend.veo),
                ),
                const SizedBox(height: 8),
                _GenButton(
                  label: '자체 서버로 생성',
                  icon: Icons.movie_outlined,
                  busyKey: p.busyKey(c.id, GenMode.videoLow),
                  onGen: () => p.gen(
                    c,
                    GenMode.videoLow,
                    backend: VideoBackend.serviceApi,
                  ),
                  enabled: p.videoReadyOf(VideoBackend.serviceApi),
                  disabledHint: p.videoBlockReasonOf(VideoBackend.serviceApi),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _GroupCard(
            icon: Icons.tune,
            title: '설정',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('생성 해상도'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in VideoRes.values)
                      ChoiceChip(
                        label: Text(r.label),
                        selected: p.settings.videoRes == r,
                        onSelected: (_) => p.setVideoRes(r),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const _SectionLabel('LoRA (선택 · LTX-2.3용)'),
                const SizedBox(height: 6),
                _LoraField(key: ValueKey('lora_${p.selectedSceneId}')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 씬 탭 — 선택 씬의 것들을 한곳에: 제목 · 공통 프롬프트 · 영상 일괄 생성 · 배경음.
class _SceneSettingsTab extends StatelessWidget {
  const _SceneSettingsTab();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    if (sc == null) {
      return const Center(
        child: Text('씬을 선택하세요', style: TextStyle(color: Colors.white38)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupCard(
            icon: Icons.movie_filter_outlined,
            title: '씬',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionLabel('제목'),
                const SizedBox(height: 6),
                TextField(
                  key: ValueKey('scene_title_${sc.id}'),
                  controller: p.sceneTitleCtrl(sc.id),
                  style:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: '씬 제목 (선택)',
                    isDense: true,
                    filled: true,
                    fillColor: previewBg,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => p.noteEdited(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _GroupCard(
            icon: Icons.auto_awesome_motion_outlined,
            title: '영상 일괄 생성',
            child: VideoBatch(),
          ),
          const SizedBox(height: 16),
          const BgmSection(),
          const SizedBox(height: 24),
          // 구조는 두고 생성물만 비우기 — 다시 뽑기 전 초기화용.
          OutlinedButton.icon(
            onPressed: () async {
              final shots = [for (final b in sc.dialogues) ...b.shots];
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('미디어 모두 삭제'),
                  content: Text(
                    '"${sc.title.trim().isEmpty ? '(제목 없음)' : sc.title.trim()}" 씬의 '
                    '생성물을 모두 지웁니다 — 샷 ${shots.length}개의 시작·끝 프레임과 영상, '
                    '대사 음성, 배경음.\n'
                    '파일도 함께 삭제되며 되돌릴 수 없습니다.\n\n'
                    '프롬프트·제목·대사 텍스트 등 구조는 그대로 남습니다.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('모두 삭제'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                final n = await p.removeSceneMedia();
                p.messenger?.call('미디어 $n개를 삭제했습니다');
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orangeAccent,
              side: const BorderSide(color: Color(0x55FFAB40)),
            ),
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: const Text('미디어 모두 삭제'),
          ),
          const SizedBox(height: 8),
          // 파괴적 동작이라 맨 아래에, 확인을 거쳐서. (예전엔 씬 목록 안에 있어 오클릭이 쉬웠다.)
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('씬 삭제'),
                  content: Text(
                    '"${sc.title.trim().isEmpty ? '(제목 없음)' : sc.title.trim()}" 씬을 삭제합니다.\n'
                    '비트 ${sc.dialogues.length}개 · 샷 ${sc.shotCount}개가 함께 사라집니다. '
                    '되돌릴 수 없습니다.\n\n'
                    '(생성된 미디어 파일은 프로젝트 폴더에 남습니다)',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('삭제'),
                    ),
                  ],
                ),
              );
              if (ok == true) p.removeScene(sc);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Color(0x55FF5252)),
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('이 씬 삭제'),
          ),
        ],
      ),
    );
  }
}

class _SceneCommonField extends StatefulWidget {
  const _SceneCommonField({super.key});

  @override
  State<_SceneCommonField> createState() => _SceneCommonFieldState();
}

class _SceneCommonFieldState extends State<_SceneCommonField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: StoryboardScope.read(context).selectedScene?.commonPrompt ?? '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      minLines: 3,
      maxLines: 8,
      style: const TextStyle(fontSize: 13, height: 1.4),
      onChanged: (v) => StoryboardScope.read(context).setSceneCommonPrompt(v),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: const InputDecoration(
        hintText: '예: 이 씬의 장소·분위기·시간대…',
        isDense: true,
        filled: true,
        fillColor: previewBg,
        border: OutlineInputBorder(),
      ),
    );
  }
}

/// 한 프레임(시작/끝)의 프롬프트 편집 + 생성 버튼 + 결과 미리보기 묶음.
class _FrameSection extends StatelessWidget {
  const _FrameSection({
    required this.title,
    required this.controller,
    required this.koController,
    required this.hint,
    required this.genLabel,
    required this.genIcon,
    required this.path,
    required this.busyKey,
    required this.onGen,
    required this.onLoad,
    required this.shot,
    required this.mode,
  });

  /// 이 프레임이 속한 샷 + 어느 프레임인지 — 삭제 버튼이 대상을 알기 위해.
  final Shot shot;
  final GenMode mode;

  final String title;
  final TextEditingController controller;
  final TextEditingController koController;
  final String hint;
  final String genLabel;
  final IconData genIcon;
  final String? path;
  final String busyKey;
  final VoidCallback onGen;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final busy = p.isBusy(busyKey);
    // 연동은 시작장면에만 있다 — 끝장면은 물려받을 대상이 아니라 만드는 것이다.
    final canLink = mode == GenMode.imageStart && p.prevShotOf(shot) != null;
    final linked = mode == GenMode.imageStart && shot.linkStart;
    return _GroupCard(
      icon: genIcon,
      title: title,
      done: path != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canLink) ...[
            _LinkStartToggle(shot: shot),
            const SizedBox(height: 10),
          ],
          // 결과(프레임)가 위, 그걸 만드는 수단(프롬프트·생성/불러오기)이 아래.
          _OutputBlock(
            title: title,
            path: path,
            busyKey: busyKey,
            // 연동 중인 시작장면은 앞 샷의 끝장면 파일 그 자체다 — 여기서 지우면 앞 샷이 날아간다.
            // 지우려면 연동을 먼저 끄거나, 앞 샷의 끝장면에서 지워야 한다.
            deleteTarget: linked ? null : (shot: shot, mode: mode),
          ),
          const SizedBox(height: 14),
          _SectionLabel('프롬프트'),
          const SizedBox(height: 6),
          _PromptField(
            controller: controller,
            hint: linked ? '앞 샷의 끝장면 프롬프트가 들어옵니다' : hint,
            readOnly: linked,
          ),
          const SizedBox(height: 10),
          _SectionLabel('프롬프트 번역 (한국어)'),
          const SizedBox(height: 6),
          _PromptField(
            controller: koController,
            hint: '위 프롬프트를 한국어로 — 확인용이고 생성엔 안 쓰임',
            readOnly: linked,
          ),
          const SizedBox(height: 10),
          // 연동 중이면 만들 게 없다 — 앞 샷의 끝장면이 곧 이 샷의 시작이다.
          if (!linked)
            Row(
              children: [
                Expanded(
                  child: _GenButton(
                    label: genLabel,
                    icon: genIcon,
                    busyKey: busyKey,
                    onGen: onGen,
                    enabled: p.imageReady,
                    disabledHint: p.imageBlockReason,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : onLoad,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('불러오기'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 시작장면 연동 토글 — 켜면 앞 샷의 끝장면(이미지·프롬프트)이 따라 들어오고 편집이 잠긴다.
class _LinkStartToggle extends StatelessWidget {
  const _LinkStartToggle({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final prev = p.prevShotOf(shot);
    if (prev == null) return const SizedBox.shrink();
    final on = shot.linkStart;
    final prevName = p.shotLabel(prev);
    final prevHasEnd = prev.endImagePath != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 6, 2),
      decoration: BoxDecoration(
        color: on ? const Color(0x145BD1C0) : const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: on ? const Color(0x445BD1C0) : const Color(0x14FFFFFF),
        ),
      ),
      child: Row(
        children: [
          Icon(
            on ? Icons.link : Icons.link_off,
            size: 16,
            color: on ? accent2 : Colors.white38,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '앞 샷 끝장면 이어받기',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  on
                      ? (prevHasEnd
                          ? '$prevName의 끝장면 · 바뀌면 같이 바뀝니다'
                          : '$prevName에 끝장면이 아직 없습니다 — 만들면 들어옵니다')
                      : '이 샷의 시작장면을 직접 만듭니다',
                  style: TextStyle(
                    fontSize: 11,
                    color: on && !prevHasEnd
                        ? Colors.orangeAccent
                        : Colors.white38,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            onChanged: (v) => p.setLinkStart(shot, v),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.icon,
    required this.title,
    required this.child,
    this.done,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final bool? done;

  @override
  Widget build(BuildContext context) {
    final lit = done ?? false;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: lit ? const Color(0x335BD1C0) : const Color(0x1AFFFFFF),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent2),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (done != null) _DoneBadge(done: done!),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0x14FFFFFF)),
          ),
          child,
        ],
      ),
    );
  }
}

class _DoneBadge extends StatelessWidget {
  const _DoneBadge({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: done ? accent2 : Colors.white24,
        ),
        const SizedBox(width: 4),
        Text(
          done ? '생성됨' : '미생성',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: done ? accent2 : Colors.white38,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: accent2,
      ),
    );
  }
}

class _PromptField extends StatelessWidget {
  const _PromptField({
    required this.controller,
    required this.hint,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String hint;

  /// 연동으로 값이 따라 들어오는 칸 — 보여주기만 하고 고칠 수 없다.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return TextField(
      controller: controller,
      readOnly: readOnly,
      minLines: 4,
      maxLines: 10,
      style: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: readOnly ? Colors.white54 : null,
      ),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: previewBg,
        border: const OutlineInputBorder(),
      ),
      onChanged: readOnly ? null : (_) => p.save(),
    );
  }
}

class _GenButton extends StatelessWidget {
  const _GenButton({
    required this.label,
    required this.icon,
    required this.busyKey,
    required this.onGen,
    this.enabled = true,
    this.disabledHint,
  });

  final String label;
  final IconData icon;
  final String busyKey;
  final VoidCallback onGen;
  final bool enabled;
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    final busy = StoryboardScope.of(context).isBusy(busyKey);
    final btn = FilledButton.icon(
      onPressed: (busy || !enabled) ? null : onGen,
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(busy ? '생성 중…' : label),
    );
    if (!enabled && disabledHint != null) {
      return Tooltip(message: disabledHint!, child: btn);
    }
    return btn;
  }
}

class _OutputBlock extends StatelessWidget {
  const _OutputBlock({
    required this.title,
    required this.path,
    required this.busyKey,
    this.isVideo = false,
    this.deleteTarget,
    this.trimTarget,
  });

  final String title;
  final String? path;
  final String busyKey;
  final bool isVideo;

  /// 지정하면 '삭제' 버튼이 붙는다 — 이 샷의 해당 생성물(프레임/영상)만 지운다.
  final ({Shot shot, GenMode mode})? deleteTarget;

  /// 지정하면 '트림' 버튼이 붙는다(영상 전용) — 프레임 단위로 보며 앞뒤를 잘라낸다.
  final Shot? trimTarget;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(title),
        const SizedBox(height: 6),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: previewBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: path != null
                  ? const Color(0x335BD1C0)
                  : const Color(0x14FFFFFF),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: OutputPreview(
            path: path,
            version: p.verOf(busyKey),
            busy: p.isBusy(busyKey),
            isVideo: isVideo,
            fit: BoxFit.contain,
            onOpen: path == null ? null : () => p.openFile(path!),
            // 이미지(시작·끝장면)는 클릭하면 확대 팝업 — 영상은 탭이 재생이라 제외.
            onImageTap: (isVideo || path == null)
                ? null
                : () => showImageZoomDialog(
                      context,
                      path: path!,
                      version: p.verOf(busyKey),
                      title: title,
                    ),
            // 영상은 그 자리서 재생하지 말고 팝업으로 크게 재생.
            onVideoTap: (isVideo && path != null)
                ? () => showVideoPlayDialog(context, path: path!, title: title)
                : null,
          ),
        ),
        // 결과가 위, 그걸 다루는 수단은 아래. 왼쪽에 열기·폴더·트림(넘치면 접힘),
        // 삭제만 오른쪽 끝으로 떼어 둔다 — 되돌릴 수 없는 동작이라 실수로 안 눌리게.
        if (path != null) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 2,
                  children: [
                    _MediaAction(
                      icon: Icons.open_in_new,
                      label: '열기',
                      onTap: () => p.openFile(path!),
                    ),
                    _MediaAction(
                      icon: Icons.folder_open_outlined,
                      label: '폴더',
                      onTap: () => p.revealInFinder(path!),
                    ),
                    if (trimTarget != null)
                      _MediaAction(
                        icon: Icons.content_cut,
                        label: '트림',
                        onTap: () async {
                          final seconds =
                              await showVideoTrimDialog(context, path: path!);
                          if (seconds != null) {
                            await p.applyTrim(trimTarget!, seconds);
                          }
                        },
                      ),
                  ],
                ),
              ),
              if (deleteTarget != null)
                _MediaAction(
                  icon: Icons.delete_outline,
                  label: '삭제',
                  color: Colors.redAccent,
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('$title 삭제'),
                        content: Text(
                          '이 샷의 $title을(를) 지웁니다.\n'
                          '파일도 함께 삭제되며 되돌릴 수 없습니다.\n\n'
                          '${path!.split('/').last}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('취소'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.redAccent),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('삭제'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await p.removeMedia(
                          deleteTarget!.shot, deleteTarget!.mode);
                    }
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 미리보기 아래 액션 버튼 하나(열기·폴더·트림·삭제) — 생김새를 한 군데로 모은다.
class _MediaAction extends StatelessWidget {
  const _MediaAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: color,
        ),
        icon: Icon(icon, size: 15),
        label: Text(label),
      );
}
