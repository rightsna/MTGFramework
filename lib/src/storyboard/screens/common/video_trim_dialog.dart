import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../services/video_edit.dart';
import '../ui.dart';

/// 생성된 영상을 **프레임 단위로 확인하고 앞뒤를 잘라내는** 다이얼로그.
/// FE2V 결과물은 가끔 양 끝에 이상한 프레임이 섞이는데, 그걸 눈으로 찾아 버리는 게 목적이다.
///
/// 프레임 정확도: macOS video_player는 seek 허용오차 0으로 맞춰 seek하므로
/// `(n + 0.5) / fps` 지점을 찍으면 정확히 n번 프레임이 보인다.
/// 실제 자르기는 ffmpeg의 select 필터가 프레임 번호로 처리한다([VideoEdit.trim]).
///
/// 저장하면 **원본 파일을 덮어쓴다**(되돌릴 수 없음). 자른 실제 길이(초)를 돌려주고,
/// 취소하면 null.
Future<double?> showVideoTrimDialog(
  BuildContext context, {
  required String path,
}) =>
    showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VideoTrimDialog(path: path),
    );

class _VideoTrimDialog extends StatefulWidget {
  const _VideoTrimDialog({required this.path});
  final String path;

  @override
  State<_VideoTrimDialog> createState() => _VideoTrimDialogState();
}

class _VideoTrimDialogState extends State<_VideoTrimDialog> {
  VideoPlayerController? _ctrl;
  VideoInfo? _info;
  Object? _error;

  int _frame = 0; // 현재 보고 있는 프레임
  int _first = 0; // 남길 구간 시작
  int _last = 0; // 남길 구간 끝(포함)
  bool _saving = false;

