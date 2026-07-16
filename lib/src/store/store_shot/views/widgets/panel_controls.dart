import 'package:flutter/material.dart';

import '../../../l10n/app_locale.dart';

/// 패널 섹션 제목.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      );
}

/// 라벨 + 슬라이더 + 값 텍스트 한 줄. [enabled]가 false면 비활성.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 72, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          SizedBox(
              width: 48, child: Text(valueText, textAlign: TextAlign.end)),
        ],
      );
}

/// 정렬 버튼 한 줄(아이콘 3개). [onTap]이 null이면 비활성.
class AlignRow extends StatelessWidget {
  const AlignRow({
    super.key,
    required this.label,
    required this.icons,
    this.onTap,
  });

  final String label;
  final List<IconData> icons;
  final void Function(int)? onTap;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 72, child: Text(label)),
          for (var i = 0; i < icons.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: OutlinedButton(
                onPressed: onTap == null ? null : () => onTap!(i),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                ),
                child: Icon(icons[i], size: 20),
              ),
            ),
        ],
      );
}

/// 베젤 색 스와치. [color]가 null이면 "베젤없음" 스와치(어두운 칸 + 금지 아이콘).
class BezelSwatch extends StatelessWidget {
  const BezelSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.white24;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color ?? const Color(0xFF1A1A1D),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border, width: selected ? 3 : 1),
        ),
        child: color == null
            ? const Icon(Icons.block, size: 15, color: Colors.white54)
            : null,
      ),
    );
  }
}

/// 소스 이미지 한 칸(불러오기/편집/제거 버튼 포함).
class SourceTile extends StatelessWidget {
  const SourceTile({
    super.key,
    required this.label,
    required this.name,
    required this.hint,
    required this.onPick,
    this.onEdit,
    this.onClear,
  });

  final String label;
  final String? name;
  final String hint;
  final VoidCallback? onPick;
  final VoidCallback? onEdit;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: Icon(name == null ? Icons.image_outlined : Icons.image),
        title: Text('$label — ${name ?? tr(context, '미선택', 'none')}',
            overflow: TextOverflow.ellipsis),
        subtitle: Text(hint, style: const TextStyle(fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null && name != null)
              IconButton(
                tooltip: tr(context, '이미지 에디터로 편집', 'Edit in Image Editor'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit,
              ),
            if (onClear != null && name != null)
              IconButton(
                tooltip: tr(context, '제거', 'Remove'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
            TextButton(
              onPressed: onPick,
              child: Text(tr(context, '불러오기', 'Load')),
            ),
          ],
        ),
      ),
    );
  }
}
