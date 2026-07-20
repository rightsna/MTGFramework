part of 'canvas_view.dart';

/// 캔버스 자체를 꾸미는 정적 위젯 — 카드 사이 화살표, 도트 그리드 배경, 메모 패널.

/// 샷 사이 흐름 화살표 — 카드 상단 근처(헤더/대사 높이)에 맞춰 배치.
class _ShotArrow extends StatelessWidget {
  const _ShotArrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 40, left: 4, right: 4),
      child: Icon(Icons.arrow_right_alt, color: accent, size: 30),
    );
  }
}

/// 캔버스 도트 그리드 배경.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const _step = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0x0AFFFFFF);
    for (var x = 0.0; x < size.width; x += _step) {
      for (var y = 0.0; y < size.height; y += _step) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
