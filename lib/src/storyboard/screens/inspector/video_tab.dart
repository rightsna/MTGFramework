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
  const _LoraField({required super.key});

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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TrackLinkBar(shot: c),
          // 영상 메모 — 장면 탭 메모와 별개다(영상에 적을 말은 프레임에 적을 말과 다르다).
          _LockIfInherited(
              locked: locked,
              child: _ShotNote(controller: p.videoNoteCtrl(c.id))),
          const SizedBox(height: 16),
          // 결과(영상)가 위, 그걸 만드는 수단(프롬프트·생성) 다음, 설정은 맨 아래.
          _GroupCard(
            icon: Icons.movie_outlined,
            title: '영상',
            done: c.videoPath != null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 생성 중이면 진행 상태를 영상칸 위에 **고정**으로 — 반복 스낵바 대신.
                if (p.isBusy(p.busyKey(c.id, GenMode.videoLow))) ...[
                  _GenProgressBanner(
                    text: p.progressOf(p.busyKey(c.id, GenMode.videoLow)) ??
                        '생성 준비 중…',
                  ),
                  const SizedBox(height: 8),
                ],
                // 영상이 있으면 영상을, 없으면 **생성에 쓸 장면**을 대신 보여준다
                // (FE2V면 시작·끝 두 장, I2V면 시작 한 장) — 무엇으로 뽑는지 바로 보이게.
                if (c.videoPath != null)
                  _OutputBlock(
                    title: '영상',
                    path: c.videoPath,
                    busyKey: p.busyKey(c.id, GenMode.videoLow),
                    isVideo: true,
                    deleteTarget: (shot: c, mode: GenMode.videoLow),
                    trimTarget: c,
                  )
                else
                  _VideoInputFrames(shot: c),
                const SizedBox(height: 14),
                // 내용(프롬프트·길이)은 따라가는 동안 잠긴다. 생성 버튼은 그 아래에 열려 있다.
                _LockIfInherited(
                  locked: locked,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PromptPair(
                        label: '프롬프트',
                        controller: p.videoCtrl(c.id),
                        koController: p.videoKoCtrl(c.id),
                        hint: '움직임/카메라 등 영상 묘사',
                      ),
                      const SizedBox(height: 10),
                      _SectionLabel('네거티브 프롬프트'),
                      const SizedBox(height: 6),
                      _PromptField(
                        controller: p.videoNegCtrl(c.id),
                        hint: '빼고 싶은 것만 (예: hand, text, watermark) — '
                            '위 프롬프트에 "no hand"처럼 쓰면 오히려 나온다',
                      ),
                      const SizedBox(height: 14),
                      _SectionLabel('길이 (초 · 이 샷)'),
                      const SizedBox(height: 6),
                      _SecondsField(key: ValueKey('sec_${c.id}')),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 백엔드는 **누를 때 고른다** — 트랙은 결과가 들어가는 자리일 뿐이라
                // 어느 줄에서든 아무 백엔드로나 뽑을 수 있다(자체 서버로 두 줄을 견줘도 된다).
                for (final b in VideoBackend.values) ...[
                  _GenButton(
                    label: '${b.label}로 생성',
                    icon: b == VideoBackend.veo
                        ? Icons.auto_awesome_outlined
                        : Icons.movie_outlined,
                    busyKey: p.busyKey(c.id, GenMode.videoLow),
                    onGen: () => p.gen(c, GenMode.videoLow, backend: b),
                    enabled: p.videoReadyOf(b),
                    disabledHint: p.videoBlockReasonOf(b),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          // 해상도·LoRA는 씬 단위라 씬 탭의 '생성 설정'으로 옮겼다.
        ],
      ),
    );
  }
}

/// 영상이 아직 없을 때 영상칸에 대신 놓는 **생성 입력 장면** 미리보기.
/// FE2V면 시작·끝 두 장, I2V면 시작 한 장. 탭하면 확대. 읽기만 하고 편집은 장면 탭에서.
class _VideoInputFrames extends StatelessWidget {
  const _VideoInputFrames({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final start = p.startPathOf(shot); // 연동 중이면 앞 샷의 끝장면
    final end = shot.i2v ? null : shot.endImagePath;

    Widget frame(String label, String? path, GenMode mode) {
      final key = p.busyKey(shot.id, mode);
      return Expanded(
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: previewBg,
            borderRadius: BorderRadius.circular(10),
            // 영상이 아니라 장면을 대신 보여주는 중 — **빨간 테두리**로 아직 미생성임을 강조.
            border: Border.all(color: Colors.redAccent, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: OutputPreview(
            path: path,
            version: p.verOf(key),
            busy: p.isBusy(key),
            fit: BoxFit.contain,
            onImageTap: path == null
                ? null
                : () => showImageZoomDialog(context,
                    path: path, version: p.verOf(key), title: label),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const _SectionLabel('영상'),
            const SizedBox(width: 8),
            const Text('아직 없음 — 생성에 쓸 장면',
                style: TextStyle(fontSize: 11, color: Color(0x66FFFFFF))),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            frame('시작', start, GenMode.imageStart),
            if (!shot.i2v) ...[
              const SizedBox(width: 8),
              frame('끝', end, GenMode.imageEnd),
            ],
          ],
        ),
      ],
    );
  }
}

/// 생성 중 진행 상태를 영상칸 위에 고정으로 보여주는 배너 — 스피너 + 문구.
class _GenProgressBanner extends StatelessWidget {
  const _GenProgressBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent2.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent2.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: accent2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
