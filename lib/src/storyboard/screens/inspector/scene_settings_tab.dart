part of 'inspector_panel.dart';

/// 씬 탭 — 선택 씬 전체 설정(제목·생성 설정·일괄 생성·삭제). 배경음은 별도 '배경음' 탭.

/// 씬 탭 — 선택 씬의 것들을 한곳에: 제목 · 생성 설정 · 영상 일괄 생성 · 삭제.
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
          // 씬 메모 — 다른 탭과 마찬가지로 최상단.
          _ShotNote(
              key: ValueKey('scene_note_${sc.id}'),
              controller: p.sceneNoteCtrl(sc.id)),
          const SizedBox(height: 16),
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
          // 해상도·LoRA는 전부 **씬 단위** — 씬마다 따로 저장된다(다른 씬에 영향 없음).
          _GroupCard(
            icon: Icons.tune,
            title: '생성 설정',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionLabel('프레임 해상도 (시작·끝 장면)'),
                const SizedBox(height: 2),
                const Text(
                  'FE2V 입력이라 영상과 비율을 맞추세요. '
                  '인물참조가 있는 샷은 무시되고 참조 사진 크기로 나옵니다.',
                  style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.4),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in ImageRes.values)
                      ChoiceChip(
                        label: Text(r.label, style: _chipLabel),
                        selected: sc.imageRes == r,
                        onSelected: (_) => p.setImageRes(r),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionLabel('영상 해상도'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in VideoRes.values)
                      ChoiceChip(
                        label: Text(r.label, style: _chipLabel),
                        selected: sc.videoRes == r,
                        onSelected: (_) => p.setVideoRes(r),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionLabel('LoRA (씬 단위 · LTX-2.3용)'),
                const SizedBox(height: 6),
                _LoraField(key: ValueKey('lora_${sc.id}')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 기본 성우 — 화자 미지정(내레이션) 대사에 쓰는 보이스. 씬 단위.
          _GroupCard(
            icon: Icons.record_voice_over_outlined,
            title: '기본 성우 (내레이션)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '화자를 지정하지 않은 대사(내레이션)에 쓰는 보이스입니다. '
                  '화자에 목소리가 있으면 그 화자 보이스가 우선합니다.',
                  style:
                      TextStyle(fontSize: 11, color: Colors.white38, height: 1.4),
                ),
                const SizedBox(height: 8),
                _SceneDefaultVoiceField(key: ValueKey('scene_voice_${sc.id}')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _GroupCard(
            icon: Icons.auto_awesome_motion_outlined,
            title: '영상 일괄 생성',
            child: VideoBatch(),
          ),
          // 배경음은 별도 '배경음' 탭으로 옮겼다.
          const SizedBox(height: 24),
          // 구조는 두고 생성물만 비우기 — 다시 뽑기 전 초기화용.
          OutlinedButton.icon(
            onPressed: () async {
              final shots = [for (final b in sc.beats) ...b.shots];
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('미디어 모두 삭제'),
                  content: Text(
                    '"${sc.title.trim().isEmpty ? '(제목 없음)' : sc.title.trim()}" 씬의 '
                    '생성물을 모두 지웁니다 — 샷 ${shots.length}개의 시작·끝 프레임과 영상, '
                    '대사 음성, 배경음.\n'
                    '${sc.tracks.length > 1 ? '트랙 ${sc.tracks.length}개에서 뽑은 영상이 전부 사라집니다.\n' : ''}'
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
          // 참조가 끊긴 고아 미디어를 프로젝트 전체에서 쓸어 담는다(옛 삭제로 남은 파일 정리).
          OutlinedButton.icon(
            onPressed: () async {
              final n = await p.sweepOrphanMedia();
              p.messenger?.call(n == 0
                  ? '정리할 고아 미디어가 없습니다'
                  : '고아 미디어 $n개를 삭제했습니다');
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0x33FFFFFF)),
            ),
            icon: const Icon(Icons.auto_delete_outlined, size: 18),
            label: const Text('고아 미디어 정리 (프로젝트 전체)'),
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
                    '비트 ${sc.beats.length}개 · 샷 ${sc.shotCount}개가 함께 사라집니다. '
                    '되돌릴 수 없습니다.\n\n'
                    '(이 씬의 미디어 파일도 함께 삭제됩니다)',
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

/// 씬 기본 성우 선택 — 일레븐랩스 보이스 목록에서 하나 고른다(내레이션·화자 미지정용).
/// 인물 관리의 보이스 드롭다운과 같은 방식(설정의 키로 목록을 받아온다).
class _SceneDefaultVoiceField extends StatefulWidget {
  const _SceneDefaultVoiceField({required super.key});

  @override
  State<_SceneDefaultVoiceField> createState() =>
      _SceneDefaultVoiceFieldState();
}

class _SceneDefaultVoiceFieldState extends State<_SceneDefaultVoiceField> {
  List<ElevenVoice> _voices = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    final key = StoryboardScope.read(context).settings.elevenKey.trim();
    if (key.isEmpty) return;
    setState(() => _loading = true);
    try {
      final voices = await ElevenLabsService(key).listVoices();
      if (!mounted) return;
      setState(() {
        _voices = voices;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    final currentId = sc?.defaultVoiceId.trim() ?? '';

    if (p.settings.elevenKey.trim().isEmpty) {
      return const Text('설정에서 일레븐랩스 키를 넣어야 성우를 고를 수 있어요',
          style: TextStyle(fontSize: 12, color: Colors.orangeAccent));
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Row(
        children: [
          Expanded(
            child: Text('보이스 목록 실패: $_error',
                style:
                    const TextStyle(fontSize: 12, color: Colors.redAccent)),
          ),
          TextButton(onPressed: _loadVoices, child: const Text('다시 시도')),
        ],
      );
    }

    final ids = _voices.map((v) => v.id).toSet();
    // 저장된 성우가 목록에 없으면(다른 계정 등) 항목을 하나 끼워 값이 유지되게.
    final missingCurrent = currentId.isNotEmpty && !ids.contains(currentId);

    return DropdownButtonFormField<String?>(
      initialValue: currentId.isEmpty ? null : currentId,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('없음 (내레이션 음성 생성 안 함)'),
        ),
        if (missingCurrent)
          DropdownMenuItem<String?>(
            value: currentId,
            child: Text(
              '${sc!.defaultVoiceName.isEmpty ? currentId : sc.defaultVoiceName} (목록에 없음)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        for (final v in _voices)
          DropdownMenuItem<String?>(
            value: v.id,
            child: Text(
              '${v.name}${v.category == null ? '' : '  · ${v.category}'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (id) {
        if (id == null) {
          p.setSceneDefaultVoice('', '');
        } else {
          final match = _voices.where((v) => v.id == id);
          p.setSceneDefaultVoice(id, match.isEmpty ? '' : match.first.name);
        }
      },
    );
  }
}

/// 배경음 탭 — 선택 씬의 BGM(스타일·길이·생성/불러오기·재생). 씬 탭에서 분리했다.
class _BgmTab extends StatelessWidget {
  const _BgmTab();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    if (p.selectedScene == null) {
      return const Center(
        child: Text('씬을 선택하세요', style: TextStyle(color: Colors.white38)),
      );
    }
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: BgmSection(),
    );
  }
}
