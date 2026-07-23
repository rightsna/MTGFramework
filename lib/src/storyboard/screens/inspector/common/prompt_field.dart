part of '../inspector_panel.dart';

class _PromptField extends StatelessWidget {
  const _PromptField({
    required this.controller,
    required this.hint,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String hint;

  /// 연동으로 값이 따라 들어오는 칸 — 보여주기만 하고 고칠 수 없다.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return TextField(
      controller: controller,
      readOnly: readOnly,
      minLines: 4,
      // 길어도 칸이 같이 늘어나 내부 스크롤을 최대한 안 만든다(패널 자체 스크롤로 본다).
      maxLines: 40,
      style: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: readOnly ? Colors.white54 : null,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _hintStyle,
        isDense: true,
        filled: true,
        fillColor: previewBg,
        border: const OutlineInputBorder(),
      ),
      onChanged: readOnly ? null : (_) => p.save(),
    );
  }
}

