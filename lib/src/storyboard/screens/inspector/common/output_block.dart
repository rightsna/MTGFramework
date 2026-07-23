part of '../inspector_panel.dart';

class _OutputBlock extends StatelessWidget {
  const _OutputBlock({
    required this.title,
    required this.path,
    required this.busyKey,
    this.isVideo = false,
    this.deleteTarget,
    this.trimTarget,
  });

  final String title;
  final String? path;
  final String busyKey;
  final bool isVideo;

  /// 지정하면 '삭제' 버튼이 붙는다 — 이 샷의 해당 생성물(프레임/영상)만 지운다.
  final ({Shot shot, GenMode mode})? deleteTarget;

  /// 지정하면 '트림' 버튼이 붙는다(영상 전용) — 프레임 단위로 보며 앞뒤를 잘라낸다.
  final Shot? trimTarget;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 제목 오른쪽에 다루기 버튼(열기·폴더·트림·삭제)을 아이콘만 붙인다 — 미리보기 아래에
        // 따로 줄을 두면 패널만 길어진다. 생성물이 있을 때만 보인다.
        Row(
          children: [
            _SectionLabel(title),
            const Spacer(),
            if (path != null) ...[
              _MediaAction(
                icon: Icons.open_in_new,
                label: '열기',
                onTap: () => p.openFile(path!),
              ),
              _MediaAction(
                icon: Icons.folder_open_outlined,
                label: '폴더에서 보기',
                onTap: () => p.revealInFinder(path!),
              ),
              if (trimTarget != null)
                _MediaAction(
                  icon: Icons.content_cut,
                  label: '트림',
                  onTap: () async {
                    final seconds =
                        await showVideoTrimDialog(context, path: path!);
                    if (seconds != null) {
                      await p.applyTrim(trimTarget!, seconds);
                    }
                  },
                ),
              if (deleteTarget != null)
                _MediaAction(
                  icon: Icons.delete_outline,
                  label: '삭제',
                  color: Colors.redAccent,
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('$title 삭제'),
                        content: Text(
                          '이 샷의 $title을(를) 지웁니다.\n'
                          '파일도 함께 삭제되며 되돌릴 수 없습니다.\n\n'
                          '${path!.split('/').last}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('취소'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.redAccent),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('삭제'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await p.removeMedia(
                          deleteTarget!.shot, deleteTarget!.mode);
                    }
                  },
                ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 180,
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
          child: OutputPreview(
            path: path,
            version: p.verOf(busyKey),
            busy: p.isBusy(busyKey),
            isVideo: isVideo,
            fit: BoxFit.contain,
            onOpen: path == null ? null : () => p.openFile(path!),
            // 이미지(시작·끝장면)는 클릭하면 확대 팝업 — 영상은 탭이 재생이라 제외.
            onImageTap: (isVideo || path == null)
                ? null
                : () => showImageZoomDialog(
                      context,
                      path: path!,
                      version: p.verOf(busyKey),
                      title: title,
                    ),
            // 영상은 그 자리서 재생하지 말고 팝업으로 크게 — 씬의 영상들을 이어서 재생하며
            // 대사 음성·씬 배경음도 함께 튼다.
            onVideoTap: (isVideo && path != null)
                ? () => showVideoPlayDialog(context,
                    playlist: p.scenePlaylist(),
                    startPath: path!,
                    bgmPath: p.scenePlayBgmPath)
                : null,
          ),
        ),
      ],
    );
  }
}

