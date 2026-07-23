part of '../inspector_panel.dart';

/// 영상 생성 방식 옵션 카드 하나 — 선택되면 강조 테두리+틴트. 둘을 나란히 놓아 고른다.
class _VideoModeCard extends StatelessWidget {
  const _VideoModeCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : const Color(0x66FFFFFF);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.14) : const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accent : const Color(0x1FFFFFFF),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 5),
                  Text(title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: selected ? Colors.white : const Color(0xBBFFFFFF),
                      )),
                  const Spacer(),
                  if (selected)
                    const Icon(Icons.check_circle, size: 12, color: accent),
                ],
              ),
              const SizedBox(height: 2),
              Text(desc,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.white54, height: 1.25)),
            ],
          ),
        ),
      ),
    );
  }
}
