import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:video_player/video_player.dart';

import '../../models/caption.dart' show captionTextSeconds;
import '../ui.dart' show accent2;

/// 재생 목록의 한 항목 — 영상 + 그 샷이 속한 비트의 음성(있으면).
/// [beatId]로 비트 경계를 안다: 1 대사 = 여러 샷이라, 같은 비트가 이어지는 동안엔 음성을 새로
/// 틀지 않고 이어서 재생한다(샷마다 처음부터 다시 틀면 대사가 뚝뚝 끊긴다).
///
/// [path]가 null이면 **아직 영상이 없는 샷**이다 — 빼지 않고 [imagePath](시작 프레임,
/// 그것도 없으면 검은 화면)를 [seconds]만큼 세워 둔다. 대사는 그대로 들린다.
typedef PlaylistItem = ({
  String? path,
  String? imagePath,
  double seconds, // 영상 없는 항목이 화면에 머무는 길이(영상 항목은 실제 길이를 쓴다)
  String title,
  String beatId,
  String? voicePath,
  String? sfxPath,
  List<({double seconds, String text})> captionCues,
  String captionPos, // 'top' | 'middle' | 'bottom'
});

/// 영상을 크게 재생하는 팝업 — **씬의 영상들을 순서대로 이어서** 보며, 대사 음성·씬 배경음도
/// 함께 튼다(완성본 미리보기). [startPath]가 있으면 그 영상에서, 없으면(=null)
/// **씬 처음부터** 시작한다. 기본은 그 샷을 반복하고, "다음 영상 자동 재생"을 켜면 이어서 본다.
Future<void> showVideoPlayDialog(
  BuildContext context, {
  required List<PlaylistItem> playlist,
  String? startPath,
  String? bgmPath,
  double speed = 1.0, // 트랙 배속 — 영상·대사·효과음이 함께 빨라진다(배경음은 등속)
}) =>
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xE6000000),
      builder: (_) => _VideoPlayDialog(
        playlist: playlist,
        startPath: startPath,
        bgmPath: bgmPath,
        speed: speed,
      ),
    );

class _VideoPlayDialog extends StatefulWidget {
  const _VideoPlayDialog({
    required this.playlist,
    this.startPath,
    this.bgmPath,
    this.speed = 1.0,
  });
  final List<PlaylistItem> playlist;
  final String? startPath;
  final String? bgmPath;
  final double speed;

  @override
  State<_VideoPlayDialog> createState() => _VideoPlayDialogState();
}

