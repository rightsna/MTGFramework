import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../providers/storyboard_provider.dart';
import '../ui.dart';

/// 캔버스 하단 배경음 섹션 (씬 단위 BGM).
/// 선택 씬의 스타일 태그·길이로 ACE-Step 인스트루멘탈 BGM(/bgm)을 생성·재생한다.
class BgmSection extends StatelessWidget {
  const BgmSection({super.key});

  static const double height = 200;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    if (sc == null) return const SizedBox.shrink();
    final status = p.apiStatus;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: panelBg,
        border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, size: 16, color: accent2),
              const SizedBox(width: 6),
              const Text('배경음 · 씬 BGM',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: accent2)),
              const Spacer(),
              if (status.reachable && !status.audioReady)
                const Text('· 배경음 워크플로 미설치(bgm)',
                    style:
                        TextStyle(fontSize: 11, color: Colors.orangeAccent)),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: _BgmControls(key: ValueKey(sc.id))),
                const SizedBox(width: 18),
                const Expanded(flex: 4, child: _BgmPlayerBox()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 왼쪽: 스타일 프롬프트 + 길이 슬라이더 + 생성 버튼. 씬이 바뀌면 key로 재생성돼 값 갱신.
class _BgmControls extends StatefulWidget {
  const _BgmControls({super.key});

  @override
  State<_BgmControls> createState() => _BgmControlsState();
}

class _BgmControlsState extends State<_BgmControls> {
  late final TextEditingController _prompt = TextEditingController(
      text: StoryboardScope.read(context).selectedScene?.bgmPrompt ?? '');
  late double _seconds =
      (StoryboardScope.read(context).selectedScene?.bgmSeconds ?? 30)
          .toDouble()
          .clamp(10, 120);

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    final key = sc == null ? '' : p.bgmBusyKey(sc.id);
    final busy = p.isBusy(key);
    final ready = p.bgmReady; // 서버 연결 + bgm 워크플로 있어야 생성 가능
    Widget genBtn = FilledButton.icon(
      onPressed: (busy || !ready)
          ? null
          : () {
              p.setSceneBgmPrompt(_prompt.text);
              p.genBgm();
            },
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.graphic_eq, size: 18),
      label: Text(busy ? '생성 중…' : '배경음 생성'),
    );
    if (!ready && p.bgmBlockReason != null) {
      genBtn = Tooltip(message: p.bgmBlockReason!, child: genBtn);
    }
    // 세로 스택 — 좁은 폭(패널 열림 등)에서도 넘치지 않게. 프롬프트 위 → 슬라이더·버튼 아래.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 스타일 태그 입력 — 남는 세로 공간을 채운다.
        Expanded(
          child: TextField(
            controller: _prompt,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 13, height: 1.35),
            onTapOutside: (_) {
              p.setSceneBgmPrompt(_prompt.text);
              FocusManager.instance.primaryFocus?.unfocus();
            },
            decoration: const InputDecoration(
              isDense: true,
              filled: true,
              fillColor: previewBg,
              border: OutlineInputBorder(),
              hintText:
                  '스타일 태그 (씬 단위·인스트루멘탈) — 예: cinematic, ambient, calm, piano',
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 길이 슬라이더(전체폭 — 슬라이더가 Expanded라 어떤 폭에도 맞춤).
        Row(
          children: [
            const Text('길이', style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: _seconds,
                min: 10,
                max: 120,
                divisions: 11,
                label: '${_seconds.round()}초',
                onChanged: (v) => setState(() => _seconds = v),
                onChangeEnd: (v) => p.setSceneBgmSeconds(v.round()),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text('${_seconds.round()}초',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        genBtn,
      ],
    );
  }
}

/// 오른쪽: 생성된 배경음 재생 + 열기/내보내기.
class _BgmPlayerBox extends StatelessWidget {
  const _BgmPlayerBox();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    final path = sc?.bgmPath;
    final key = sc == null ? '' : p.bgmBusyKey(sc.id);
    final busy = p.isBusy(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('생성된 배경음',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Color(0xAAFFFFFF))),
            const Spacer(),
            if (path != null) ...[
              TextButton.icon(
                onPressed: () => p.openFile(path),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('열기'),
              ),
              TextButton.icon(
                onPressed: () => p.revealInFinder(path),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('폴더'),
              ),
              TextButton.icon(
                onPressed: () => p.exportFile(path),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('내보내기'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: previewBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: path != null
                    ? const Color(0x335BD1C0)
                    : const Color(0x14FFFFFF),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: busy
                ? const Center(child: CircularProgressIndicator())
                : path == null
                    ? const Center(
                        child: Text('아직 생성된 배경음이 없습니다',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 12)),
                      )
                    : _BgmPlayer(
                        key: ValueKey('$path:${p.verOf(key)}'),
                        path: path,
                        onOpen: () => p.openFile(path),
                      ),
          ),
        ),
      ],
    );
  }
}

/// 인라인 오디오 플레이어. 새 의존성 없이 video_player로 mp3를 재생한다
/// (macOS AVPlayer는 오디오 전용 파일 재생 가능). 초기화 실패 시 '열기' 폴백.
class _BgmPlayer extends StatefulWidget {
  const _BgmPlayer({super.key, required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  State<_BgmPlayer> createState() => _BgmPlayerState();
}

class _BgmPlayerState extends State<_BgmPlayer> {
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
