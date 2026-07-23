import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../ui.dart' show accent2;

/// 재생 목록의 한 항목 — 영상 + 그 샷이 속한 비트의 음성(있으면).
/// [beatId]로 비트 경계를 안다: 1 대사 = 여러 샷이라, 같은 비트가 이어지는 동안엔 음성을 새로
/// 틀지 않고 이어서 재생한다(샷마다 처음부터 다시 틀면 대사가 뚝뚝 끊긴다).
typedef PlaylistItem = ({
  String path,
  String title,
  String beatId,
  String? voicePath,
});

/// 영상을 크게 재생하는 팝업 — **씬의 영상들을 순서대로 이어서** 보며, 대사 음성·씬 배경음도
/// 함께 튼다(완성본 미리보기). [startPath]에서 시작한다. 기본은 그 샷을 반복하고,
/// "다음 영상 자동 재생"을 켜면 씬을 이어서 본다.
Future<void> showVideoPlayDialog(
  BuildContext context, {
  required List<PlaylistItem> playlist,
  required String startPath,
  String? bgmPath,
}) =>
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xE6000000),
      builder: (_) => _VideoPlayDialog(
        playlist: playlist,
        startPath: startPath,
        bgmPath: bgmPath,
      ),
    );

class _VideoPlayDialog extends StatefulWidget {
  const _VideoPlayDialog({
    required this.playlist,
    required this.startPath,
    this.bgmPath,
  });
  final List<PlaylistItem> playlist;
  final String startPath;
  final String? bgmPath;

  @override
  State<_VideoPlayDialog> createState() => _VideoPlayDialogState();
}

class _VideoPlayDialogState extends State<_VideoPlayDialog> {
  VideoPlayerController? _ctrl; // 영상
  VideoPlayerController? _voice; // 현재 비트의 대사 음성(mp3)
  VideoPlayerController? _bgm; // 씬 배경음(mp3, 루프)
  String? _voiceBeatId; // 지금 음성이 걸린 비트 — 비트가 바뀔 때만 새로 튼다
  Object? _error;
  late int _index;
  bool _playing = true;
  bool _autoNext = true; // 다음 영상 자동 재생 — 켜짐(끄면 현재 샷 반복)

  List<PlaylistItem> get _items => widget.playlist;

  @override
  void initState() {
    super.initState();
    final i = _items.indexWhere((e) => e.path == widget.startPath);
    _index = i < 0 ? 0 : i;
    _openBgm();
    _open();
  }

  Future<void> _openBgm() async {
    final path = widget.bgmPath;
    if (path == null || !File(path).existsSync()) return;
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setLooping(true);
      _bgm = c;
      if (_playing) await c.play();
    } catch (_) {
      await c.dispose();
    }
  }

  Future<void> _open() async {
    final old = _ctrl;
    _ctrl = null;
    _error = null;
    old?.removeListener(_onTick);
    await old?.dispose();
    if (!mounted) return;
    setState(() {});
    if (_items.isEmpty) return;

    await _syncVoice(); // 비트가 바뀌면 이 지점에서 음성을 새로 튼다

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
    c.addListener(_onTick);
    await c.setLooping(!_autoNext);
    _ctrl = c;
    if (_playing) c.play();
    setState(() {});
  }

  /// 현재 항목의 비트에 맞춰 음성을 맞춘다. 같은 비트가 이어지면 그대로 두고,
  /// 비트가 바뀌면 음성을 새로 로드해 처음부터 재생한다.
  Future<void> _syncVoice() async {
    final it = _items[_index];
    if (it.beatId == _voiceBeatId) return; // 같은 대사가 이어지는 중 — 음성 유지
    _voiceBeatId = it.beatId;
    final old = _voice;
    _voice = null;
    old?.removeListener(_onTick);
    await old?.dispose();
    final vp = it.voicePath;
    if (vp == null || !File(vp).existsSync()) return;
    final c = VideoPlayerController.file(File(vp));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick); // 대사가 끝나는 순간을 잡아 다음 비트로 넘긴다(영상이 멈춰 있어도)
      _voice = c;
      if (_playing) await c.play();
    } catch (_) {
      await c.dispose();
    }
  }

  bool get _ended {
    final v = _ctrl?.value;
    return v != null &&
        v.duration > Duration.zero &&
        v.position >= v.duration &&
        !v.isPlaying;
  }

  bool get _voiceEnded {
    final v = _voice?.value;
    return v != null &&
        v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration;
  }

  bool get _hasVoiceNow {
    final v = _voice?.value;
    return v != null && v.isInitialized && v.duration > Duration.zero;
  }

  /// 다음 항목이 **같은 비트**인지(같은 대사가 여러 샷으로 이어지는 중).
  bool get _sameBeatNext =>
      _index + 1 < _items.length &&
      _items[_index + 1].beatId == _items[_index].beatId;

  /// 지금 비트 다음의 **다른 비트** 첫 항목 인덱스. 없으면 null(끝).
  int? get _nextBeatIndex {
    final bid = _items[_index].beatId;
    for (var j = _index + 1; j < _items.length; j++) {
      if (_items[j].beatId != bid) return j;
    }
    return null;
  }

  bool _advancing = false; // 한 프레임에 두 리스너가 겹쳐 두 번 넘기는 것 방지

  /// 영상·음성 컨트롤러가 진행할 때마다 호출 — UI 갱신 + 자동 진행 판단.
  void _onTick() {
    if (!mounted) return;
    setState(() {}); // 재생 아이콘·진행바 갱신
    if (!_playing || !_autoNext || _advancing) return;

    void go(int i) {
      _advancing = true;
      _index = i;
      _open().whenComplete(() => _advancing = false);
    }

    if (_hasVoiceNow) {
      // 대사 우선: 대사가 끝나면 다음 비트로 넘어가며 남은 영상을 잘라낸다.
      if (_voiceEnded) {
        final ni = _nextBeatIndex;
        if (ni != null) {
          go(ni);
        } else {
          _stopAtEnd();
        }
        return;
      }
      // 대사가 아직인데 영상이 먼저 끝나면: 같은 비트의 다음 샷으로. 마지막 샷이면 대사가
      // 끝날 때까지 **마지막 프레임을 유지**(여기서 아무것도 안 함 → 다음 tick에서 대사 종료를 잡음).
      if (_ended && _sameBeatNext) go(_index + 1);
    } else {
      // 대사 없는 비트: 영상이 끝나면 다음으로.
      if (_ended) {
        if (_index < _items.length - 1) {
          go(_index + 1);
        } else {
          _stopAtEnd();
        }
      }
    }
  }

  void _stopAtEnd() {
    _playing = false;
    _voice?.pause();
    _bgm?.pause();
    if (mounted) setState(() {});
  }

  void _toggle() {
    final c = _ctrl;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        _playing = false;
        c.pause();
        _voice?.pause();
        _bgm?.pause();
      } else {
        _playing = true;
        if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
        c.play();
        _voice?.play();
        _bgm?.play();
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
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    _voice?.dispose();
    _bgm?.dispose();
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
                if (_voice != null)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.record_voice_over,
                        size: 15, color: Color(0x99FFFFFF)),
                  ),
                if (_bgm != null)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.music_note,
                        size: 15, color: Color(0x99FFFFFF)),
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
    return LayoutBuilder(
      builder: (context, box) {
        const chromeH = 76.0;
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
