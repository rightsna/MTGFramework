part of 'inspector_panel.dart';

/// 프레임 탭 — 샷의 시작/끝 프레임과 그 부속(생성 방식 토글·인물참조·프레임 섹션).

/// 이 샷의 **프레임 생성 설정** — 영상 방식(FE2V/I2V)과 인물 참조를 한 카드에 묶는다.
/// 둘 다 "프레임을 어떻게 뽑을지"의 입력이라 한자리에 있는 게 읽기 쉽다.
///  - FE2V/I2V: 같은 모델·같은 그래프고 끝 프레임을 박느냐만 다르다. FE2V는 끝 그림이 정해지는
///    대신 양끝이 멀면 중간이 깨지고, I2V는 끝이 자유로운 대신 어디로 갈지 통제가 안 된다.
///  - 인물 참조: 선택 인물(최대 3)의 대표사진을 레퍼런스로 정체성 유지 생성(FireRed 멀티).
class _FrameGenSettings extends StatelessWidget {
  const _FrameGenSettings({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final chars = p.characters;
    final sel = shot.refCharacterIds;
    final atCap = sel.length >= 3;
    return _GroupCard(
      icon: Icons.tune,
      title: '프레임 설정',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('영상 생성 방식'),
          const SizedBox(height: 6),
          Row(
            children: [
              _VideoModeCard(
                icon: Icons.compare_arrows,
                title: 'FE2V',
                desc: '시작·끝 두 장 고정',
                selected: !shot.i2v,
                onTap: () => p.setI2v(shot, false),
              ),
              const SizedBox(width: 8),
              _VideoModeCard(
                icon: Icons.play_arrow_rounded,
                title: 'I2V',
                desc: '시작 한 장, 끝은 자유',
                selected: shot.i2v,
                onTap: () => p.setI2v(shot, true),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          const SizedBox(height: 12),
          Row(
            children: [
              const _SectionLabel('인물 참조'),
              const Spacer(),
              Text('${sel.length}/3',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 6),
          if (chars.isEmpty)
            const Text('인물 관리에서 인물을 먼저 추가하세요',
                style: TextStyle(fontSize: 11, color: Colors.white38))
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final c in chars)
                  FilterChip(
                    showCheckmark: false,
                    // 칩 안쪽 좌우 여백을 좁혀 촘촘하게.
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    label: Text(c.name.isEmpty ? '(이름 없음)' : c.name,
                        style: _chipLabel),
                    selected: sel.contains(c.id),
                    onSelected: (atCap && !sel.contains(c.id))
                        ? null
                        : (_) => p.toggleShotRefCharacter(shot, c.id),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              sel.isEmpty
                  ? '선택하면 각 인물의 대표이미지로 정체성 유지 생성 (FireRed 멀티)'
                  : '선택 인물 대표사진을 레퍼런스로 정체성 유지 생성 (FireRed 멀티)',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }
}

/// 영상 생성 방식 옵션 카드 하나 — 선택되면 강조 테두리+틴트. 둘을 나란히 놓아 고른다.
class _VideoModeCard extends StatelessWidget {
  const _VideoModeCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : const Color(0x66FFFFFF);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.14) : const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accent : const Color(0x1FFFFFFF),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 5),
                  Text(title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: selected ? Colors.white : const Color(0xBBFFFFFF),
                      )),
                  const Spacer(),
                  if (selected)
                    const Icon(Icons.check_circle, size: 12, color: accent),
                ],
              ),
              const SizedBox(height: 2),
              Text(desc,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.white54, height: 1.25)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 프레임 탭(샷): 프레임 메모 + 생성 설정 + 시작/끝 프레임.
class _FrameTab extends StatelessWidget {
  const _FrameTab({required this.shot});

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
          // 프레임 메모 — 이 샷의 프레임 작업용. 영상 탭에는 별도의 영상 메모가 있다.
          _ShotNote(controller: p.shotNoteCtrl(shot.id)),
          const SizedBox(height: 14),
          // 이 샷의 프레임 생성 설정 — 영상 방식(FE2V/I2V) + 인물 참조를 한 카드에.
          _FrameGenSettings(shot: shot),
          const SizedBox(height: 14),
          // 결과(프레임)가 위, 그 생성에 쓰이는 설정(인물참조)은 아래.
          _FrameSection(
            title: '시작 프레임',
            controller: p.startCtrl(shot.id),
            koController: p.startKoCtrl(shot.id),
            hint: '샷의 첫 프레임(시작)을 묘사',
            genLabel: '시작 프레임 생성',
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
              title: '끝 프레임',
              controller: p.endCtrl(shot.id),
              koController: p.endKoCtrl(shot.id),
              hint: '샷의 마지막 프레임(끝)을 묘사',
              genLabel: '끝 프레임 생성',
              genIcon: Icons.last_page,
              path: shot.endImagePath,
              busyKey: p.busyKey(shot.id, GenMode.imageEnd),
              onGen: () => p.gen(shot, GenMode.imageEnd),
              onLoad: () => p.loadFrame(shot, GenMode.imageEnd),
              shot: shot,
              mode: GenMode.imageEnd,
            ),
          ],
          // 인물 참조는 위 '프레임 설정' 카드로 합쳤다.
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
    // 연동은 시작 프레임에만 있다 — 끝 프레임은 물려받을 대상이 아니라 만드는 것이다.
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
            // 연동 중인 시작 프레임은 앞 샷의 끝 프레임 파일 그 자체다 — 여기서 지우면 앞 샷이 날아간다.
            // 지우려면 연동을 먼저 끄거나, 앞 샷의 끝 프레임에서 지워야 한다.
            deleteTarget: linked ? null : (shot: shot, mode: mode),
          ),
          const SizedBox(height: 14),
          _PromptPair(
            label: '프롬프트',
            controller: controller,
            koController: koController,
            hint: linked ? '앞 샷의 끝 프레임 프롬프트가 들어옵니다' : hint,
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

/// 시작 프레임 연동 토글 — 켜면 앞 샷의 끝 프레임(이미지·프롬프트)이 따라 들어오고 편집이 잠긴다.
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
                  '앞 샷 끝 프레임 이어받기',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  on
                      ? (prevHasEnd
                          ? '$prevName의 끝 프레임 · 바뀌면 같이 바뀝니다'
                          : '$prevName에 끝 프레임이 아직 없습니다 — 만들면 들어옵니다')
                      : '이 샷의 시작 프레임을 직접 만듭니다',
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