  /// 구간 재생 중이면 true — 끝 프레임에 닿으면 멈춰야 해서 따로 둔다.
  bool _rangePlaying = false;

  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final info = await VideoEdit.probe(widget.path);
      if (info == null) {
        throw Exception(VideoEdit.available
            ? '영상 정보를 읽을 수 없습니다.'
            : VideoEdit.missingHint);
      }
      final c = VideoPlayerController.file(File(widget.path));
      await c.initialize();
      await c.setVolume(0); // 프레임 훑을 때 소리가 튀지 않게. 구간 재생 때 켠다.
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() {
        _info = info;
        _ctrl = c;
        _last = info.frameCount - 1;
      });
      await _seek(0);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _onTick() {
    final c = _ctrl;
    final info = _info;
    if (c == null || info == null || !mounted) return;
    if (_rangePlaying) {
      final f = (c.value.position.inMicroseconds / 1e6 * info.fps).floor();
      if (f >= _last || !c.value.isPlaying) {
        _stopRange();
        return;
      }
      setState(() => _frame = f.clamp(0, info.frameCount - 1));
    }
  }

  /// [n]번 프레임을 화면에 띄운다. 프레임 n은 [n/fps, (n+1)/fps) 구간이므로
  /// 한가운데를 찍어야 부동소수 오차로 앞 프레임에 걸리지 않는다.
  Future<void> _seek(int n) async {
    final c = _ctrl;
    final info = _info;
    if (c == null || info == null) return;
    final f = n.clamp(0, info.frameCount - 1);
    setState(() => _frame = f);
    await c.seekTo(
      Duration(microseconds: ((f + 0.5) / info.fps * 1e6).round()),
    );
  }

  void _step(int delta) {
    if (_rangePlaying) _stopRange();
    _seek(_frame + delta);
  }

  Future<void> _playRange() async {
    final c = _ctrl;
    final info = _info;
    if (c == null || info == null) return;
    await c.seekTo(
      Duration(microseconds: ((_first + 0.5) / info.fps * 1e6).round()),
    );
    await c.setVolume(1);
    setState(() => _rangePlaying = true);
    await c.play();
  }

  Future<void> _stopRange() async {
    final c = _ctrl;
    if (c == null) return;
    setState(() => _rangePlaying = false);
    await c.pause();
    await c.setVolume(0);
    await _seek(_last);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final big = HardwareKeyboard.instance.isShiftPressed;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _step(big ? -10 : -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _step(big ? 10 : 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _step(-1 << 30);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _step(1 << 30);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _apply() async {
    final info = _info;
    if (info == null) return;
    final kept = _last - _first + 1;
    final cut = info.frameCount - kept;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('트림 저장'),
        content: Text(
          '앞 $_first 프레임, 뒤 ${info.frameCount - 1 - _last} 프레임'
          '(합계 $cut 프레임)을 잘라냅니다.\n'
          '남는 길이는 ${(kept / info.fps).toStringAsFixed(2)}초입니다.\n\n'
          '원본 파일을 덮어쓰며 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    // 파일을 갈아치우기 전에 플레이어가 잡고 있는 핸들을 놓게 한다.
    await _ctrl?.pause();
    try {
      final seconds = await VideoEdit.trim(
        widget.path,
        first: _first,
        last: _last,
        fps: info.fps,
      );
      if (mounted) Navigator.pop(context, seconds);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: panelBg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: _onKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      '영상 트림',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.path.split('/').last,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text('$_error', textAlign: TextAlign.center),
      );
    }
    final c = _ctrl;
    final info = _info;
    if (c == null || info == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: Container(
            constraints: const BoxConstraints(minHeight: 260),
            decoration: BoxDecoration(
              color: previewBg,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _readout(info),
        _scrubber(info),
        const SizedBox(height: 4),
        _stepBar(),
        const Divider(height: 26),
        _rangeBar(info),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              '← → 프레임 이동 · Shift+← → 10프레임',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: .35)),
            ),
            const Spacer(),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: _saving || (_first == 0 && _last == info.frameCount - 1)
                  ? null
                  : _apply,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.content_cut, size: 16),
              label: Text(_saving ? '저장 중…' : '잘라서 저장'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _readout(VideoInfo info) {
    final t = _frame / info.fps;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            '프레임 $_frame',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            ' / ${info.frameCount - 1}',
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
          const SizedBox(width: 12),
          Text(
            '${t.toStringAsFixed(3)}s',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white54,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          Text(
            '${info.width}×${info.height} · ${info.fps.toStringAsFixed(info.fps % 1 == 0 ? 0 : 2)}fps',
            style: const TextStyle(fontSize: 11, color: Colors.white30),
          ),
        ],
      ),
    );
  }

  /// 프레임 스크러버. 남길 구간을 트랙 위에 그려서 잘려나갈 쪽이 눈에 보이게 한다.
  Widget _scrubber(VideoInfo info) {
    final max = (info.frameCount - 1).toDouble();
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 6,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 배경 트랙(전체) + 남길 구간 하이라이트.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: LayoutBuilder(
              builder: (_, box) {
                final w = box.maxWidth;
                double x(int f) => max == 0 ? 0 : f / max * w;
                return SizedBox(
                  height: 6,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      Positioned(
                        left: x(_first),
                        width: (x(_last) - x(_first)).clamp(2.0, w),
                        top: 0,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent2,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Slider(
            value: _frame.toDouble().clamp(0, max),
            min: 0,
            max: max,
            divisions: info.frameCount > 1 ? info.frameCount - 1 : null,
            onChanged: (v) {
              if (_rangePlaying) _stopRange();
              _seek(v.round());
            },
          ),
        ],
      ),
    );
  }

  Widget _stepBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepButton(Icons.first_page, '처음', () => _step(-1 << 30)),
        _StepButton(Icons.keyboard_double_arrow_left, '-10', () => _step(-10)),
        _StepButton(Icons.chevron_left, '-1', () => _step(-1)),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          onPressed: _rangePlaying ? _stopRange : _playRange,
          tooltip: _rangePlaying ? '정지' : '구간 재생',
          icon: Icon(_rangePlaying ? Icons.stop : Icons.play_arrow, size: 20),
        ),
        const SizedBox(width: 10),
        _StepButton(Icons.chevron_right, '+1', () => _step(1)),
        _StepButton(Icons.keyboard_double_arrow_right, '+10', () => _step(10)),
        _StepButton(Icons.last_page, '끝', () => _step(1 << 30)),
      ],
    );
  }

  /// 남길 구간 지정 — 지금 보고 있는 프레임을 시작/끝으로 찍는다.
  Widget _rangeBar(VideoInfo info) {
    final kept = _last - _first + 1;
    final cut = info.frameCount - kept;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _frame > _last ? null : () => setState(() => _first = _frame),
                icon: const Icon(Icons.arrow_right_alt, size: 16),
                label: Text('여기부터 (프레임 $_frame)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _frame < _first ? null : () => setState(() => _last = _frame),
                icon: const Icon(Icons.keyboard_tab, size: 16),
                label: Text('여기까지 (프레임 $_frame)'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: (_first == 0 && _last == info.frameCount - 1)
                  ? null
                  : () => setState(() {
                        _first = 0;
                        _last = info.frameCount - 1;
                      }),
              child: const Text('초기화'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: previewBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Text(
                '남길 구간  $_first ~ $_last',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$kept프레임 · ${(kept / info.fps).toStringAsFixed(2)}초',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const Spacer(),
              Text(
                cut == 0
                    ? '자를 프레임 없음'
                    : '$cut프레임 잘라냄 (${(info.duration).toStringAsFixed(2)}초 → ${(kept / info.fps).toStringAsFixed(2)}초)',
                style: TextStyle(
                  fontSize: 11,
                  color: cut == 0 ? Colors.white30 : Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton(this.icon, this.tooltip, this.onTap);
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 19),
      );
}
