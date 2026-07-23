part of '../inspector_panel.dart';

/// 가운데 안내(아이콘 + 제목 + 선택 부제) — 인스펙터 빈 상태 공용.
class _CenterNote extends StatelessWidget {
  const _CenterNote({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 40),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: Colors.white38)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white24),
            ),
          ],
        ],
      ),
    );
  }
}

