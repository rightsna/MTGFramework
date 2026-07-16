import 'package:flutter/material.dart';

import '../../models/clip.dart';
import '../../models/shot.dart';
import '../../providers/storyboard_provider.dart';
import '../../services/api_service.dart';
import '../common/output_preview.dart';
import '../common/voice_play_button.dart';
import '../ui.dart';

/// 대사(TTS·클립) 식별색.
const _voiceColor = Color(0xFFE0678A);

/// 가운데 캔버스: 선택 씬을 **샷들의 가로 타임라인**으로 그린다.
/// 각 샷 = [상태] + [대사(0/1)] + [클립들]. 샷 하나가 대사 한 마디고, 그 아래 클립들이 화면을 덮는다.
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
    final shots = p.shots;
    if (shots.isEmpty) {
      return _empty(
        '첫 샷을 추가하세요 (샷 = 대사 한 마디 + 클립들)',
        FilledButton.icon(
          onPressed: p.addShot,
          icon: const Icon(Icons.add),
          label: const Text('샷 추가'),
        ),
      );
    }
    // 캔버스: 줌 인/아웃 + 상하좌우 팬(InteractiveViewer). 도트 그리드 배경 위에
    // 샷 카드가 가로로 이어지고 사이사이 화살표로 흐름을 표시. 카드 높이는 클립 수에 맞춰 fit.
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
                for (var i = 0; i < shots.length; i++) ...[
                  SizedBox(
                      width: 286, child: _ShotCard(shot: shots[i], index: i)),
                  if (i < shots.length - 1) const _ShotArrow(),
                ],
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 34),
                  child: SizedBox(
                    width: 56,
                    child: OutlinedButton(
                      onPressed: p.addShot,
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

/// 샷 카드: [상태 스트립] + [헤더] + [대사] + [클립들] + [메모].
class _ShotCard extends StatelessWidget {
  const _ShotCard({required this.shot, required this.index});

  final Shot shot;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final selected = shot.id == p.selectedShotId;
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
          _StatusStrip(shot: shot),
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
                      Text('SHOT ${index + 1}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 1.0,
                              color: Color(0xAAFFFFFF))),
                      if (shot.title.trim().isNotEmpty)
                        Text(shot.title.trim(),
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
                  onPressed: () => p.removeShot(shot),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '샷 삭제',
                ),
              ],
            ),
          ),
          // 대사(0/1)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: _DialogueBox(shot: shot),
          ),
          // 클립들 — 3열 정사각 그리드. 높이는 클립 수(행)에 맞춰 자란다.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            child: _ClipsArea(shot: shot),
          ),
        ],
      ),
    );
    // 메모는 샷 박스 안이 아니라, 카드 아래에 독립 라운드박스로 분리해서 붙인다.
    final Widget content = shot.note.trim().isEmpty
        ? card
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              card,
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _NoteBox(text: shot.note.trim()),
              ),
            ],
          );
    // 몸통(배경) 탭 → 이 샷 선택. 앞쪽의 클립·상태 스트립·대사·삭제·＋ 버튼은
    // 각자 제스처를 먼저 가져가고(자식 우선), 그 외 빈 배경 탭만 여기로 떨어진다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => p.selectShot(shot.id),
      child: content,
    );
  }
}

/// 샷 최상단 상태 스트립 — 탭하면 다음 상태로 순환.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final c = statusColor(shot.status);
    return GestureDetector(
      onTap: () => p.cycleShotStatus(shot),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: c.withValues(alpha: 0.20),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Icon(statusIcon(shot.status), size: 13, color: c),
            const SizedBox(width: 5),
            Text(shot.status.label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: c)),
          ],
        ),
      ),
    );
  }
}

/// 샷의 대사 박스 — 화자 + 텍스트 + 음성 상태. 탭 → 편집 모달. 대사 없으면 "대사 추가".
class _DialogueBox extends StatelessWidget {
  const _DialogueBox({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final d = shot.dialogue;
    if (d == null) {
      return InkWell(
        onTap: () => editShotDialogue(context, shot),
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
              Text('대사 추가',
                  style: TextStyle(fontSize: 12, color: _voiceColor)),
            ],
          ),
        ),
      );
    }
    final speaker = p.characterById(d.speakerId);
    final isNarration = d.speakerId == null;
    final busy = p.isBusy(p.voiceBusyKey(shot.id));
    return InkWell(
      onTap: () => editShotDialogue(context, shot),
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
                    Text(_fmt(d.voiceSeconds),
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

/// 샷의 클립들 — **3열 정사각 그리드** + 추가 타일. 탭하면 그 클립 선택(인스펙터가 편집).
/// shrinkWrap이라 그리드 높이가 행 수(클립 수)에 맞춰 자라고 → 샷 카드 높이도 따라 fit 된다.
class _ClipsArea extends StatelessWidget {
  const _ClipsArea({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('클립',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: accent2)),
            const SizedBox(width: 5),
            Text('${shot.clips.length}',
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
            for (var i = 0; i < shot.clips.length; i++)
              _ClipThumb(shot: shot, clip: shot.clips[i], index: i),
            _AddClipTile(shot: shot),
          ],
        ),
      ],
    );
  }
}

