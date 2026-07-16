import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/app_locale.dart';

/// 앱 아이콘 소스를 실제 출력처럼 contain + 배경 적용한 모습으로 대표 크기 몇 개로
/// 미리 보여준다. 소스가 없으면 안내 문구를 표시. 입력만으로 그려지는 정적 위젯.
class AppIconPreview extends StatelessWidget {
  const AppIconPreview({
    super.key,
    required this.srcBytes,
    required this.bgColor,
  });

  final Uint8List? srcBytes;

  /// 미리보기 칸 배경색 — 투명 배경을 유지하는 경우 null.
  final Color? bgColor;

  static const _sizes = [180.0, 120.0, 76.0, 48.0];

  @override
  Widget build(BuildContext context) {
    final bytes = srcBytes;
    if (bytes == null) {
      return ColoredBox(
        color: const Color(0xFF1A1A1D),
        child: Center(
          child: Text(
              tr(context, '소스 이미지를 선택하세요 (정사각 1024×1024 권장)',
                  'Choose a source image (square 1024×1024 recommended)'),
              style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    return ColoredBox(
      color: const Color(0xFF1A1A1D),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 24,
          runSpacing: 24,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            for (final s in _sizes)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: s,
                    height: s,
                    color: bgColor,
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 6),
                  Text('${s.toInt()}px',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
