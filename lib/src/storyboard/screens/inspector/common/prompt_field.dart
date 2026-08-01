part of '../inspector_panel.dart';

class _PromptField extends StatelessWidget {
  const _PromptField({
    required this.controller,
    required this.hint,
  });

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return TextField(
      controller: controller,
      minLines: 4,
      // 길어도 칸이 같이 늘어나 내부 스크롤을 최대한 안 만든다(패널 자체 스크롤로 본다).
      maxLines: 40,
      style: const TextStyle(fontSize: 14, height: 1.4),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _hintStyle,
        isDense: true,
        filled: true,
        fillColor: previewBg,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => p.save(),
    );
  }
}

