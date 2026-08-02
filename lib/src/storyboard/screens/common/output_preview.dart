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
    // 이미지(PNG/JPG/애니메이션 WebP) — **그려질 크기로만 디코드**한다.
    // 원본 그대로 풀면 704×1280 한 장이 3.4MB(픽셀×4바이트)라, 캔버스 한 씬(썸네일 100장)에
    // 수백 MB가 잡히고 Flutter 이미지 캐시(기본 100MB)를 넘겨 쫓겨났다 다시 푸는 일이 반복된다
    // — 프로젝트 처음 열 때 버벅이던 원인. 확대 팝업은 따로라 원본 화질 그대로다.
    return LayoutBuilder(
      builder: (context, box) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        // 폭이 무한(스크롤 안 등)일 땐 적당한 상한으로 — 그래도 원본보단 훨씬 작다.
        final w = box.hasBoundedWidth ? box.maxWidth : 400.0;
        final img = LazyFileImage(
          key: ValueKey('$p:$version'),
          path: p,
          fit: fit,
          cacheWidth: (w * dpr).clamp(64, 2048).round(),
        );
        if (onImageTap == null) return img;
        return GestureDetector(
          onTap: onImageTap,
          child: MouseRegion(cursor: SystemMouseCursors.zoomIn, child: img),
        );
      },
    );
  }
}

/// 파일 이미지를 **한 프레임에 몰아서 열지 않는** 로더.
///
/// 캔버스 한 화면에 썸네일이 십수 장인데, 그 위젯들이 한꺼번에 만들어지면 파일 열기·디코드
/// 요청이 한 프레임에 몰려 진입 순간 걸린다. 여기선 [_ImageAdmission]에서 자리를 받은
/// 것부터 순서대로 열고, 아직 차례가 아닌 칸은 빈 박스로 둔다(레이아웃은 그대로).
class LazyFileImage extends StatefulWidget {
  const LazyFileImage({
    super.key,
    required this.path,
    required this.fit,
    required this.cacheWidth,
  });

  final String path;
  final BoxFit fit;
  final int cacheWidth;

  @override
  State<LazyFileImage> createState() => _LazyFileImageState();
}

class _LazyFileImageState extends State<LazyFileImage> {
  bool _admitted = false;
  VoidCallback? _cancel;

  @override
  void initState() {
    super.initState();
    _request();
  }

  void _request() {
    _cancel = _ImageAdmission.request(() {
      if (mounted) setState(() => _admitted = true);
    });
  }

  @override
  void didUpdateWidget(LazyFileImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _cancel?.call();
      _admitted = false;
      _request();
    }
  }

  @override
  void dispose() {
    _cancel?.call(); // 화면 밖으로 나간 칸은 대기열에서 빠진다
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_admitted) return const SizedBox.expand();
    return Image.file(
      File(widget.path),
      fit: widget.fit,
      gaplessPlayback: true,
      cacheWidth: widget.cacheWidth,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}

/// 이미지 열기 **입장 순서** — 프레임당 [_perFrame]장씩만 들여보낸다.
/// (전역이라 캔버스·인스펙터가 같은 예산을 나눠 쓴다. 화면에서 사라진 요청은 취소된다.)
class _ImageAdmission {
  static const _perFrame = 3;
  static final List<VoidCallback> _queue = [];
  static bool _scheduled = false;

  /// [onAdmit]을 대기열에 넣고, 취소 함수를 돌려준다.
  static VoidCallback request(VoidCallback onAdmit) {
    _queue.add(onAdmit);
    _schedule();
    return () => _queue.remove(onAdmit);
  }

  static void _schedule() {
    if (_scheduled || _queue.isEmpty) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      for (var i = 0; i < _perFrame && _queue.isNotEmpty; i++) {
        _queue.removeAt(0)();
      }
      _schedule(); // 남았으면 다음 프레임에 이어서
    });
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
  /// 영상 디코더는 만드는 것 자체가 비싸다(파일 열기 + 플랫폼 채널). 그래서 이미지와 **같은
  /// 입장 대기열**([_ImageAdmission])을 거쳐 프레임을 나눠 연다 — 탭을 옮기거나 샷을 고르는
  /// 순간 여러 개가 한꺼번에 열려 걸리던 걸 막는다.
  VideoPlayerController? _ctrl;
  VoidCallback? _cancelAdmission;
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _cancelAdmission = _ImageAdmission.request(_open);
  }

  void _open() {
    if (!mounted) return;
    final c = VideoPlayerController.file(File(widget.path));
    _ctrl = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setLooping(true);
      setState(() => _ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
    c.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {}); // 재생/일시정지 아이콘 갱신
  }

  @override
  void dispose() {
    _cancelAdmission?.call(); // 아직 차례가 안 왔으면 대기열에서 뺀다
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  void _toggle() {
    // 팝업 등으로 넘길 거면 인라인 재생은 하지 않는다.
    if (widget.onTapOverride != null) {
      widget.onTapOverride!();
      return;
    }
    final c = _ctrl;
    if (!_ready || c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
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
    final c = _ctrl;
    if (!_ready || c == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final playing = c.value.isPlaying;
    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
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
