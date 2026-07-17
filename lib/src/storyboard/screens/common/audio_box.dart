import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../providers/storyboard_provider.dart';
import '../ui.dart';

/// 오디오(배경음 · 대사 음성) 공통 박스.
///
/// **배경음과 대사 음성은 같은 오디오**라 UI도 같아야 한다 — 액션 줄(열기·폴더·내보내기
/// + 추가 액션)과 재생 박스(시크바 + 재생/정지 + 시간)를 여기 한 군데서만 정의한다.
///
/// [path]=null 이면 [emptyText]를 띄운다. [version]은 파일이 같은 이름으로 새로 만들어졌을 때
/// 플레이어를 다시 만들기 위한 캐시 키.
class AudioBox extends StatelessWidget {
  const AudioBox({
    super.key,
    required this.path,
    required this.emptyText,
    this.busy = false,
    this.version = 0,
    this.extraActions = const [],
    this.footer,
  });

  /// 오디오 파일 경로. null = 아직 없음.
  final String? path;

  /// 파일이 없을 때 박스 안에 띄울 안내.
  final String emptyText;

  /// 생성/불러오기 진행 중이면 스피너.
  final bool busy;

  /// 같은 경로에 파일이 바뀌었을 때 플레이어를 새로 만들기 위한 버전.
  final int version;

  /// 열기·폴더·내보내기 뒤에 붙일 추가 액션(예: 대사 지우기).
  final List<Widget> extraActions;

  /// 박스 아래에 덧붙일 위젯(예: 커버리지 배지).
  final Widget? footer;

  static const double _boxHeight = 96;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final f = path;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 좁은 폭이라 라벨 달린 버튼은 넘친다 → 아이콘 버튼으로 압축.
        if (f != null || extraActions.isNotEmpty)
          Row(
            children: [
              const Spacer(),
              if (f != null) ...[
                IconButton(
                  tooltip: '열기',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () => p.openFile(f),
                  icon: const Icon(Icons.open_in_new),
                ),
                IconButton(
                  tooltip: '폴더에서 보기',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () => p.revealInFinder(f),
                  icon: const Icon(Icons.folder_open_outlined),
                ),
                IconButton(
                  tooltip: '내보내기',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () => p.exportFile(f),
                  icon: const Icon(Icons.download_outlined),
                ),
              ],
              ...extraActions,
            ],
          ),
        SizedBox(
          height: _boxHeight,
          child: Container(
            decoration: BoxDecoration(
              color: previewBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: f != null
                    ? const Color(0x335BD1C0)
                    : const Color(0x14FFFFFF),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: busy
                ? const Center(child: CircularProgressIndicator())
                : f == null
                    ? Center(
                        child: Text(emptyText,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                      )
                    : _AudioPlayer(
                        key: ValueKey('$f:$version'),
                        path: f,
                        onOpen: () => p.openFile(f),
                      ),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 6),
          footer!,
        ],
      ],
    );
  }
}

/// 인라인 오디오 플레이어. 새 의존성 없이 video_player로 mp3를 재생한다
/// (macOS AVPlayer는 오디오 전용 파일 재생 가능). 초기화 실패 시 '열기' 폴백.
class _AudioPlayer extends StatefulWidget {
  const _AudioPlayer({super.key, required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  State<_AudioPlayer> createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<_AudioPlayer> {
  late final VideoPlayerController _ctrl;
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(File(widget.path));
    _ctrl.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
    _ctrl.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTick);
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_ready) return;
    _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play();
    setState(() {});
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return InkWell(
        onTap: widget.onOpen,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.headphones_outlined, size: 30, color: accent2),
              SizedBox(height: 4),
              Text('열기 (외부 재생)', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    final v = _ctrl.value;
    final dur = v.duration;
    final pos = v.position > dur ? dur : v.position;
    final max = dur.inMilliseconds == 0 ? 1.0 : dur.inMilliseconds.toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            iconSize: 38,
            color: accent2,
            icon: Icon(v.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: pos.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                    max: max,
                    activeColor: accent2,
                    onChanged: (ms) =>
                        _ctrl.seekTo(Duration(milliseconds: ms.round())),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(pos),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54)),
                      Text(_fmt(dur),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
