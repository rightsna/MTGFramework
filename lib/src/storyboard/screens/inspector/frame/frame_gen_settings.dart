part of '../inspector_panel.dart';

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
