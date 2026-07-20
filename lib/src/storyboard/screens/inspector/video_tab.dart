part of 'inspector_panel.dart';

/// 영상 탭 — 샷의 영상 생성과 그 설정(길이·LoRA).

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
    // 따라가는 샷은 **내용은 잠기고 영상 생성만 열려 있다** — 트랙을 나눈 이유가 그것뿐이라서.
    final locked = c.inherits;
    final backend = p.backendOf(c);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TrackLinkBar(shot: c),
          // 영상 메모 — 장면 탭 메모와 별개다(영상에 적을 말은 프레임에 적을 말과 다르다).
          _ShotNote(controller: p.videoNoteCtrl(c.id), readOnly: locked),
          const SizedBox(height: 16),
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
                  // 아직 이 트랙에서 안 뽑았으면 기준 트랙 영상을 그대로 보여 준다.
                  path: p.videoPathOf(c),
                  busyKey: p.busyKey(c.id, GenMode.videoLow),
                  isVideo: true,
                  // 트림·삭제는 **이 트랙에서 뽑은 영상**에만 — 빌려 보여 주는 중이면
                  // 그 파일은 기준 트랙 것이라 손대면 안 된다.
                  deleteTarget: p.hasOwnVideo(c)
                      ? (shot: c, mode: GenMode.videoLow)
                      : null,
                  trimTarget: p.hasOwnVideo(c) ? c : null,
                ),
                if (!p.hasOwnVideo(c) && p.videoPathOf(c) != null) ...[
                  const SizedBox(height: 6),
                  Text('${p.trackLabel(p.tracks.first)}의 영상입니다 — 아래에서 뽑으면 이 트랙 것이 됩니다',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0x88FFFFFF))),
                ],
                const SizedBox(height: 14),
                _SectionLabel('프롬프트'),
                const SizedBox(height: 6),
                _PromptField(
                  controller: p.videoCtrl(c.id),
                  hint: '움직임/카메라 등 영상 묘사',
                  readOnly: locked,
                ),
                const SizedBox(height: 10),
                _SectionLabel('프롬프트 번역 (한국어)'),
                const SizedBox(height: 6),
                _PromptField(
                  controller: p.videoKoCtrl(c.id),
                  hint: '위 프롬프트를 한국어로 — 확인용이고 생성엔 안 쓰임',
                  readOnly: locked,
                ),
                const SizedBox(height: 10),
                _SectionLabel('네거티브 프롬프트'),
                const SizedBox(height: 6),
                _PromptField(
                  controller: p.videoNegCtrl(c.id),
                  hint: '빼고 싶은 것만 (예: hand, text, watermark) — '
                      '위 프롬프트에 "no hand"처럼 쓰면 오히려 나온다',
                  readOnly: locked,
                ),
                const SizedBox(height: 14),
                _SectionLabel('길이 (초 · 이 샷)'),
                const SizedBox(height: 6),
                IgnorePointer(
                  ignoring: locked,
                  child: Opacity(
                    opacity: locked ? 0.5 : 1,
                    child: _SecondsField(key: ValueKey('sec_${c.id}')),
                  ),
                ),
                const SizedBox(height: 10),
                // 백엔드는 **트랙이 정한다** — 같은 콘티를 트랙별로 다른 백엔드로 뽑아 비교하는 게
                // 트랙의 전부다(바꾸려면 트랙 줄의 ⋯ 메뉴에서).
                _GenButton(
                  label: '${backend.label}로 생성',
                  icon: backend == VideoBackend.veo
                      ? Icons.auto_awesome_outlined
                      : Icons.movie_outlined,
                  busyKey: p.busyKey(c.id, GenMode.videoLow),
                  onGen: () => p.gen(c, GenMode.videoLow),
                  enabled: p.videoReadyOf(backend),
                  disabledHint: p.videoBlockReasonOf(backend),
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
                        label: Text(r.label, style: _chipLabel),
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
