import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard

import '../../models/clip.dart';
import '../../models/shot.dart';
import '../../providers/storyboard_provider.dart';
import '../../services/api_service.dart';
import '../../services/movie_settings.dart';
import '../canvas/bgm_section.dart';
import '../canvas/canvas_view.dart' show editShotDialogue;
import '../common/output_preview.dart';
import '../ui.dart';

/// 오른쪽 인스펙터: 최상위 탭 [일반 | 샷 | 배경음].
///  - 일반: 씬 일반 설정(준비 중)
///  - 샷: 선택 샷 정보(제목·상태·메모·대사)
///  - 배경음: 씬 단위 BGM (원래 캔버스 하단에 있던 것)
/// 클립 편집 [장면|영상|공통]은 캔버스 하단의 [ClipEditorPanel]로 분리했다.
class InspectorPanel extends StatefulWidget {
  const InspectorPanel({super.key});

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
    length: 2,
    vsync: this,
    initialIndex: 1,
  ); // 기본 '배경음'

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: panelBg,
        border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            labelColor: accent2,
            indicatorColor: accent2,
            tabs: const [
              Tab(text: '일반'),
              Tab(text: '배경음'),
            ],
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _tab,
              builder: (context, _) => IndexedStack(
                index: _tab.index,
                children: const [_GeneralTab(), _BgmTab()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 일반 탭 — 씬 일반 설정(아직 내용 미정, 플레이스홀더).
class _GeneralTab extends StatelessWidget {
  const _GeneralTab();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    if (p.selectedScene == null) {
      return const Center(
        child: Text('씬을 선택하세요', style: TextStyle(color: Colors.white38)),
      );
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, color: Colors.white24, size: 40),
          SizedBox(height: 10),
          Text('씬 일반 설정 (준비 중)', style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}

/// 샷 탭 — 선택 샷 정보(제목·상태·메모·대사).
class _ShotInfoTab extends StatelessWidget {
  const _ShotInfoTab();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final shot = p.selectedShot;
    if (shot == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, color: Colors.white24, size: 40),
            SizedBox(height: 10),
            Text('왼쪽에서 샷을 선택하세요', style: TextStyle(color: Colors.white38)),
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
                'SHOT ${p.shots.indexOf(shot) + 1}',
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
            controller: p.titleCtrl(shot.id),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: '샷 제목 (선택)',
              isDense: true,
              filled: true,
              fillColor: previewBg,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => p.noteEdited(),
          ),
          const SizedBox(height: 12),
          _StatusSelector(shot: shot),
          const SizedBox(height: 14),
          _ShotNote(shotId: shot.id),
          const SizedBox(height: 14),
          _DialogueSummary(shot: shot),
        ],
      ),
    );
  }
}

/// 배경음 탭 — 씬 단위 BGM.
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
    return const SingleChildScrollView(child: BgmSection());
  }
}

/// 캔버스 하단 클립 편집 패널: 탭 [장면 | 영상 | 공통]. 선택 클립을 편집한다.
/// (탭 선택은 settings.inspectorTab에 유지 — 예전 인스펙터 탭 기억을 이어받음.)
class ClipEditorPanel extends StatefulWidget {
  const ClipEditorPanel({super.key});

  @override
  State<ClipEditorPanel> createState() => _ClipEditorPanelState();
}

