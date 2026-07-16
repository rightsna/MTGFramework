import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/clip.dart';
import '../../providers/storyboard_provider.dart';
import '../ui.dart';

/// 왼쪽 미리보기 플레이어: 선택 씬의 클립들에서 선택 화질 영상만 모아 **순서대로 이어서**
/// 실제 재생한다(한 클립이 끝나면 자동으로 다음 클립).
class PreviewPlayer extends StatefulWidget {
  const PreviewPlayer({super.key});

  @override
  State<PreviewPlayer> createState() => _PreviewPlayerState();
}

class _PreviewPlayerState extends State<PreviewPlayer> {
  VideoPlayerController? _ctrl;
  List<({VideoClip clip, String path})> _clips = [];
  int _index = 0;
  bool _playing = false; // 연속 재생 모드
  bool _ready = false;

  static const _videoExts = {'.mp4', '.mov', '.m4v', '.webm'};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = StoryboardScope.of(context);
    // 재생 가능한 영상 클립만 순서대로(씬 전체 = 샷들의 클립 평탄화).
    final clips = <({VideoClip clip, String path})>[];
    for (final s in p.sceneClips) {
      final path = p.videoPathOf(s);
      if (path != null && _videoExts.any(path.toLowerCase().endsWith)) {
        clips.add((clip: s, path: path));
      }
    }
    // 목록이 바뀌었으면 재구성.
    final changed = clips.length != _clips.length ||
        [for (var i = 0; i < clips.length; i++) clips[i].path != _clips[i].path]
            .any((x) => x);
    if (changed) {
      _clips = clips;
      _index = _index.clamp(0, clips.isEmpty ? 0 : clips.length - 1);
      _load(autoPlay: _playing);
    }
  }

  Future<void> _load({bool autoPlay = false}) async {
    final old = _ctrl;
    _ctrl = null;
    _ready = false;
    old?.removeListener(_tick);
    await old?.dispose();
    if (!mounted) return;
    setState(() {});
    if (_clips.isEmpty) return;

    final ctrl = VideoPlayerController.file(File(_clips[_index].path));
    try {
      await ctrl.initialize();
    } catch (_) {
      // 재생 불가 클립이면 다음으로 건너뛴다.
      await ctrl.dispose();
      if (_index < _clips.length - 1) {
        _index++;
        return _load(autoPlay: autoPlay);
      }
      return;
    }
    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    ctrl.addListener(_tick);
    _ctrl = ctrl;
    _ready = true;
    if (autoPlay) ctrl.play();
    setState(() {});
  }

  void _tick() {
    final c = _ctrl;
    if (c == null) return;
    final v = c.value;
    // 클립 끝 → 다음 클립으로(연속 재생 중일 때).
    if (_playing &&
        v.duration > Duration.zero &&
        v.position >= v.duration &&
        !v.isPlaying) {
      _next(autoPlay: true);
      return;
    }
    if (mounted) setState(() {}); // 재생/정지 아이콘·진행바 갱신
  }

  void _playPause() {
    final c = _ctrl;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        _playing = false;
        c.pause();
      } else {
        _playing = true;
        // 끝에서 다시 누르면 처음부터.
        if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
        c.play();
      }
    });
  }

  void _jump(int i) {
    if (_clips.isEmpty) return;
    _index = i.clamp(0, _clips.length - 1);
    _load(autoPlay: _playing);
  }

  void _next({bool autoPlay = false}) {
    if (_index < _clips.length - 1) {
      _index++;
      _load(autoPlay: autoPlay);
    } else {
      _playing = false; // 마지막 클립 → 정지
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_tick);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final hasClips = _clips.isNotEmpty;
    final cur = hasClips ? _clips[_index] : null;
    final title = cur == null
        ? '재생할 영상 없음'
        : (cur.clip.title.trim().isEmpty
            ? 'CLIP ${p.sceneClips.indexOf(cur.clip) + 1}'
            : 'CLIP ${p.sceneClips.indexOf(cur.clip) + 1} · ${cur.clip.title.trim()}');
    final playing = _ctrl?.value.isPlaying ?? false;

    return Container(
      color: panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더 + 접기
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.movie_filter_outlined, size: 18, color: accent2),
                const SizedBox(width: 8),
                const Text('미리보기 플레이어',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const Spacer(),
                IconButton(
                  tooltip: '접기',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: p.togglePlayer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 재생 화면
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: previewBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _screen(p),
              ),
            ),
          ),
          // 현재 클립 라벨 + 진행바
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                Text(hasClips ? '${_index + 1} / ${_clips.length}' : '0 / 0',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0x99FFFFFF))),
              ],
            ),
          ),
          if (_ready && _ctrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: VideoProgressIndicator(_ctrl!, allowScrubbing: true),
            ),
          // 재생 컨트롤
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 28,
                  tooltip: '이전',
                  onPressed:
                      hasClips && _index > 0 ? () => _jump(_index - 1) : null,
                  icon: const Icon(Icons.skip_previous),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  iconSize: 32,
                  tooltip: playing ? '일시정지' : '재생',
                  onPressed: (hasClips && _ready) ? _playPause : null,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 28,
                  tooltip: '다음',
                  onPressed: hasClips && _index < _clips.length - 1
                      ? () => _jump(_index + 1)
                      : null,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _screen(StoryboardProvider p) {
    if (_clips.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined, color: Colors.white24, size: 40),
            SizedBox(height: 8),
            Text(
              '생성된 영상이 없습니다',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      );
    }
    final c = _ctrl;
    if (!_ready || c == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      onTap: _playPause,
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}
