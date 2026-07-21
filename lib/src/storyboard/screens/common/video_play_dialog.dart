import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../ui.dart' show accent2;

/// 재생 목록의 한 항목 — 영상 경로 + 라벨.
typedef PlaylistItem = ({String path, String title});

/// 영상을 크게 재생하는 팝업 — **씬의 영상들을 순서대로 이어서** 본다(옛 미리보기 플레이어 통합).
/// [startPath]에서 시작한다. 기본은 그 샷을 반복하고, "다음 영상 자동 재생"을 켜면 씬을 이어서 본다.
/// 여백이나 닫기를 누르면 닫힌다.
Future<void> showVideoPlayDialog(
  BuildContext context, {
  required List<PlaylistItem> playlist,
  required String startPath,
}) =>
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xE6000000),
      builder: (_) => _VideoPlayDialog(playlist: playlist, startPath: startPath),
    );

class _VideoPlayDialog extends StatefulWidget {
  const _VideoPlayDialog({required this.playlist, required this.startPath});
  final List<PlaylistItem> playlist;
  final String startPath;

  @override
  State<_VideoPlayDialog> createState() => _VideoPlayDialogState();
}

class _VideoPlayDialogState extends State<_VideoPlayDialog> {
  VideoPlayerController? _ctrl;
  Object? _error;
  late int _index;
  bool _playing = true; // 연속 재생 중인지 — 자동 이어붙이기 판단용
  bool _autoNext = false; // 다음 영상 자동 재생 — **기본 꺼짐**(끄면 현재 샷을 반복)

  List<PlaylistItem> get _items => widget.playlist;

  @override
  void initState() {
    super.initState();
    final i = _items.indexWhere((e) => e.path == widget.startPath);
    _index = i < 0 ? 0 : i;
    _open();
  }

  Future<void> _open() async {
    final old = _ctrl;
    _ctrl = null;
    _error = null;
    old?.removeListener(_tick);
    await old?.dispose();
    if (!mounted) return;
    setState(() {});
    if (_items.isEmpty) return;

    final c = VideoPlayerController.file(File(_items[_index].path));
    try {
      await c.initialize();
    } catch (e) {
      await c.dispose();
      if (mounted) setState(() => _error = e);
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    c.addListener(_tick);
    await c.setLooping(!_autoNext); // 자동 재생이 꺼져 있으면 현재 샷을 영상 자체가 반복
    _ctrl = c;
    if (_playing) c.play();
    setState(() {});
  }

  void _tick() {
    final c = _ctrl;
    if (c == null) return;
    final v = c.value;
    // 자동 재생이 켜져 있으면 한 편이 끝나고 다음으로. 꺼져 있으면 영상이 알아서 반복해 안 넘어간다.
    if (_playing &&
        _autoNext &&
        v.duration > Duration.zero &&
        v.position >= v.duration &&
        !v.isPlaying) {
      if (_index < _items.length - 1) {
        _index++;
        _open();
      } else {
        setState(() => _playing = false);
      }
      return;
    }
    if (mounted) setState(() {}); // 재생/정지 아이콘·진행바 갱신
  }

  void _toggle() {
    final c = _ctrl;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        _playing = false;
        c.pause();
      } else {
        _playing = true;
        if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
        c.play();
      }
    });
  }

  void _jump(int i) {
    if (i < 0 || i >= _items.length) return;
    _index = i;
    _open();
  }

  void _toggleAutoNext() {
    setState(() => _autoNext = !_autoNext);
    _ctrl?.setLooping(!_autoNext);
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_tick);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _items.isEmpty ? '' : _items[_index].title;
    final counter = _items.isEmpty ? '' : '${_index + 1} / ${_items.length}';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          // 영상 바깥(여백)을 눌러도 닫힌다.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.opaque,
            ),
          ),
          Center(child: _body()),
          // 상단: 제목 · 순번 · 닫기
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                ),
                if (counter.isNotEmpty) ...[
                  Text(counter,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0x99FFFFFF))),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return const SizedBox(
        width: 160,
        height: 120,
        child: Center(
          child: Text('영상을 열 수 없습니다',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    final c = _ctrl;
    if (c == null) {
      return const SizedBox(
        width: 120,
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final playing = c.value.isPlaying;
    final ratio = c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio;
    final hasPrev = _index > 0;
    final hasNext = _index < _items.length - 1;
    // 창(팝업 여백 제외) 안에 세로·가로 모두 들어가도록 실제 여유 크기를 재서 맞춘다.
    // 진행바 + 컨트롤 높이만큼은 영상 높이에서 뺀다.
    return LayoutBuilder(
      builder: (context, box) {
        const chromeH = 76.0; // 진행바 + 재생 컨트롤 + 간격
        final maxW = box.maxWidth;
        final maxH = box.maxHeight - chromeH;
        var w = maxW;
        var h = w / ratio;
        if (h > maxH) {
          h = maxH;
          w = h * ratio;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 여백 탭(닫기)과 영상 탭(재생/정지)이 안 섞이게 영상 자체는 따로 잡는다.
            GestureDetector(
              onTap: _toggle,
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(c),
                    if (!playing)
                      const IgnorePointer(
                        child: Icon(Icons.play_circle,
                            size: 64, color: Colors.white70),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: w,
              child: VideoProgressIndicator(c, allowScrubbing: true),
            ),
            const SizedBox(height: 2),
            // 처음으로 · 이전 · 재생/정지 · 다음 · 다음 영상 자동 재생
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '제일 처음으로',
                  color: Colors.white70,
                  onPressed: hasPrev ? () => _jump(0) : null,
                  icon: const Icon(Icons.first_page),
                ),
                IconButton(
                  tooltip: '이전',
                  color: Colors.white70,
                  onPressed: hasPrev ? () => _jump(_index - 1) : null,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton.filled(
                  iconSize: 28,
                  tooltip: playing ? '일시정지' : '재생',
                  onPressed: _toggle,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: '다음',
                  color: Colors.white70,
                  onPressed: hasNext ? () => _jump(_index + 1) : null,
                  icon: const Icon(Icons.skip_next),
                ),
                IconButton(
                  tooltip: _autoNext ? '다음 영상 자동 재생 켜짐' : '다음 영상 자동 재생',
                  color: _autoNext ? accent2 : Colors.white70,
                  onPressed: _toggleAutoNext,
                  icon: const Icon(Icons.playlist_play),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