class _ClipEditorPanelState extends State<ClipEditorPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _restoredTab = false;
  String? _lastShotId; // 선택 변경 감지용(샷만 선택 시 '샷' 탭으로 전환)
  String? _lastClipId;

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
      _lastShotId = p.selectedShotId;
      _lastClipId = p.selectedClipId;
      final saved = p.settings.inspectorTab.clamp(0, 3);
      if (saved != _tab.index) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tab.index = saved;
        });
      }
    } else if (_restoredTab) {
      // 선택 변경 감지: '샷만' 선택(클립 없음)되면 '샷' 탭으로 전환.
      final shotId = p.selectedShotId;
      final clipId = p.selectedClipId;
      if (shotId != _lastShotId || clipId != _lastClipId) {
        _lastShotId = shotId;
        _lastClipId = clipId;
        if (shotId != null && clipId == null && _tab.index != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _tab.animateTo(0);
          });
        }
      }
    }
    final clip = p.selectedClip;
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
              Tab(text: '샷'),
              Tab(text: '장면'),
              Tab(text: '영상'),
              Tab(text: '프롬프트'),
            ],
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _tab,
              builder: (context, _) => IndexedStack(
                index: _tab.index,
                children: [
                  const _ShotInfoTab(),
                  clip == null ? const _NoClip() : _SceneTab(clip: clip),
                  clip == null ? const _NoClip() : _VideoTab(clip: clip),
                  const _CommonTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 장면·영상 탭에 편집할 클립이 없을 때의 안내.
///  - 샷 미선택 → 샷을 먼저 선택
///  - 샷은 있으나 클립 0개 → 클립 추가(＋)
///  - 클립은 있으나 선택 안 됨 → 캔버스에서 클립을 클릭하도록 안내
class _NoClip extends StatelessWidget {
  const _NoClip();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final shot = p.selectedShot;
    if (shot == null) {
      return const _CenterNote(
        icon: Icons.touch_app_outlined,
        title: '샷을 선택하세요',
      );
    }
    if (shot.clips.isEmpty) {
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
              '이 샷에 클립이 없습니다',
              style: TextStyle(color: Colors.white38),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => p.addClip(shot),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('클립 추가'),
            ),
          ],
        ),
      );
    }
    return const _CenterNote(
      icon: Icons.ads_click,
      title: '클립을 선택하세요',
      subtitle: '캔버스에서 편집할 클립을 클릭하면\n이 샷의 장면·영상을 편집할 수 있어요',
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

/// 대사 요약 — 화자 + 텍스트 미리보기(+음성). 탭하면 편집 모달.
class _DialogueSummary extends StatelessWidget {
  const _DialogueSummary({required this.shot});

  final Shot shot;

  static const _voice = Color(0xFFE0678A);

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final d = shot.dialogue;
    final speaker = p.characterById(d?.speakerId);
    return InkWell(
      onTap: () => editShotDialogue(context, shot),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(
          color: const Color(0x12E0678A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x33E0678A)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.record_voice_over_outlined,
              size: 16,
              color: _voice,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: d == null
                  ? const Text(
                      '대사 추가 (없으면 무음 샷)',
                      style: TextStyle(fontSize: 12, color: _voice),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          d.speakerId == null
                              ? '내레이션'
                              : ((speaker?.name.trim().isNotEmpty ?? false)
                                    ? speaker!.name.trim()
                                    : '(이름 없음)'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _voice,
                          ),
                        ),
                        Text(
                          d.text.trim().isEmpty ? '(대사 없음)' : d.text.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ],
                    ),
            ),
            if (d?.hasVoice ?? false) ...[
              const Icon(Icons.graphic_eq, size: 13, color: accent2),
              const SizedBox(width: 3),
              Text(
                _fmt(d!.voiceSeconds),
                style: const TextStyle(fontSize: 10, color: accent2),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 14, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

String _fmt(double s) =>
    s == s.roundToDouble() ? '${s.toInt()}s' : '${s.toStringAsFixed(1)}s';

/// 장면 탭(클립): 샷 메모 + 인물참조 + 시작/끝장면 프레임.
class _SceneTab extends StatelessWidget {
  const _SceneTab({required this.clip});

  final VideoClip clip;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RefCharacterPicker(clip: clip),
          const SizedBox(height: 20),
          _FrameSection(
            title: '시작장면',
            controller: p.startCtrl(clip.id),
            hint: '클립의 첫 프레임(시작 장면)을 묘사',
            genLabel: '시작장면 생성',
            genIcon: Icons.first_page,
            path: clip.startImagePath,
            busyKey: p.busyKey(clip.id, GenMode.imageStart),
            onGen: () => p.gen(clip, GenMode.imageStart),
            onLoad: () => p.loadFrame(clip, GenMode.imageStart),
          ),
          const SizedBox(height: 16),
          _FrameSection(
            title: '끝장면',
            controller: p.endCtrl(clip.id),
            hint: '클립의 마지막 프레임(끝 장면)을 묘사',
            genLabel: '끝장면 생성',
            genIcon: Icons.last_page,
            path: clip.endImagePath,
            busyKey: p.busyKey(clip.id, GenMode.imageEnd),
            onGen: () => p.gen(clip, GenMode.imageEnd),
            onLoad: () => p.loadFrame(clip, GenMode.imageEnd),
          ),
        ],
      ),
    );
  }
}

/// 샷 제작 상태 선택 칩(준비/진행/검토/반려/완료). 사용자가 수동으로 정한다.
class _StatusSelector extends StatelessWidget {
  const _StatusSelector({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final st in ShotStatus.values)
          _StatusChoice(
            status: st,
            selected: shot.status == st,
            onTap: () => p.setShotStatus(shot, st),
          ),
      ],
    );
  }
}

