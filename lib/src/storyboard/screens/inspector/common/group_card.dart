part of '../inspector_panel.dart';

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.icon,
    required this.title,
    required this.child,
    this.done,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final bool? done;

  @override
  Widget build(BuildContext context) {
    final lit = done ?? false;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: lit ? const Color(0x335BD1C0) : const Color(0x1AFFFFFF),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent2),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (done != null) _DoneBadge(done: done!),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0x14FFFFFF)),
          ),
          child,
        ],
      ),
    );
  }
}

