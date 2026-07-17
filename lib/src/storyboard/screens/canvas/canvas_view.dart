import 'package:flutter/material.dart';

import '../../models/shot.dart';
import '../../models/dialogue_beat.dart';
import '../../providers/storyboard_provider.dart';
import '../../services/api_service.dart';
import '../common/output_preview.dart';
import '../common/voice_play_button.dart';
import '../ui.dart';

/// 대사(TTS·샷) 식별색.
const _voiceColor = Color(0xFFE0678A);

/// 가운데 캔버스: 선택 씬을 **샷들의 가로 타임라인**으로 그린다.
/// 각 대사 = [상태] + [대사 내용(0/1)] + [샷들]. 대사 한 마디 아래 샷들이 화면을 덮는다.
class CanvasView extends StatelessWidget {
  const CanvasView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    if (p.selectedScene == null) {
      return _empty(
        '왼쪽에서 씬을 추가/선택하세요',
        FilledButton.icon(
          onPressed: p.addScene,
          icon: const Icon(Icons.add),
          label: const Text('씬 추가'),
        ),
      );
    }
    final dialogues = p.dialogues;
    if (dialogues.isEmpty) {
      return _empty(
        '첫 대사를 추가하세요 (대사 한 마디 = 샷 여러 개)',
        FilledButton.icon(
          onPressed: p.addDialogue,
          icon: const Icon(Icons.add),
          label: const Text('대사 추가'),
        ),
      );
    }
    // 캔버스: 줌 인/아웃 + 상하좌우 팬(InteractiveViewer). 도트 그리드 배경 위에
    // 대사 카드가 가로로 이어지고 사이사이 화살표로 흐름을 표시. 카드 높이는 샷 수에 맞춰 fit.
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(600),
      minScale: 0.3,
      maxScale: 1.8,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Padding(
            padding: const EdgeInsets.all(44),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < dialogues.length; i++) ...[
                  SizedBox(
                      width: 286, child: _ShotCard(beat: dialogues[i], index: i)),
                  if (i < dialogues.length - 1) const _ShotArrow(),
                ],
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 34),
                  child: SizedBox(
                    width: 56,
                    child: OutlinedButton(
                      onPressed: p.addDialogue,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        side: const BorderSide(color: Color(0x33FFFFFF)),
                      ),
                      child: const Icon(Icons.add),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String text, Widget button) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text(text), const SizedBox(height: 12), button],
        ),
      );
}

/// 대사 카드: [상태 스트립] + [헤더] + [대사] + [샷들] + [메모].
class _ShotCard extends StatelessWidget {
  const _ShotCard({required this.beat, required this.index});

  final DialogueBeat beat;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final selected = beat.id == p.selectedDialogueId;
    final card = Card(
      elevation: selected ? 8 : 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? accent : const Color(0x14FFFFFF),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusStrip(beat: beat),
          // 헤더
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2A2550), Color(0xFF1C2030)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
            ),
            padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('대사 ${index + 1}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 1.0,
                              color: Color(0xAAFFFFFF))),
                      if (beat.title.trim().isNotEmpty)
                        Text(beat.title.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () => p.removeDialogue(beat),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '대사 삭제',
                ),
              ],
            ),
          ),
          // 대사(0/1)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: _DialogueBox(beat: beat),
          ),
          // 샷들 — 3열 정사각 그리드. 높이는 샷 수(행)에 맞춰 자란다.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            child: _ShotsArea(beat: beat),
          ),
        ],
      ),
    );
    // 메모는 샷 박스 안이 아니라, 카드 아래에 독립 라운드박스로 분리해서 붙인다.
    final Widget content = beat.note.trim().isEmpty
        ? card
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              card,
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _NoteBox(text: beat.note.trim()),
              ),
            ],
          );
    // 몸통(배경) 탭 → 이 대사 선택. 앞쪽의 샷·상태 스트립·대사·삭제·＋ 버튼은
    // 각자 제스처를 먼저 가져가고(자식 우선), 그 외 빈 배경 탭만 여기로 떨어진다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => p.selectDialogue(beat.id),
      child: content,
    );
  }
}

/// 샷 최상단 상태 스트립 — 탭하면 다음 상태로 순환.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.beat});

  final DialogueBeat beat;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final c = statusColor(beat.status);
    return GestureDetector(
      onTap: () => p.cycleDialogueStatus(beat),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: c.withValues(alpha: 0.20),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Icon(statusIcon(beat.status), size: 13, color: c),
            const SizedBox(width: 5),
            Text(beat.status.label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: c)),
          ],
        ),
      ),
    );
  }
}

/// 대사 박스 — 화자 + 텍스트 + 음성 상태. 탭 → 이 대사를 선택(편집은 우측 '대사' 탭).
class _DialogueBox extends StatelessWidget {
  const _DialogueBox({required this.beat});

