part of '../inspector_panel.dart';

/// 메모(특이사항) 상자. 프롬프트와 무관한 자유 기록 — 생성에 쓰이지 않는다.
/// 비트·샷 어디든 [controller]만 물리면 같은 생김새로 쓴다.
class _ShotNote extends StatelessWidget {
  const _ShotNote({super.key, required this.controller});

  final TextEditingController controller;

  static const _amber = Color(0xFFE0A94A);

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0x14E0A94A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33E0A94A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined, size: 15, color: _amber),
              const SizedBox(width: 6),
              const Text(
                '메모 · 특이사항',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: _amber,
                ),
              ),
              const Spacer(),
              const Text(
                '생성에 안 쓰임',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 6,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: const InputDecoration(
              hintText: '이 샷의 특이사항·참고를 자유롭게 기록 (프롬프트 아님)',
              hintStyle: _hintStyle,
              isDense: true,
              filled: true,
              fillColor: previewBg,
              border: OutlineInputBorder(),
            ),
            // 저장 + 즉시 갱신 — 캔버스의 메모 패널이 입력을 실시간으로 비춘다.
            onChanged: (_) => p.noteEdited(),
          ),
        ],
      ),
    );
  }
}

