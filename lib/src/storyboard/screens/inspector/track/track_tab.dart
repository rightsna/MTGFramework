part of '../inspector_panel.dart';

/// 트랙 탭 — 씬의 **트랙별** 설정을 한곳에: 기본 성우 · LoRA · 무비 내보내기.
/// (트랙 이름·백엔드·삭제는 캔버스의 트랙 줄 머리말에서. 여기선 생성 설정과 내보내기를 다룬다.)
class _TrackTab extends StatelessWidget {
  const _TrackTab();

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
          const Text(
            'LoRA와 기본 성우는 **트랙마다 따로**입니다 — 트랙별로 다른 조건으로 뽑아 비교하세요.\n'
            '내보내기는 그 트랙의 영상에 대사 음성·효과음·배경음을 합쳐 하나의 mp4로 굽습니다.',
            style: TextStyle(fontSize: 11.5, color: Colors.white38, height: 1.45),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < sc.tracks.length; i++) ...[
            _TrackCard(track: sc.tracks[i], isBase: i == 0),
            const SizedBox(height: 14),
          ],
          OutlinedButton.icon(
            onPressed: p.addTrack,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('트랙 추가'),
            style: OutlinedButton.styleFrom(
              foregroundColor: accent2,
              side: const BorderSide(color: Color(0x338B7BFF)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 트랙 하나의 카드 — 머리말(이름·백엔드·진행도·내보내기) + 기본 성우 + LoRA.
class _TrackCard extends StatelessWidget {
  const _TrackCard({required this.track, required this.isBase});

  final VideoTrack track;
  final bool isBase;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final exporting = p.isBusy(p.exportBusyKey(track));
    final canExport = p.trackHasVideo(track);
    return _GroupCard(
      icon: isBase ? Icons.star_rounded : Icons.layers_outlined,
      title: p.trackLabel(track),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(track.backend.shortLabel,
                    style:
                        const TextStyle(fontSize: 10.5, color: Colors.white70)),
              ),
              const SizedBox(width: 8),
              Text('영상 ${track.filledCount}/${track.shotCount}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 12),
          // 무비 내보내기 — 이 트랙의 영상 + 대사 음성·효과음·배경음 합성.
          FilledButton.tonalIcon(
            onPressed: (exporting || !canExport)
                ? null
                : () => p.exportTrackMovie(track),
            icon: exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.movie_outlined, size: 18),
            label: Text(exporting
                ? '내보내는 중…'
                : canExport
                    ? '무비 내보내기 (음성·효과음·배경음 합성)'
                    : '내보낼 영상이 없습니다'),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          const SizedBox(height: 12),
          _SectionLabel('재생 배속'),
          const SizedBox(height: 2),
          const Text(
            '미리보기와 내보내기에 똑같이 걸립니다. 영상·대사·효과음이 함께 빨라지고 '
            '길이는 1/배속이 됩니다(배경음은 그대로 전체에 깔립니다).',
            style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.4),
          ),
          const SizedBox(height: 6),
          _TrackSpeedField(
              key: ValueKey('track_speed_${track.id}'), track: track),
          const SizedBox(height: 16),
          _SectionLabel('기본 성우 (내레이션)'),
          const SizedBox(height: 2),
          const Text(
            '화자를 지정하지 않은 대사(내레이션)에 쓰는 보이스입니다. '
            '화자에 목소리가 있으면 그 화자 보이스가 우선합니다.',
            style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.4),
          ),
          const SizedBox(height: 6),
          _TrackDefaultVoiceField(
              key: ValueKey('track_voice_${track.id}'), track: track),
          const SizedBox(height: 16),
          _SectionLabel('LoRA (LTX-2.3용)'),
          const SizedBox(height: 6),
          _TrackLoraField(key: ValueKey('track_lora_${track.id}'), track: track),
        ],
      ),
    );
  }
}
