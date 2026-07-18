import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 생성 결과(이미지/영상) 미리보기 박스. 캔버스 카드와 인스펙터 출력 탭이 공유.
/// PNG/JPG/애니메이션 WebP는 이미지로, mp4/mov는 첫 프레임 + 탭 재생으로 보여준다.
class OutputPreview extends StatelessWidget {
  const OutputPreview({
    super.key,
    required this.path,
    required this.version,
    required this.busy,
    this.isVideo = false,
    this.fit = BoxFit.cover,
    this.onOpen,
    this.onImageTap,
    this.onVideoTap,
  });

  final String? path;
  final int version; // 같은 경로 재생성 시 캐시 무효화용
  final bool busy;
  final bool isVideo;
  final BoxFit fit;
  final VoidCallback? onOpen;

  /// 이미지(영상 아님)를 눌렀을 때 — 확대 팝업 등. 없으면 이미지는 그냥 표시만 한다.
  /// (영상은 탭이 재생/정지라 여기에 걸리지 않는다.)
  final VoidCallback? onImageTap;

  /// 영상을 눌렀을 때 — 지정하면 인라인 재생 대신 이걸 부른다(팝업 재생 등).
  /// 없으면 기존대로 그 자리에서 재생/정지한다.
  final VoidCallback? onVideoTap;

  static const _videoExts = {'.mp4', '.mov', '.m4v', '.webm'};

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = path;
    if (p == null) {
      return Center(
        child: Icon(isVideo ? Icons.movie_outlined : Icons.image_outlined,
            color: Colors.black26),
      );
    }
    final lower = p.toLowerCase();
    final isVid = _videoExts.any(lower.endsWith);
    if (isVid) {
      return _VideoPreview(
        key: ValueKey('$p:$version'),
        path: p,
        fit: fit,
        onOpen: onOpen,
        onTapOverride: onVideoTap,
      );
    }
    // 이미지(PNG/JPG/애니메이션 WebP)
    final img = Image.file(
      File(p),
      key: ValueKey('$p:$version'),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
    if (onImageTap == null) return img;
    return GestureDetector(
      onTap: onImageTap,
      child: MouseRegion(cursor: SystemMouseCursors.zoomIn, child: img),
    );
  }
}

/// 인라인 영상 미리보기: 첫 프레임을 보여주고 탭하면 재생/일시정지.
/// [onTapOverride]가 있으면 탭이 그걸 부른다(그 자리에서 재생하지 않고 팝업 등으로).
class _VideoPreview extends StatefulWidget {
  const _VideoPreview({
    super.key,
    required this.path,
    required this.fit,
    this.onOpen,
    this.onTapOverride,
  });

  final String path;
  final BoxFit fit;
  final VoidCallback? onOpen;
  final VoidCallback? onTapOverride;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late final VideoPlayerController _ctrl;
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(File(widget.path));
    _ctrl.initialize().then((_) {
      if (!mounted) return;
      _ctrl.setLooping(true);
      setState(() => _ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
    _ctrl.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {}); // 재생/일시정지 아이콘 갱신
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTick);
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    // 팝업 등으로 넘길 거면 인라인 재생은 하지 않는다.
    if (widget.onTapOverride != null) {
      widget.onTapOverride!();
      return;
    }
    if (!_ready) return;
    if (_ctrl.value.isPlaying) {
      _ctrl.pause();
    } else {
      _ctrl.play();
    }
    setState(() {}); // 아이콘 갱신(리스너도 갱신하지만 즉시 반영)
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
              Icon(Icons.play_circle_outline, size: 32, color: Colors.indigo),
              Text('열기', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    final playing = _ctrl.value.isPlaying;
    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _ctrl.value.size.width,
              height: _ctrl.value.size.height,
              child: VideoPlayer(_ctrl),
            ),
          ),
          // 일시정지 상태일 때만 재생 아이콘 오버레이.
          if (!playing)
            const Center(
              child: Icon(Icons.play_circle, size: 44, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}
