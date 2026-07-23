import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
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
  String? sfxPath,
  List<({double seconds, String text})> captionCues,
  String captionPos, // 'top' | 'middle' | 'bottom'
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

class _VideoPlayDialogState extends State<_VideoPlayDialog>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _ctrl; // 영상
  VideoPlayerController? _voice; // 현재 비트의 대사 음성(mp3)
  VideoPlayerController? _sfx; // 현재 비트의 효과음(mp3)
  VideoPlayerController? _bgm; // 씬 배경음(mp3, 루프)
  String? _voiceBeatId; // 지금 음성이 걸린 비트 — 비트가 바뀔 때만 새로 튼다
  String? _sfxBeatId; // 지금 효과음이 걸린 비트 — 비트가 바뀔 때만 새로 튼다

  // 자막: 비트 시작부터 흐르는 시계(_beatElapsed)로 지금 보여줄 구간을 고른다. 재생 중일 때만 흐른다.
  late final Ticker _ticker;
  Duration _tickerLast = Duration.zero;
  Duration _beatElapsed = Duration.zero;
  String? _capBeatId; // 자막 시계가 걸린 비트 — 바뀌면 시계를 0으로
  List<({double seconds, String text})> _cues = const [];
  String _capPos = 'bottom';
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
    _ticker = createTicker(_onTicker)..start();
    _openBgm();
    _open();
  }

  /// 자막 시계 — 재생 중일 때만 흐른다. 보여줄 자막 구간이 바뀌면 그때만 다시 그린다.
  void _onTicker(Duration elapsed) {
    if (!mounted) return;
    final delta = elapsed - _tickerLast;
    _tickerLast = elapsed;
    if (!_playing) return;
    final before = _activeCaption();
    _beatElapsed += delta;
    if (_activeCaption() != before) setState(() {});
  }

  /// 지금(_beatElapsed) 보여줄 자막 텍스트. 공백 구간이거나 범위 밖이면 null.
  String? _activeCaption() {
    if (_cues.isEmpty) return null;
    final t = _beatElapsed.inMilliseconds / 1000.0;
    var acc = 0.0;
    for (final c in _cues) {
      if (t >= acc && t < acc + c.seconds) {
        return c.text.trim().isEmpty ? null : c.text.trim();
      }
      acc += c.seconds;
    }
    return null;
  }

  /// 영상 위에 지금 자막을 얹는다(상단/중간/하단). 보여줄 게 없으면 빈 위젯.
  Widget _captionOverlay(double w, double h) {
    final text = _activeCaption();
    if (text == null) return const SizedBox.shrink();
    final align = switch (_capPos) {
      'top' => Alignment.topCenter,
      'middle' => Alignment.center,
      _ => Alignment.bottomCenter,
    };
    return IgnorePointer(
      child: Align(
        alignment: align,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.05, vertical: h * 0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x99000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: (h * 0.055).clamp(12, 40),
                fontWeight: FontWeight.w600,
                height: 1.25,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
        ),
      ),
    );
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
    await _syncSfx(); // 효과음도 비트 경계에서 새로 튼다
    _syncCaption(); // 자막 시계도 비트 경계에서 0으로

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
      c.addListener(_onTick); // 대사 종료를 잡는다(영상이 멈춰 있어도) — 대사가 더 길면 그 끝에서 넘어간다
      _voice = c;
      if (_playing) await c.play();
    } catch (_) {
      await c.dispose();
    }
  }

  /// 현재 비트의 효과음을 맞춘다 — 비트가 바뀔 때만 새로 튼다(같은 비트 이어지면 유지).
  /// 대사와 달리 **타임라인을 좌우하지 않는다**(진행 판단에 안 낀다) — 영상 위에 얹혀 재생만 된다.
  Future<void> _syncSfx() async {
    final it = _items[_index];
    if (it.beatId == _sfxBeatId) return; // 같은 비트 — 효과음 유지
    _sfxBeatId = it.beatId;
    final old = _sfx;
    _sfx = null;
    await old?.dispose();
    final sp = it.sfxPath;
    if (sp == null || !File(sp).existsSync()) return;
    final c = VideoPlayerController.file(File(sp));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      _sfx = c;
      if (_playing) await c.play();
    } catch (_) {
      await c.dispose();
    }
  }

  /// 비트가 바뀌면 자막 시계를 0으로 돌리고 그 비트의 자막 구간·위치를 건다.
  void _syncCaption() {
    final it = _items[_index];
    if (it.beatId == _capBeatId) return; // 같은 비트 — 시계 유지
    _capBeatId = it.beatId;
    _beatElapsed = Duration.zero;
    _cues = it.captionCues;
    _capPos = it.captionPos;
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
      // 대사와 영상 중 **더 긴 쪽**까지 재생한다(어느 쪽도 잘리지 않는다).
      if (_ended) {
        if (_sameBeatNext) {
          // 비트 안 다음 샷으로 — 영상을 이어서(음성은 유지). 대사가 짧아도 영상은 끝까지 본다.
          go(_index + 1);
        } else if (_voiceEnded) {
          // 마지막 샷: 영상도 대사도 끝났다 = 둘 중 긴 쪽까지 끝 → 다음 비트로.
          final ni = _nextBeatIndex;
          if (ni != null) {
            go(ni);
          } else {
            _stopAtEnd();
          }
        }
        // else 마지막 샷 영상은 끝났지만 대사가 남음 → 대사가 더 길다 → 마지막 프레임 유지(대기).
      }
      // 영상이 아직 재생 중이면(대사가 먼저 끝나도) 그대로 둔다 — 영상이 더 길면 끝까지 본다.
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
    _sfx?.pause();
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
        _sfx?.pause();
        _bgm?.pause();
      } else {
        _playing = true;
        if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
        c.play();
        _voice?.play();
        _sfx?.play();
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
    _ticker.dispose();
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    _voice?.dispose();
    _sfx?.dispose();
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
                    _captionOverlay(w, h),
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
