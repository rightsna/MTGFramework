part of 'inspector_panel.dart';

/// 장면 탭 — 샷의 시작/끝 프레임과 그 부속(생성 방식 토글·인물참조·프레임 섹션).

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
    // 따라가는 샷의 프레임은 기준 트랙 것을 함께 쓴다 — 여기서 고치면 비교 조건이 어긋나므로
    // 통째로 잠근다(위 띠의 '이 트랙에서 수정'으로 분리한 뒤에 손댄다).
    final locked = shot.inherits;
    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 장면 메모 — 이 샷의 프레임 작업용. 영상 탭에는 별도의 영상 메모가 있다.
          _ShotNote(controller: p.shotNoteCtrl(shot.id)),
          const SizedBox(height: 14),
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
          // 해상도(프레임·영상)는 씬 탭의 '생성 설정'에 모아 뒀다 — 여기선 이 샷의 것만 다룬다.
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
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TrackLinkBar(shot: shot),
          _LockIfInherited(locked: locked, child: body),
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
                    label: Text(c.name.isEmpty ? '(이름 없음)' : c.name,
                        style: _chipLabel),
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
          _PromptPair(
            label: '프롬프트',
            controller: controller,
            koController: koController,
            hint: linked ? '앞 샷의 끝장면 프롬프트가 들어옵니다' : hint,
            readOnly: linked,
            trailing: IconButton(
              tooltip: '프롬프트 복사 (씬 공통 포함)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                // 생성에 실제로 들어가는 형태 그대로 — 씬 공통 + 이 프레임 프롬프트.
                final t =
                    p.composedFramePrompt(shot, controller.text, mode).trim();
                if (t.isEmpty) {
                  p.messenger?.call('복사할 프롬프트가 없습니다');
                  return;
                }
                Clipboard.setData(ClipboardData(text: t));
                p.messenger?.call('$title 프롬프트 복사됨 (씬 공통 포함)');
              },
            ),
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