class _VideoPlayDialogState extends State<_VideoPlayDialog>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _ctrl; // 영상
  VideoPlayerController? _voice; // 현재 비트의 대사 음성(mp3)
  VideoPlayerController? _sfx; // 현재 **샷**의 효과음(mp3)
  VideoPlayerController? _bgm; // 씬 배경음(mp3, 루프)
  String? _voiceBeatId; // 지금 음성이 걸린 비트 — 비트가 바뀔 때만 새로 튼다
  // 효과음은 샷 단위라 항목이 바뀔 때마다 새로 튼다(비트 경계가 아니라).

  // 자막: 비트 시작부터 흐르는 시계(_beatElapsed)로 지금 보여줄 구간을 고른다. 재생 중일 때만 흐른다.
  late final Ticker _ticker;
  Duration _tickerLast = Duration.zero;
  Duration _beatElapsed = Duration.zero;

  /// 지금 항목이 화면에 머문 시간 — **영상 없는 항목**(이미지·검은 화면)의 진행 시계다.
  /// 영상이 있으면 진행은 영상 컨트롤러가 알려 준다.
  Duration _itemElapsed = Duration.zero;
  double _imageRatio = 9 / 16; // 이미지 항목의 가로세로비(로드 후 실제 값으로)
  String? _capBeatId; // 자막 시계가 걸린 비트 — 바뀌면 시계를 0으로
  List<({double seconds, String text})> _cues = const [];
  String _capPos = 'bottom';
  Object? _error;
  late int _index;
  bool _playing = true;
  bool _autoNext = true; // 다음 영상 자동 재생 — 켜짐(끄면 현재 샷 반복)

  List<PlaylistItem> get _items => widget.playlist;

  PlaylistItem? get _item =>
      (_index >= 0 && _index < _items.length) ? _items[_index] : null;

  /// 지금 항목에 영상이 없는지(=이미지나 검은 화면으로 세워 두는 중).
  bool get _isStillItem => _item != null && _item!.path == null;

  /// 영상 없는 항목이 머무는 길이(초) — 0 이하면 최소 1초는 보여 준다.
  double get _stillSeconds {
    final s = _item?.seconds ?? 0;
    return s <= 0 ? 1.0 : s;
  }

  /// 트랙 배속(1.0~2.0). 영상·대사·효과음에 걸고, 배경음은 등속으로 둔다(내보내기와 같은 규칙).
  double get _speed => widget.speed.clamp(1.0, 2.0).toDouble();

  @override
  void initState() {
    super.initState();
    // startPath가 없거나 목록에 없으면 처음부터.
    final i = widget.startPath == null
        ? -1
        : _items.indexWhere((e) => e.path == widget.startPath);
    _index = i < 0 ? 0 : i;
    _ticker = createTicker(_onTicker)..start();
    _openBgm();
    _open();
  }

  /// 자막·항목 시계 — 재생 중일 때만 흐른다. 보여줄 자막 구간이 바뀌면 그때만 다시 그린다.
  /// 영상 없는 항목일 땐 이 시계가 진행의 유일한 기준이라 매 프레임 다시 그리고 진행도 본다.
  void _onTicker(Duration elapsed) {
    if (!mounted) return;
    final delta = elapsed - _tickerLast;
    _tickerLast = elapsed;
    if (!_playing) return;
    final before = _activeCaption();
    // 자막 구간은 **원본 시간축** 기준이라, 배속으로 빨라진 만큼 시계도 빨리 흘려야 맞는다.
    _beatElapsed += delta * _speed;
    _itemElapsed += delta * _speed;
    if (_isStillItem) {
      setState(() {}); // 진행바
    } else if (_activeCaption() != before) {
      setState(() {});
    }
    // 진행 판단은 **매 프레임** 본다. 영상이 끝나면 그 컨트롤러는 더 이상 알려 주지 않으므로,
    // 남은 대사·자막을 기다리는 동안 깨워 줄 게 이 시계밖에 없다(안 그러면 그 자리에 멈춘다).
    _maybeAdvance();
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
    // 이 자리의 시계는 항상 0에서 — 첫 await 전에 돌려놔야, 여는 동안 도는 시계가
    // 앞 항목의 흘러간 시간을 이 자리 것으로 착각해 곧바로 넘겨 버리지 않는다.
    _itemElapsed = Duration.zero;
    old?.removeListener(_onTick);
    await old?.dispose();
    if (!mounted) return;
    setState(() {});
    if (_items.isEmpty) return;

    await _syncVoice(); // 비트가 바뀌면 이 지점에서 음성을 새로 튼다
    await _syncSfx(); // 효과음은 샷마다 새로 튼다
    _syncCaption(); // 자막 시계도 비트 경계에서 0으로

    final path = _items[_index].path;
    if (path == null) {
      // 아직 영상이 없는 자리 — 시작 프레임(없으면 검은 화면)을 계획 길이만큼 세운다.
      // 진행은 컨트롤러가 아니라 [_itemElapsed] 시계가 본다.
      _imageRatio = await _resolveRatio(_items[_index].imagePath);
      if (mounted) setState(() {});
      return;
    }

    final c = VideoPlayerController.file(File(path));
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
    await c.setPlaybackSpeed(_speed); // 트랙 배속
    _ctrl = c;
    if (_playing) c.play();
    setState(() {});
  }

  /// 세울 이미지의 가로세로비 — 못 읽으면 세로(9:16)로 둔다(숏폼이 기본이라).
  Future<double> _resolveRatio(String? path) async {
    if (path == null || !File(path).existsSync()) return 9 / 16;
    final done = Completer<double>();
    final stream = FileImage(File(path)).resolve(const ImageConfiguration());
    late final ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (!done.isCompleted) {
        final h = info.image.height;
        done.complete(h == 0 ? 9 / 16 : info.image.width / h);
      }
      stream.removeListener(l);
    }, onError: (_, _) {
      if (!done.isCompleted) done.complete(9 / 16);
      stream.removeListener(l);
    });
    stream.addListener(l);
    return done.future;
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
      await c.setPlaybackSpeed(_speed); // 대사도 같은 배속
      _voice = c;
      if (_playing) await c.play();
    } catch (_) {
      await c.dispose();
    }
  }

  /// 현재 **샷**의 효과음을 맞춘다 — 항목이 바뀌면 그 샷 것으로 새로 튼다.
  /// 대사와 달리 **타임라인을 좌우하지 않는다**(진행 판단에 안 낀다) — 영상 위에 얹혀 재생만 된다.
  Future<void> _syncSfx() async {
    final it = _items[_index];
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
      await c.setPlaybackSpeed(_speed); // 효과음도 같은 배속
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

  /// 이 자리의 **화면**이 끝났는지. 영상이 있으면 영상이, 없으면 계획 길이 시계가 기준이다.
  /// (대사가 더 길면 아래 진행 판단이 대사 끝까지 기다린다 — 규칙은 그대로.)
  bool get _ended {
    if (_isStillItem) {
      return _itemElapsed.inMilliseconds / 1000.0 >= _stillSeconds;
    }
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

  /// 이 비트의 자막이 다 지나갔는지 — 자막도 **길이를 정하는 축**이다(영상·대사와 나란히).
  /// 자막이 없으면 항상 참. 뒤쪽 빈 구간은 안 센다([captionTextSeconds]).
  bool get _capEnded {
    final end = captionTextSeconds(_cues);
    if (end <= 0) return true;
    return _beatElapsed.inMilliseconds / 1000.0 >= end;
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
    _maybeAdvance();
  }

  /// 자동 진행 판단 — 이 비트에 걸린 **화면·대사·자막 중 가장 늦게 끝나는 것**까지 재생한다.
  /// 셋 중 하나만 있어도 그것만큼은 온전히 보여 준다(영상이 없다고 그 자리를 건너뛰지 않는다).
  /// 영상 컨트롤러(=_onTick)와 시계(=_onTicker) 둘 다 여기로 들어온다.
  void _maybeAdvance() {
    if (!mounted) return;
    if (!_playing || !_autoNext || _advancing) return;

    void go(int i) {
      _advancing = true;
      _index = i;
      _open().whenComplete(() => _advancing = false);
    }

    if (!_ended) return; // 화면(영상 또는 세워 둔 프레임)이 아직 남았다

    // 비트 안 다음 샷으로 — 대사·자막은 비트 단위라 그대로 이어진다(시계도 안 건드린다).
    if (_sameBeatNext) {
      go(_index + 1);
      return;
    }
    // 비트의 마지막 샷: 화면은 끝났지만 대사나 자막이 남았으면 그 자리에서 기다린다.
    if (_hasVoiceNow && !_voiceEnded) return;
    if (!_capEnded) return;

    final ni = _nextBeatIndex;
    if (ni != null) {
      go(ni);
    } else {
      _stopAtEnd();
    }
  }

  void _stopAtEnd() {
    _playing = false;
    _voice?.pause();
    _sfx?.pause();
    _bgm?.pause();
    if (mounted) setState(() {});
  }

  /// 재생/일시정지 — 영상이 없는 자리(이미지·검은 화면)에서도 눌린다(대사·시계가 선다).
  void _toggle() {
    setState(() {
      final c = _ctrl;
      if (_playing) {
        _playing = false;
        c?.pause();
        _voice?.pause();
        _sfx?.pause();
        _bgm?.pause();
      } else {
        _playing = true;
        if (c != null && c.value.position >= c.value.duration) {
          c.seekTo(Duration.zero);
        }
        c?.play();
        _voice?.play();
        _sfx?.play();
        _bgm?.play();
      }
    });
  }

  void _jump(int i) {
    if (i < 0 || i >= _items.length) return;
    // 여는 동안은 진행 판단을 멈춘다(자동 진행과 같은 규칙) — 안 그러면 여는 사이에
    // 시계가 먼저 판단해 버려 손으로 고른 자리를 지나칠 수 있다.
    _advancing = true;
    _index = i;
    _open().whenComplete(() => _advancing = false);
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

  /// 영상이 없는 자리의 화면 — 시작 프레임, 그것도 없으면 "영상 없음" 검은 화면.
  /// 자리를 비우지 않는 게 요점이다(비우면 그 비트 대사가 통째로 사라진다).
  Widget _stillFrame() {
    final img = _item?.imagePath;
    if (img != null && File(img).existsSync()) {
      return Image.file(File(img), fit: BoxFit.contain);
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Text(
        '영상 없음 — 대사만 재생',
        style: TextStyle(color: Colors.white38, fontSize: 12),
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
    // 영상이 있는 자리인데 컨트롤러가 아직 없으면 = 여는 중.
    if (c == null && !_isStillItem) {
      return const SizedBox(
        width: 120,
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final playing = c?.value.isPlaying ?? _playing;
    final ratio = c == null
        ? _imageRatio
        : (c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio);
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
                    if (c != null)
                      VideoPlayer(c)
                    else
                      _stillFrame(),
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
              child: c != null
                  ? VideoProgressIndicator(c, allowScrubbing: true)
                  : LinearProgressIndicator(
                      // 영상이 없는 자리 — 계획 길이 대비 얼마나 지났는지.
                      value: (_itemElapsed.inMilliseconds /
                              1000.0 /
                              _stillSeconds)
                          .clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: const Color(0x22FFFFFF),
                    ),
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
