part of '../inspector_panel.dart';

class _DoneBadge extends StatelessWidget {
  const _DoneBadge({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: done ? accent2 : Colors.white24,
        ),
        const SizedBox(width: 4),
        Text(
          done ? '생성됨' : '미생성',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: done ? accent2 : Colors.white38,
          ),
        ),
      ],
    );
  }
}

