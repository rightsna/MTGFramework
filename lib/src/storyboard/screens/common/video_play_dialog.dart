import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 영상을 화면 가득 크게 재생하는 팝업 — 영상 탭에서 결과를 제대로 볼 때.
/// 열면 바로 재생되고(보려고 누른 것이므로), 화면이나 닫기를 누르면 닫힌다.
Future<void> showVideoPlayDialog(
  BuildContext context, {
  required String path,
  String? title,
}) =>
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xE6000000),
      builder: (_) => _VideoPlayDialog(path: path, title: title),
    );

class _VideoPlayDialog extends StatefulWidget {
  const _VideoPlayDialog({required this.path, this.title});
  final String path;
  final String? title;

  @override
  State<_VideoPlayDialog> createState() => _VideoPlayDialogState();
}

class _VideoPlayDialogState extends State<_VideoPlayDialog> {
  VideoPlayerController? _ctrl;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final c = VideoPlayerController.file(File(widget.path));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_tick);
      await c.setLooping(true);
      setState(() => _ctrl = c);
      await c.play();
    } catch (e) {
      await c.dispose();
      if (mounted) setState(() => _error = e);
    }
  }

  void _tick() {
    if (mounted) setState(() {}); // 재생/정지 아이콘·진행바 갱신
  }

  void _toggle() {
    final c = _ctrl;
    if (c == null) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_tick);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Row(
              children: [
                if (widget.title != null)
                  Expanded(
                    child: Text(
                      widget.title!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                  )
                else
                  const Spacer(),
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
    // 창(팝업 여백 제외) 안에 세로·가로 모두 들어가도록 실제 여유 크기를 재서 맞춘다.
    // 진행바 높이만큼은 영상 높이에서 뺀다.
    return LayoutBuilder(
      builder: (context, box) {
        const barH = 28.0; // 진행바 + 간격
        final maxW = box.maxWidth;
        final maxH = box.maxHeight - barH;
        // 가로 맞춤 높이가 세로 여유를 넘으면 세로 기준으로 맞춘다(=contain).
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
          ],
        );
      },
    );
  }
}
