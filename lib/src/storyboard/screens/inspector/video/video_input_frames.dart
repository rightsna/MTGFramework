part of '../inspector_panel.dart';

/// 영상이 아직 없을 때 영상칸에 대신 놓는 **생성 입력 장면** 미리보기.
/// FE2V면 시작·끝 두 장, I2V면 시작 한 장. 탭하면 확대. 읽기만 하고 편집은 장면 탭에서.
class _VideoInputFrames extends StatelessWidget {
  const _VideoInputFrames({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final start = p.startPathOf(shot); // 연동 중이면 앞 샷의 끝장면
    final end = p.shotNeedsEndFrame(shot) ? p.shotEndImage(shot) : null;

    Widget frame(String label, String? path, GenMode mode) {
      final key = p.busyKey(shot.id, mode);
      return Expanded(
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: previewBg,
            borderRadius: BorderRadius.circular(10),
            // 영상이 아니라 장면을 대신 보여주는 중 — **빨간 테두리**로 아직 미생성임을 강조.
            border: Border.all(color: Colors.redAccent, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: OutputPreview(
            path: path,
            version: p.verOf(key),
            busy: p.isBusy(key),
            fit: BoxFit.contain,
            onImageTap: path == null
                ? null
                : () => showImageZoomDialog(context,
                    path: path, version: p.verOf(key), title: label),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const _SectionLabel('영상'),
            const SizedBox(width: 8),
            const Text('아직 없음 — 생성에 쓸 프레임',
                style: TextStyle(fontSize: 11, color: Color(0x66FFFFFF))),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            frame('시작', start, GenMode.imageStart),
            if (p.shotNeedsEndFrame(shot)) ...[
              const SizedBox(width: 8),
              frame('끝', end, GenMode.imageEnd),
            ],
          ],
        ),
      ],
    );
  }
}
