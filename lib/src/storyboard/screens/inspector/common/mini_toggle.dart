part of '../inspector_panel.dart';

/// 작은 2단 토글 알약 — 프롬프트 원본/번역 전환용.
class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.left,
    required this.right,
    required this.rightSelected,
    required this.onChanged,
  });

  final String left;
  final String right;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String t, bool selected, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: selected ? accent2 : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(t,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.black : const Color(0x88FFFFFF))),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(left, !rightSelected, () => onChanged(false)),
        seg(right, rightSelected, () => onChanged(true)),
      ]),
    );
  }
}

