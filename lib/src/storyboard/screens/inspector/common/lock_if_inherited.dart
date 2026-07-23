part of '../inspector_panel.dart';

/// 따라가는(상속) 샷의 편집 영역을 통째로 잠근다 — 칸마다 readOnly를 물리는 대신 한 겹으로.
/// 잠긴 동안에도 **보이기는 그대로**여야 한다(트랙 1과 같은 내용을 쓰고 있다는 게 요점).
class _LockIfInherited extends StatelessWidget {
  const _LockIfInherited({required this.locked, required this.child});

  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) => locked
      ? IgnorePointer(child: Opacity(opacity: 0.55, child: child))
      : child;
}

