part of '../inspector_panel.dart';

/// 원문 프롬프트와 한국어 번역을 **한 칸으로** — 위의 [원본|번역] 토글로 전환한다.
/// 두 칸을 쌓으면 패널만 길어져, 실제로 보는 하나만 띄운다. 토글 선택은 **유지된다**
/// (설정에 저장 — 다음 샷·다음 실행에도 마지막으로 본 쪽으로 열린다). 기본은 원문.
class _PromptPair extends StatelessWidget {
  const _PromptPair({
    required this.label,
    required this.controller,
    required this.koController,
    required this.hint,
    this.readOnly = false,
    this.trailing,
  });

  final String label;
  final TextEditingController controller; // 원문(생성에 실제로 쓰임)
  final TextEditingController koController; // 번역(확인용)
  final String hint;
  final bool readOnly;
  final Widget? trailing; // 라벨 우측(복사 버튼 등)

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final ko = p.promptShowKo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SectionLabel(label),
            const SizedBox(width: 8),
            _MiniToggle(
              left: '원본',
              right: '번역',
              rightSelected: ko,
              onChanged: p.setPromptShowKo,
            ),
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 6),
        _PromptField(
          controller: ko ? koController : controller,
          hint: ko ? '위 프롬프트를 한국어로 — 확인용이고 생성엔 안 쓰임' : hint,
          readOnly: readOnly,
        ),
      ],
    );
  }
}