class _StatusChoice extends StatelessWidget {
  const _StatusChoice({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final ShotStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.22) : const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? c : const Color(0x1AFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              statusIcon(status),
              size: 12,
              color: selected ? c : Colors.white38,
            ),
            const SizedBox(width: 4),
            Text(
              status.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? c : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 샷 메모(특이사항). 프롬프트와 무관한 자유 기록 — 생성에 쓰이지 않는다.
class _ShotNote extends StatelessWidget {
  const _ShotNote({required this.shotId});

  final String shotId;

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
            controller: p.noteCtrl(shotId),
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

/// 인물 참조 피커(클립). 선택 시 이 클립의 장면 생성이 인물 대표사진을 레퍼런스로 정체성 유지 생성.
class _RefCharacterPicker extends StatelessWidget {
  const _RefCharacterPicker({required this.clip});

  final VideoClip clip;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final chars = p.characters;
    final sel = clip.refCharacterIds;
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
                        : (_) => p.toggleClipRefCharacter(clip, c.id),
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

/// 클립별 영상 길이(초) 슬라이더. 1~15초.
class _SecondsField extends StatefulWidget {
  const _SecondsField({super.key});

  @override
  State<_SecondsField> createState() => _SecondsFieldState();
}

class _SecondsFieldState extends State<_SecondsField> {
  late double _val =
      (StoryboardScope.read(context).selectedClip?.videoSeconds ?? 5)
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
              final c = p.selectedClip;
              if (c != null) p.setClipSeconds(c, v.round());
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

/// LoRA URL 입력 + 강도 슬라이더 (씬 단위 — 같은 씬 클립들끼리 공유).
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

/// 영상 탭(클립): 설정(해상도·LoRA) + 생성 영상.
class _VideoTab extends StatelessWidget {
  const _VideoTab({required this.clip});

  final VideoClip clip;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final c = clip;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: 16),
          _GroupCard(
            icon: Icons.movie_outlined,
            title: '생성 영상',
            done: c.videoPath != null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionLabel('프롬프트'),
                const SizedBox(height: 6),
                _PromptField(
                  controller: p.videoCtrl(c.id),
                  hint: '움직임/카메라 등 영상 묘사',
                ),
                const SizedBox(height: 14),
                _SectionLabel('길이 (초 · 이 클립)'),
                const SizedBox(height: 6),
                _SecondsField(key: ValueKey('sec_${c.id}')),
                const SizedBox(height: 14),
                _OutputBlock(
                  title: '미리보기',
                  path: c.videoPath,
                  busyKey: p.busyKey(c.id, GenMode.videoLow),
                  isVideo: true,
                ),
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
        ],
      ),
    );
  }
}

/// 공통 탭: 프로젝트/씬 공통 프롬프트.
class _CommonTab extends StatelessWidget {
  const _CommonTab();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupCard(
            icon: Icons.public,
            title: '프로젝트 공통 프롬프트',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '이 프로젝트의 모든 클립 생성에 함께 붙습니다.',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 8),
                _ProjectCommonField(key: ValueKey('proj_${p.savePath}')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _GroupCard(
            icon: Icons.movie_filter_outlined,
            title: '씬 공통 프롬프트',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '이 씬의 모든 클립 생성에 함께 붙습니다.',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 8),
                if (sc == null)
                  const Text(
                    '씬을 선택하세요',
                    style: TextStyle(color: Colors.white38),
                  )
                else
                  _SceneCommonField(key: ValueKey('common_${sc.id}')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '생성 시 [프로젝트] + [씬] + [클립] 순으로 합쳐집니다.',
            style: TextStyle(fontSize: 11, color: Colors.white30),
          ),
        ],
      ),
    );
  }
}

class _ProjectCommonField extends StatefulWidget {
  const _ProjectCommonField({super.key});

  @override
  State<_ProjectCommonField> createState() => _ProjectCommonFieldState();
}

class _ProjectCommonFieldState extends State<_ProjectCommonField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: StoryboardScope.read(context).projectCommonPrompt,
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
      onChanged: (v) => StoryboardScope.read(context).setProjectCommonPrompt(v),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: const InputDecoration(
        hintText: '예: cinematic, film grain, 일관된 아트 스타일…',
        isDense: true,
        filled: true,
        fillColor: previewBg,
        border: OutlineInputBorder(),
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
    required this.hint,
    required this.genLabel,
    required this.genIcon,
    required this.path,
    required this.busyKey,
    required this.onGen,
    required this.onLoad,
  });

  final String title;
  final TextEditingController controller;
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
    return _GroupCard(
      icon: genIcon,
      title: title,
      done: path != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel('프롬프트'),
          const SizedBox(height: 6),
          _PromptField(controller: controller, hint: hint),
          const SizedBox(height: 14),
          _OutputBlock(title: '미리보기', path: path, busyKey: busyKey),
          const SizedBox(height: 10),
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
  const _PromptField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return TextField(
      controller: controller,
      minLines: 4,
      maxLines: 10,
      style: const TextStyle(fontSize: 14, height: 1.4),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: previewBg,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => p.save(),
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
  });

  final String title;
  final String? path;
  final String busyKey;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SectionLabel(title),
            const Spacer(),
            if (path != null) ...[
              TextButton.icon(
                onPressed: () => p.openFile(path!),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('열기'),
              ),
              TextButton.icon(
                onPressed: () => p.revealInFinder(path!),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('폴더'),
              ),
              TextButton.icon(
                onPressed: () => p.exportFile(path!),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('내보내기'),
              ),
            ],
          ],
        ),
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
          ),
        ),
      ],
    );
  }
}
