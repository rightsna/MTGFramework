import 'dart:io';

import 'package:flutter/material.dart';

/// 이미지를 화면 가득 확대해 보는 팝업 — 시작·끝장면 프레임을 크게 확인할 때.
/// 배경이나 닫기를 누르면 닫히고, 핀치/휠로 더 크게 볼 수 있다(InteractiveViewer).
Future<void> showImageZoomDialog(
  BuildContext context, {
  required String path,
  required int version, // 같은 경로 재생성 시 캐시 무효화용
  String? title,
}) =>
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xE6000000),
      builder: (ctx) => _ImageZoomDialog(path: path, version: version, title: title),
    );

class _ImageZoomDialog extends StatelessWidget {
  const _ImageZoomDialog({
    required this.path,
    required this.version,
    this.title,
  });

  final String path;
  final int version;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          // 이미지 바깥(여백)을 눌러도 닫힌다.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.opaque,
            ),
          ),
          Center(
            child: InteractiveViewer(
              maxScale: 6,
              child: Image.file(
                File(path),
                key: ValueKey('$path:$version'),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 120,
                  height: 120,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
          // 상단: 제목 + 닫기.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Row(
              children: [
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                  )
                else
                  const Spacer(),
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
}
