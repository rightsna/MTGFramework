import 'package:flutter/material.dart';

/// 미리보기에서 투명 영역을 검정과 구분되게 보여주는 체커보드(출력엔 영향 없음).
class CheckerPainter extends CustomPainter {
  const CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF2A2A2E));
    final light = Paint()..color = const Color(0xFF3C3C42);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x ~/ cell) + (y ~/ cell)).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), light);
        }
      }
    }
  }

  @override
  bool shouldRepaint(CheckerPainter oldDelegate) => false;
}
