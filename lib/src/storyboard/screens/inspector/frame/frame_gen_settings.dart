part of '../inspector_panel.dart';

/// 이 샷의 **영상 생성 방식**(FE2V/I2V/스틸컷/IA2V) — 프레임을 어떻게 쓸지가 여기서 갈린다.
///  - FE2V/I2V: 같은 모델·같은 그래프고 끝 프레임을 박느냐만 다르다. FE2V는 끝 그림이 정해지는
///    대신 양끝이 멀면 중간이 깨지고, I2V는 끝이 자유로운 대신 어디로 갈지 통제가 안 된다.
///  - IA2V: 시작 한 장 + 그 비트의 **대사 음성**을 조건으로 넣어 입까지 움직인다(자체 서버 전용).
class _FrameGenSettings extends StatelessWidget {
  const _FrameGenSettings({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final mode = p.shotVideoMode(shot);
    final effect = p.shotStillEffect(shot);
    return _GroupCard(
      icon: Icons.tune,
      title: '생성 방식',
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
                desc: '시작·끝 두 장',
                selected: mode == VideoMode.fe2v,
                onTap: () => p.setVideoMode(shot, VideoMode.fe2v),
              ),
              const SizedBox(width: 8),
              _VideoModeCard(
                icon: Icons.play_arrow_rounded,
                title: 'I2V',
                desc: '시작 한 장',
                selected: mode == VideoMode.i2v,
                onTap: () => p.setVideoMode(shot, VideoMode.i2v),
              ),
              const SizedBox(width: 8),
              _VideoModeCard(
                icon: Icons.photo_outlined,
                title: '스틸컷',
                desc: '사진 → 영상',
                selected: mode == VideoMode.still,
                onTap: () => p.setVideoMode(shot, VideoMode.still),
              ),
              const SizedBox(width: 8),
              // IA2V — 시작 한 장 + **그 비트의 대사 음성**. 그 음성에 맞춰 입이 움직인다.
              _VideoModeCard(
                icon: Icons.record_voice_over_outlined,
                title: 'IA2V',
                desc: '음성에 입 맞춤',
                selected: mode == VideoMode.ia2v,
                onTap: () => p.setVideoMode(shot, VideoMode.ia2v),
              ),
            ],
          ),
          // 스틸컷일 때만 켄번스(줌) 효과를 고른다.
          if (mode == VideoMode.still) ...[
            const SizedBox(height: 12),
            const _SectionLabel('효과 (켄번스)'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in StillEffect.values)
                  ChoiceChip(
                    label: Text(e.label, style: _chipLabel),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    selected: effect == e,
                    onSelected: (_) => p.setStillEffect(shot, e),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
