part of '../inspector_panel.dart';

/// 씬 공통 프롬프트 입력 — 이 씬의 모든 샷 프레임 생성에 함께 붙는 문구(씬 단위).
class _SceneCommonField extends StatefulWidget {
  const _SceneCommonField({super.key});

  @override
  State<_SceneCommonField> createState() => _SceneCommonFieldState();
}

class _SceneCommonFieldState extends State<_SceneCommonField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: StoryboardScope.read(context).selectedScene?.commonPrompt ?? '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      minLines: 3,
      maxLines: 8,
      style: const TextStyle(fontSize: 13, height: 1.4),
      onChanged: (v) => StoryboardScope.read(context).setSceneCommonPrompt(v),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: const InputDecoration(
        hintText: '예: 이 씬의 장소·분위기·시간대…',
        isDense: true,
        filled: true,
        fillColor: previewBg,
        border: OutlineInputBorder(),
      ),
    );
  }
}