/// 정사각 클립 썸네일 — 시작이미지 + 오버레이(번호·삭제·하단 영상상태/길이). 그리드 셀을 꽉 채운다.
class _ClipThumb extends StatelessWidget {
  const _ClipThumb(
      {required this.shot, required this.clip, required this.index});

  final Shot shot;
  final VideoClip clip;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final selected = clip.id == p.selectedClipId && shot.id == p.selectedShotId;
    final hasVideo = clip.videoPath != null;
    return GestureDetector(
      onTap: () => p.selectClip(shot.id, clip.id),
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
              path: clip.startImagePath,
              version: p.verOf(p.busyKey(clip.id, GenMode.imageStart)),
              busy: p.isBusy(p.busyKey(clip.id, GenMode.imageStart)),
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
                onTap: () => p.removeClip(shot, clip),
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
                    Text('${clip.videoSeconds}s',
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

/// 클립 추가 타일 — 그리드 셀 가운데의 원형 + 버튼.
class _AddClipTile extends StatelessWidget {
  const _AddClipTile({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Center(
      child: InkWell(
        onTap: () => p.addClip(shot),
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
String _fmt(double s) =>
    s == s.roundToDouble() ? '${s.toInt()}s' : '${s.toStringAsFixed(1)}s';

/// 샷 대사 편집 모달: 화자(내레이션 포함) + 텍스트 + 음성 생성 + 대사 삭제.
Future<void> editShotDialogue(BuildContext context, Shot shot) async {
  final p = StoryboardScope.read(context);
  final d = shot.dialogue;
  final textCtrl = TextEditingController(text: d?.text ?? '');
  String? speaker = d?.speakerId;
  bool genning = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Row(
          children: [
            const Text('대사'),
            const Spacer(),
            if (shot.dialogue != null)
              IconButton(
                tooltip: '대사 삭제(무음 샷)',
                onPressed: () {
                  p.removeShotDialogue(shot);
                  Navigator.of(ctx).pop();
                },
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.redAccent,
              ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('화자',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: speaker,
                isExpanded: true,
                decoration: const InputDecoration(
                    isDense: true, border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('내레이션 (화자 없음)')),
                  for (final c in p.characters)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(
                        '${c.name.trim().isEmpty ? '(이름 없음)' : c.name.trim()}'
                        '${c.hasVoice ? '  · 🎙 ${c.voiceName.isEmpty ? '보이스' : c.voiceName}' : '  · 보이스 없음'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => speaker = v),
              ),
              const SizedBox(height: 14),
              const Text('대사',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 6),
              TextField(
                controller: textCtrl,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                style: const TextStyle(fontSize: 14, height: 1.4),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '이 샷에서 말할 대사(또는 내레이션). 비우면 무음 샷',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '감정 표현: 문장 앞에 [crying] [whispers] [sighs] [shouts] 같은 '
                '영어 대괄호 태그 (일레븐랩스 v3)',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // 음성(TTS)
              Builder(builder: (_) {
                final speakerChar = p.characterById(speaker);
                final target = (speakerChar != null && speakerChar.hasVoice)
                    ? '${speakerChar.name.trim().isEmpty ? '화자' : speakerChar.name.trim()} 보이스'
                    : (p.settings.elevenVoiceId.trim().isNotEmpty
                        ? '기본 보이스${p.settings.elevenVoiceName.trim().isEmpty ? '' : '(${p.settings.elevenVoiceName.trim()})'}'
                        : null);
                final canGen = p.voiceReady &&
                    textCtrl.text.trim().isNotEmpty &&
                    target != null;
                final has = shot.dialogue?.hasVoice ?? false;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.graphic_eq, size: 14, color: accent2),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            !p.voiceReady
                                ? '설정에서 일레븐랩스 키를 넣어야 음성을 만들 수 있어요'
                                : target == null
                                    ? '보이스 없음 — 화자에 보이스를 지정하거나 설정에서 기본 보이스를 정하세요'
                                    : has
                                        ? '현재 음성 ${_fmt(shot.dialogue!.voiceSeconds)} · $target 으로 재생성'
                                        : '$target 으로 생성',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white54),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (has && !genning) ...[
                          VoicePlayButton(
                            key: ValueKey(
                                '${shot.dialogue!.voicePath}:${shot.dialogue!.voiceSeconds}'),
                            path: shot.dialogue!.voicePath!,
                            size: 34,
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: (genning || !canGen)
                                ? null
                                : () async {
                                    p.setShotDialogueSpeaker(shot, speaker);
                                    p.setShotDialogueText(
                                        shot, textCtrl.text.trim());
                                    setState(() => genning = true);
                                    await p.genVoice(shot);
                                    if (ctx.mounted) {
                                      setState(() => genning = false);
                                    }
                                  },
                            icon: genning
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Icon(has ? Icons.refresh : Icons.graphic_eq,
                                    size: 18),
                            label: Text(genning
                                ? '생성 중…'
                                : has
                                    ? '음성 재생성'
                                    : '음성 생성'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              p.setShotDialogueSpeaker(shot, speaker);
              p.setShotDialogueText(shot, textCtrl.text.trim());
              Navigator.of(ctx).pop();
            },
            child: const Text('저장'),
          ),
        ],
      ),
    ),
  );
  textCtrl.dispose();
}
