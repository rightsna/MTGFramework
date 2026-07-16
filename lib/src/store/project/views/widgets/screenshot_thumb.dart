import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_locale.dart';

/// A single screenshot thumbnail: tap to reopen the document, or hover to reveal
/// an ✕ that deletes just that screenshot.
class ScreenshotThumb extends StatefulWidget {
  const ScreenshotThumb({
    super.key,
    required this.preview,
    required this.enabled,
    required this.onOpen,
    required this.onDelete,
    this.width = 50,
  });

  final File preview;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final double width;

  @override
  State<ScreenshotThumb> createState() => _ScreenshotThumbState();
}

class _ScreenshotThumbState extends State<ScreenshotThumb> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        width: widget.width,
        height: 84,
        child: Stack(
          children: [
            Positioned.fill(
              child: InkWell(
                onTap: widget.enabled ? widget.onOpen : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(
                    widget.preview,
                    fit: BoxFit.cover,
                    cacheWidth: 100,
                    errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined,
                        size: 16,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ),
            if (_hover && widget.enabled)
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: Tooltip(
                    message: tr(context, '스크린샷 삭제', 'Delete screenshot'),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Color(0xCC000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
