part of '../inspector_panel.dart';

class _GenButton extends StatelessWidget {
  const _GenButton({
    required this.label,
    required this.icon,
    required this.busyKey,
    required this.onGen,
    this.enabled = true,
    this.disabledHint,
  });

  final String label;
  final IconData icon;
  final String busyKey;
  final VoidCallback onGen;
  final bool enabled;
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    final busy = StoryboardScope.of(context).isBusy(busyKey);
    final btn = FilledButton.icon(
      onPressed: (busy || !enabled) ? null : onGen,
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(busy ? '생성 중…' : label),
    );
    if (!enabled && disabledHint != null) {
      return Tooltip(message: disabledHint!, child: btn);
    }
    return btn;
  }
}

