import 'package:flutter/material.dart';

import '../../providers/storyboard_provider.dart';
import '../common/audio_box.dart';
import '../ui.dart';

/// 배경음 섹션 (씬 단위 BGM) — 우측 '씬' 탭에 세로로 들어간다.
/// 오디오 파일을 불러오는 게 기본이고, 스타일 태그로 ACE-Step BGM(/bgm) 생성도 된다.
///
/// 좁은 패널 폭을 전제로 **위→아래 스택**(컨트롤 → 플레이어)이며 높이는 내용에 맞춘다.
/// (예전 캔버스 하단 바 시절의 고정 높이 200 + 좌우 분할은 폭이 좁아 넘쳤다.)
class BgmSection extends StatelessWidget {
  const BgmSection({super.key});

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    if (sc == null) return const SizedBox.shrink();
    final status = p.apiStatus;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, size: 16, color: accent2),
              const SizedBox(width: 6),
              const Text('배경음 · 씬 BGM',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: accent2)),
            ],
          ),
          if (status.reachable && !status.audioReady) ...[
            const SizedBox(height: 4),
            const Text('배경음 워크플로 미설치(bgm)',
                style: TextStyle(fontSize: 11, color: Colors.orangeAccent)),
          ],
          const SizedBox(height: 10),
          // 지금 설정된 배경음이 먼저 — 결과가 위, 그걸 바꾸는 수단(불러오기/생성)이 아래.
          AudioBox(
            path: sc.bgmPath,
            emptyText: '배경음 없음 — 불러오거나 생성하세요',
            busy: p.isBusy(p.bgmBusyKey(sc.id)),
            version: p.verOf(p.bgmBusyKey(sc.id)),
          ),
          const SizedBox(height: 14),
          _BgmControls(key: ValueKey(sc.id)),
        ],
      ),
    );
  }
}

/// 불러오기 버튼 + (부가) 스타일 프롬프트·길이·생성 버튼. 씬이 바뀌면 key로 재생성돼 값 갱신.
class _BgmControls extends StatefulWidget {
  const _BgmControls({super.key});

  @override
  State<_BgmControls> createState() => _BgmControlsState();
}

class _BgmControlsState extends State<_BgmControls> {
  late final TextEditingController _prompt = TextEditingController(
      text: StoryboardScope.read(context).selectedScene?.bgmPrompt ?? '');
  late double _seconds =
      (StoryboardScope.read(context).selectedScene?.bgmSeconds ?? 30)
          .toDouble()
          .clamp(10, 120);

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    final key = sc == null ? '' : p.bgmBusyKey(sc.id);
    final busy = p.isBusy(key);
    final ready = p.bgmReady; // 서버 연결 + bgm 워크플로 있어야 생성 가능
    Widget genBtn = FilledButton.icon(
      onPressed: (busy || !ready)
          ? null
          : () {
              p.setSceneBgmPrompt(_prompt.text);
              p.genBgm();
            },
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.graphic_eq, size: 18),
      label: Text(busy ? '생성 중…' : '배경음 생성'),
    );
    if (!ready && p.bgmBlockReason != null) {
      genBtn = Tooltip(message: p.bgmBlockReason!, child: genBtn);
    }
    // 기본 동선 = 파일 불러오기. 그 아래에 부가로 AI 생성.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : p.loadBgm,
          icon: const Icon(Icons.audio_file_outlined, size: 18),
          label: const Text('오디오 파일 불러오기'),
        ),
        const SizedBox(height: 4),
        const Text(
          'mp3 · wav · m4a · aac · flac · ogg — 프로젝트 폴더로 복사됩니다',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 12),
        // ── 부가: AI로 생성 ──
        Row(
          children: [
            const Icon(Icons.graphic_eq, size: 14, color: accent2),
            const SizedBox(width: 6),
            const Text('AI로 생성 (선택)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _prompt,
          minLines: 2,
          maxLines: 4,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontSize: 13, height: 1.35),
          onTapOutside: (_) {
            p.setSceneBgmPrompt(_prompt.text);
            FocusManager.instance.primaryFocus?.unfocus();
          },
          decoration: const InputDecoration(
            isDense: true,
            filled: true,
            fillColor: previewBg,
            border: OutlineInputBorder(),
            hintText: '스타일 태그 (인스트루멘탈) — 예: cinematic, ambient, calm, piano',
          ),
        ),
        const SizedBox(height: 8),
        // 길이 슬라이더(전체폭 — 슬라이더가 Expanded라 어떤 폭에도 맞춤).
        Row(
          children: [
            const Text('길이', style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: _seconds,
                min: 10,
                max: 120,
                divisions: 11,
                label: '${_seconds.round()}초',
                onChanged: (v) => setState(() => _seconds = v),
                onChangeEnd: (v) => p.setSceneBgmSeconds(v.round()),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text('${_seconds.round()}초',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        genBtn,
      ],
    );
  }
}
