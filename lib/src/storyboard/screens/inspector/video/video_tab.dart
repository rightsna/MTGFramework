part of '../inspector_panel.dart';

/// 영상 탭 관련 위젯 — 샷의 영상 생성과 그 설정(길이).

/// 영상 탭(샷): 설정(해상도) + 영상.
class _VideoTab extends StatelessWidget {
  const _VideoTab({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final c = shot;
    // 파생 샷도 영상은 늘 자기 것이고, 프롬프트·길이는 고치면 그것만 이 트랙 것으로 오버라이드된다.
    final isStill = p.shotVideoMode(c) == VideoMode.still;
    final vBusyKey = p.busyKey(c.id, GenMode.videoLow);
    // busy(생성 중) 여부는 프로바이더가 중앙 관리한다 — 자체 서버 job이 오프라인이면 리컨실러가
    // busy를 내려서 여기 포함 모든 곳의 스피너가 사라진다. 그래서 여기선 그냥 isBusy만 본다.
    final showVideoBusy = p.isBusy(vBusyKey);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 영상 메모 — 장면 탭 메모와 별개다(영상에 적을 말은 프레임에 적을 말과 다르다).
          _ShotNote(controller: p.videoNoteCtrl(c.id)),
          const SizedBox(height: 16),
          // 결과(영상)가 위, 그걸 만드는 수단(프롬프트·생성) 다음, 설정은 맨 아래.
          _GroupCard(
            icon: Icons.movie_outlined,
            title: '영상',
            done: c.videoPath != null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 영상이 있으면(자기 것이든 상속이든) 영상을, 아무 데도 없으면 **생성에 쓸 프레임**을
                // 대신 보여준다. 트림·삭제는 **자기 트랙에서 뽑은 영상**에만(상속 중인 건 기준 것).
                if (p.videoPathOf(c) != null)
                  _OutputBlock(
                    title: '영상',
                    path: p.videoPathOf(c),
                    busyKey: p.busyKey(c.id, GenMode.videoLow),
                    isVideo: true,
                    deleteTarget: p.hasOwnVideo(c)
                        ? (shot: c, mode: GenMode.videoLow)
                        : null,
                    trimTarget: p.hasOwnVideo(c) ? c : null,
                    // 파생 트랙(트랙2…)에서 뽑은 영상만 트랙1로 복사할 수 있다.
                    copyToBaseTarget:
                        (c.isDerived && p.hasOwnVideo(c)) ? c : null,
                  )
                else
                  _VideoInputFrames(shot: c),
                if (!p.hasOwnVideo(c) && p.videoPathOf(c) != null) ...[
                  const SizedBox(height: 6),
                  Text('${p.trackLabel(p.tracks.first)}의 영상입니다 — 여기서 뽑으면 이 트랙 것이 됩니다',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0x88FFFFFF))),
                ],
                const SizedBox(height: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 스틸컷은 AI 프롬프트를 안 쓴다 — 사진 한 장을 그대로 채우므로.
                    if (!isStill) ...[
                      _PromptPair(
                        label: '프롬프트',
                        controller: p.videoCtrl(c.id),
                        koController: p.videoKoCtrl(c.id),
                        hint: '움직임/카메라 등 영상 묘사',
                      ),
                      const SizedBox(height: 10),
                      _SectionLabel('네거티브 프롬프트'),
                      const SizedBox(height: 6),
                      _PromptField(
                        controller: p.videoNegCtrl(c.id),
                        hint: '빼고 싶은 것만 (예: hand, text, watermark) — '
                            '위 프롬프트에 "no hand"처럼 쓰면 오히려 나온다',
                      ),
                      const SizedBox(height: 14),
                    ],
                    // 스틸컷은 0.1초 단위, AI 방식은 1초 단위 — 값은 하나(videoSeconds).
                    _SectionLabel(
                        isStill ? '길이 (초 · 0.1 단위)' : '길이 (초 · 이 샷)'),
                    const SizedBox(height: 6),
                    _SecondsField(
                        key: ValueKey('sec_${c.id}_$isStill'), still: isStill),
                  ],
                ),
                const SizedBox(height: 10),
                // 생성 중이면 버튼을 숨기고 '생성중 + 인디케이터'만 — 중복 생성 여지를 없앤다.
                // (서버 연결 끊긴 자체 서버 job이면 showVideoBusy=false → 스피너 대신 아래 버튼)
                if (showVideoBusy)
                  Row(
                    children: [
                      Expanded(
                        child: _GenProgressBanner(
                          text: p.progressOf(vBusyKey) ?? '생성 중…',
                        ),
                      ),
                      // 자체 서버 비동기 생성(job_id 있음)만 취소 가능 — Veo/스틸컷엔 없다.
                      if (c.videoJobId != null) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => p.cancelVideo(c),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('취소'),
                        ),
                      ],
                    ],
                  )
                else if (isStill)
                  // 스틸컷은 AI가 아니라 로컬 ffmpeg — 백엔드 선택 없이 버튼 하나.
                  // 문구에 '영상'을 붙인다 — 이 버튼도 결국 영상을 굽는다는 게 안 보여서
                  // 안 눌러도 되는 줄 알고 넘어가는 일이 있었다.
                  _GenButton(
                    label: '스틸컷 영상 생성',
                    icon: Icons.photo_outlined,
                    busyKey: p.busyKey(c.id, GenMode.videoLow),
                    onGen: () => p.gen(c, GenMode.videoLow),
                    enabled: p.stillReady,
                    disabledHint: p.stillBlockReason,
                  )
                else
                  // 백엔드는 **누를 때 고른다** — 자체 서버 · Veo 버튼을 한 줄에 나란히.
                  Row(
                    children: [
                      for (final b in VideoBackend.values) ...[
                        if (b != VideoBackend.values.first)
                          const SizedBox(width: 8),
                        Expanded(
                          child: _GenButton(
                            label: '${b.label}로 생성',
                            icon: b == VideoBackend.veo
                                ? Icons.auto_awesome_outlined
                                : Icons.movie_outlined,
                            busyKey: p.busyKey(c.id, GenMode.videoLow),
                            onGen: () => p.gen(c, GenMode.videoLow, backend: b),
                            enabled: p.videoReadyOf(b),
                            disabledHint: p.videoBlockReasonOf(b),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          // 해상도는 씬 단위라 씬 탭의 '생성 설정'으로 옮겼다.
        ],
      ),
    );
  }
}
