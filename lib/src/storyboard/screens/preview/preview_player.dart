import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/shot.dart';
import '../../providers/storyboard_provider.dart';
import '../ui.dart';

/// 왼쪽 미리보기 플레이어: 선택 씬의 샷들에서 선택 화질 영상만 모아 **순서대로 이어서**
/// 실제 재생한다(한 샷이 끝나면 자동으로 다음 샷).
class PreviewPlayer extends StatefulWidget {
  const PreviewPlayer({super.key});

  @override
  State<PreviewPlayer> createState() => _PreviewPlayerState();
}

class _PreviewPlayerState extends State<PreviewPlayer> {
  VideoPlayerController? _ctrl;
  List<({Shot shot, String path})> _shots = [];
  int _index = 0;
  bool _playing = false; // 연속 재생 모드
  bool _ready = false;

  static const _videoExts = {'.mp4', '.mov', '.m4v', '.webm'};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = StoryboardScope.of(context);
    // 재생 가능한 영상 샷만 순서대로(씬 전체 = 대사들의 샷 평탄화).
    final shots = <({Shot shot, String path})>[];
    for (final s in p.sceneShots) {
      final path = p.videoPathOf(s);
      if (path != null && _videoExts.any(path.toLowerCase().endsWith)) {
        shots.add((shot: s, path: path));
      }
    }
    // 목록이 바뀌었으면 재구성.
    final changed = shots.length != _shots.length ||
        [for (var i = 0; i < shots.length; i++) shots[i].path != _shots[i].path]
            .any((x) => x);
    if (changed) {
      _shots = shots;
      _index = _index.clamp(0, shots.isEmpty ? 0 : shots.length - 1);
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
    if (_shots.isEmpty) return;

    final ctrl = VideoPlayerController.file(File(_shots[_index].path));
    try {
      await ctrl.initialize();
    } catch (_) {
      // 재생 불가 샷이면 다음으로 건너뛴다.
      await ctrl.dispose();
      if (_index < _shots.length - 1) {
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
    // 샷 끝 → 다음 샷으로(연속 재생 중일 때).
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
    if (_shots.isEmpty) return;
    _index = i.clamp(0, _shots.length - 1);
    _load(autoPlay: _playing);
  }

  void _next({bool autoPlay = false}) {
    if (_index < _shots.length - 1) {
      _index++;
      _load(autoPlay: autoPlay);
    } else {
      _playing = false; // 마지막 샷 → 정지
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
    final hasShots = _shots.isNotEmpty;
    final cur = hasShots ? _shots[_index] : null;
    final title = cur == null
        ? '재생할 영상 없음'
        : (cur.shot.title.trim().isEmpty
            ? '샷 ${p.sceneShots.indexOf(cur.shot) + 1}'
            : '샷 ${p.sceneShots.indexOf(cur.shot) + 1} · ${cur.shot.title.trim()}');
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
          // 현재 샷 라벨 + 진행바
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
                Text(hasShots ? '${_index + 1} / ${_shots.length}' : '0 / 0',
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
                      hasShots && _index > 0 ? () => _jump(_index - 1) : null,
                  icon: const Icon(Icons.skip_previous),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  iconSize: 32,
                  tooltip: playing ? '일시정지' : '재생',
                  onPressed: (hasShots && _ready) ? _playPause : null,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 28,
                  tooltip: '다음',
                  onPressed: hasShots && _index < _shots.length - 1
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
    if (_shots.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined, color: Colors.white24, size: 40),
            SizedBox(height: 8),
            Text(
              '영상이 없습니다',
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
