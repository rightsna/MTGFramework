part of '../inspector_panel.dart';

/// 비트 연출 노트 = 이 비트에서 **무엇을 표현할지**. 비트는 표현 단위이고, 대사는 그 표현을
/// 이루는 요소 중 하나일 뿐이다(대사 없이 연출만으로도 성립).
/// 메모(특이사항)와 달리 제작 지시에 해당하지만, 프롬프트로 자동으로 물리지는 않는다.
class _DirectionNote extends StatelessWidget {
  const _DirectionNote({required this.dialogueId});

  final String dialogueId;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0x145BD1C0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x335BD1C0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_filter_outlined, size: 15, color: accent2),
              const SizedBox(width: 6),
              const Text(
                '비트 연출 노트',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: accent2,
                ),
              ),
              const Spacer(),
              const Text(
                '무엇을 표현할지',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: p.directionCtrl(dialogueId),
            minLines: 6,
            maxLines: 30,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: const InputDecoration(
              hintText: '이 비트에서 무엇을 표현할지 (대사는 그중 하나)',
              isDense: true,
              filled: true,
              fillColor: previewBg,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => p.save(),
          ),
        ],
      ),
    );
  }
}
