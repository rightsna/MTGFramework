part of '../inspector_panel.dart';

/// 비트 탭 — 비트 정보(메모·제목·연출 노트·대사)와 그 부속.

/// 비트 탭 — 선택 비트 정보(제목·비트 연출 노트·메모·대사).
class _BeatTab extends StatelessWidget {
  const _BeatTab();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final beat = p.selectedDialogue;
    if (beat == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, color: Colors.white24, size: 40),
            SizedBox(height: 10),
            Text('왼쪽에서 비트를 선택하세요', style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 비트 메모 — 영상·장면 탭과 마찬가지로 최상단에서 먼저 보인다.
          _ShotNote(controller: p.noteCtrl(beat.id)),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: accent2,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '비트 ${p.dialogues.indexOf(beat) + 1}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: Color(0xAAFFFFFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: p.titleCtrl(beat.id),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: '비트 제목 (선택)',
              hintStyle: _hintStyle,
              isDense: true,
              filled: true,
              fillColor: previewBg,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => p.noteEdited(),
          ),
          const SizedBox(height: 12),
          _DirectionNote(dialogueId: beat.id),
          const SizedBox(height: 14),
          // 대사 내용·화자·음성은 팝업 대신 이 탭에서 바로 편집한다.
          _DialogueEditor(key: ValueKey('dlg_${beat.id}'), beat: beat),
          const SizedBox(height: 14),
          // 효과음(SFX) — 대사와 비슷하나 화자가 없다. 트랙 공유.
          _SfxEditor(key: ValueKey('sfx_${beat.id}'), beat: beat),
        ],
      ),
    );
  }
}
