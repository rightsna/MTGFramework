import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../ui.dart';

/// 대사 음성(mp3)을 그 자리에서 재생/정지하는 작은 버튼.
/// BGM과 같은 방식으로 video_player를 오디오 재생에 재사용한다(별도 의존성 없음).
///
/// 음성을 재생성하면 파일 경로는 같아도 내용이 바뀌므로, 호출부에서
/// `key: ValueKey('$path:$seconds')` 처럼 길이를 섞은 키를 주면 새로 로드된다.
class VoicePlayButton extends StatefulWidget {
  const VoicePlayButton({
    super.key,
    required this.path,
    this.size = 20,
    this.color = accent2,
  });

  final String path;
  final double size;
  final Color color;

  @override
  State<VoicePlayButton> createState() => _VoicePlayButtonState();
}

class _VoicePlayButtonState extends State<VoicePlayButton> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _error = false;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final v = _ctrl?.value;
    // 끝까지 재생되면 처음으로 되감아 다시 재생할 수 있게 한다.
    if (v != null &&
        v.isInitialized &&
        !v.isPlaying &&
        v.position >= v.duration &&
        v.duration > Duration.zero) {
      _ctrl?.seekTo(Duration.zero);
    }
    setState(() {});
  }

  Future<void> _ensureLoaded() async {
    if (_ready || _loading) return;
    setState(() => _loading = true);
    final c = VideoPlayerController.file(File(widget.path));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() {
        _ctrl = c;
        _ready = true;
        _loading = false;
      });
    } catch (_) {
      await c.dispose();
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle() async {
    if (!_ready) {
      await _ensureLoaded();
      if (!_ready) return;
    }
    final c = _ctrl!;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      if (c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
      await c.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Icon(Icons.error_outline,
          size: widget.size, color: Colors.redAccent.withValues(alpha: 0.7));
    }
    final playing = _ctrl?.value.isPlaying ?? false;
    return InkWell(
      onTap: _toggle,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: _loading
            ? SizedBox(
                width: widget.size,
                height: widget.size,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Icon(
                playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                size: widget.size,
                color: widget.color,
              ),
      ),
    );
  }
}