  final DialogueBeat beat;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final d = beat.dialogue;
    if (d == null) {
      return InkWell(
        onTap: () => p.selectDialogue(beat.id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x22E0678A)),
          ),
          child: const Row(
            children: [
              Icon(Icons.add, size: 14, color: _voiceColor),
              SizedBox(width: 6),
              Text('대사 입력',
                  style: TextStyle(fontSize: 12, color: _voiceColor)),
            ],
          ),
        ),
      );
    }
    final speaker = p.characterById(d.speakerId);
    final isNarration = d.speakerId == null;
    final busy = p.isBusy(p.voiceBusyKey(beat.id));
    return InkWell(
      onTap: () => p.selectDialogue(beat.id),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: const Color(0x14E0678A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x33E0678A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isNarration ? Icons.menu_book_outlined : Icons.person,
                    size: 12,
                    color: isNarration ? Colors.white38 : _voiceColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isNarration
                        ? '내레이션'
                        : ((speaker?.name.trim().isNotEmpty ?? false)
                            ? speaker!.name.trim()
                            : '(이름 없음)'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isNarration ? Colors.white54 : Colors.white),
                  ),
                ),
                if (busy)
                  const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else if (d.hasVoice)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    VoicePlayButton(
                      key: ValueKey('${d.voicePath}:${d.voiceSeconds}'),
                      path: d.voicePath!,
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    Text(fmtSeconds(d.voiceSeconds),
                        style: const TextStyle(fontSize: 10, color: accent2)),
                  ])
                else
                  const Icon(Icons.mic_none_outlined,
                      size: 12, color: Colors.white24),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              d.text.trim().isEmpty ? '(대사 없음)' : d.text.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: d.text.trim().isEmpty
                      ? Colors.white30
                      : const Color(0xDDFFFFFF)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 대사의 샷들 — **3열 정사각 그리드** + 추가 타일. 탭하면 그 샷 선택(인스펙터가 편집).
/// shrinkWrap이라 그리드 높이가 행 수(샷 수)에 맞춰 자라고 → 대사 카드 높이도 따라 fit 된다.
class _ShotsArea extends StatelessWidget {
  const _ShotsArea({required this.beat});

  final DialogueBeat beat;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('샷',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: accent2)),
            const SizedBox(width: 5),
            Text('${beat.shots.length}',
                style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1, // 정사각
          children: [
            for (var i = 0; i < beat.shots.length; i++)
              _ShotThumb(beat: beat, shot: beat.shots[i], index: i),
            _AddShotTile(beat: beat),
          ],
        ),
      ],
    );
  }
}

/// 정사각 샷 썸네일 — 시작이미지 + 오버레이(번호·삭제·하단 영상상태/길이). 그리드 셀을 꽉 채운다.
class _ShotThumb extends StatelessWidget {
  const _ShotThumb(
      {required this.beat, required this.shot, required this.index});

  final DialogueBeat beat;
  final Shot shot;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final selected = shot.id == p.selectedShotId && beat.id == p.selectedDialogueId;
    final hasVideo = shot.videoPath != null;
    return GestureDetector(
      onTap: () => p.selectShot(beat.id, shot.id),
      child: Container(
        decoration: BoxDecoration(
          color: previewBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? accent : const Color(0x18FFFFFF),
              width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            OutputPreview(
              path: p.startPathOf(shot),
              version: p.verOf(p.busyKey(shot.id, GenMode.imageStart)),
              busy: p.isBusy(p.busyKey(shot.id, GenMode.imageStart)),
            ),
            Positioned(
              left: 3,
              top: 3,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${index + 1}',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ),
            Positioned(
              right: 1,
              top: 1,
              child: GestureDetector(
                onTap: () => p.removeShot(beat, shot),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                      color: Color(0xAA000000), shape: BoxShape.circle),
                  child: const Icon(Icons.close,
                      size: 11, color: Colors.white70),
                ),
              ),
            ),
            // 하단 상태 스트립: 영상 생성 여부 + 길이.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                color: const Color(0x99000000),
                child: Row(
                  children: [
                    Icon(hasVideo ? Icons.check_circle : Icons.movie_outlined,
                        size: 9, color: hasVideo ? accent2 : Colors.white38),
                    const SizedBox(width: 3),
                    Text('${shot.videoSeconds}s',
                        style: const TextStyle(
                            fontSize: 9, color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 샷 추가 타일 — 그리드 셀 가운데의 원형 + 버튼.
class _AddShotTile extends StatelessWidget {
  const _AddShotTile({required this.beat});

  final DialogueBeat beat;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Center(
      child: InkWell(
        onTap: () => p.addShot(beat),
        customBorder: const CircleBorder(),
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0x14FFFFFF),
            border: Border.fromBorderSide(BorderSide(color: Color(0x2AFFFFFF))),
          ),
          child: const Icon(Icons.add, size: 14, color: Colors.white54),
        ),
      ),
    );
  }
}

/// 샷 메모(특이사항) — 앰버 톤 라운드 박스.
class _NoteBox extends StatelessWidget {
  const _NoteBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0x14E0A94A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33E0A94A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.sticky_note_2_outlined,
                size: 13, color: Color(0xFFE0A94A)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, height: 1.35, color: Color(0xCCFFFFFF))),
          ),
        ],
      ),
    );
  }
}

/// 샷 사이 흐름 화살표 — 카드 상단 근처(헤더/대사 높이)에 맞춰 배치.
class _ShotArrow extends StatelessWidget {
  const _ShotArrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 40, left: 4, right: 4),
      child: Icon(Icons.arrow_right_alt, color: accent, size: 30),
    );
  }
}

/// 캔버스 도트 그리드 배경.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const _step = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0x0AFFFFFF);
    for (var x = 0.0; x < size.width; x += _step) {
      for (var y = 0.0; y < size.height; y += _step) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

/// 초 표기(정수면 정수, 아니면 소수 1자리).
String fmtSeconds(double s) =>
    s == s.roundToDouble() ? '${s.toInt()}s' : '${s.toStringAsFixed(1)}s';

