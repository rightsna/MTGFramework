part of '../inspector_panel.dart';

/// 제목 옆 액션 아이콘 하나(열기·폴더·트림·삭제) — 라벨은 툴팁으로만.
class _MediaAction extends StatelessWidget {
  const _MediaAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label; // 툴팁
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: label,
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        color: color ?? Colors.white70,
        icon: Icon(icon),
      );
}
