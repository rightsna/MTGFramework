part of 'inspector_panel.dart';

/// 인스펙터 탭들이 함께 쓰는 조각들 — 빈 상태 안내·메모 상자·카드/라벨·입력·생성 버튼·결과 블록.

/// 인스펙터 칩(해상도·인물참조) 라벨 — 좁은 패널에서 여러 개가 줄바꿈되므로 작게.
const _chipLabel = TextStyle(fontSize: 11);

/// 장면·영상 탭에 편집할 샷이 없을 때의 안내.
///  - 샷 미선택 → 샷을 먼저 선택
///  - 대사는 있으나 샷 0개 → 샷 추가(＋)
///  - 샷은 있으나 선택 안 됨 → 캔버스에서 샷을 클릭하도록 안내
class _NoShot extends StatelessWidget {
  const _NoShot();

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final beat = p.selectedDialogue;
    if (beat == null) {
      return const _CenterNote(
        icon: Icons.touch_app_outlined,
        title: '비트를 선택하세요',
      );
    }
    if (beat.shots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_filter_outlined,
              color: Colors.white24,
              size: 40,
            ),
            const SizedBox(height: 10),
            const Text(
              '이 비트에 샷이 없습니다',
              style: TextStyle(color: Colors.white38),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => p.addShot(beat),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('비트 추가'),
            ),
          ],
        ),
      );
    }
    return const _CenterNote(
      icon: Icons.ads_click,
      title: '샷을 선택하세요',
      subtitle: '캔버스에서 편집할 샷을 클릭하면\n그 샷의 장면·영상을 편집할 수 있어요',
    );
  }
}

/// 가운데 안내(아이콘 + 제목 + 선택 부제) — 인스펙터 빈 상태 공용.
class _CenterNote extends StatelessWidget {
  const _CenterNote({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 40),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: Colors.white38)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white24),
            ),
          ],
        ],
      ),
    );
  }
}

/// 파생 트랙에서 이 샷이 **기준 트랙을 따라가는 중**인지 알려주는 띠 + 분리/되돌리기 버튼.
/// 기준 트랙이거나 트랙이 하나뿐이면 아무것도 그리지 않는다.
class _TrackLinkBar extends StatelessWidget {
  const _TrackLinkBar({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    if (!shot.isDerived) return const SizedBox.shrink();
    final base = p.tracks.isEmpty ? null : p.tracks.first;
    final baseName = base == null ? '트랙 1' : p.trackLabel(base);
    final linked = shot.inherits;
    final color = linked ? accent : const Color(0xFFE0A94A);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(linked ? Icons.link : Icons.edit_outlined,
                size: 15, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                linked
                    ? '$baseName의 내용을 그대로 씁니다 — 영상만 이 트랙 것입니다'
                    : '이 트랙에서 수정한 샷입니다 — $baseName과 따로 갑니다',
                style: const TextStyle(fontSize: 11.5, height: 1.35),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () =>
                  linked ? p.detachShot(shot) : _confirmRelink(context, p),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: color,
              ),
              child: Text(linked ? '이 트랙에서 수정' : '$baseName로 되돌리기',
                  style: const TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRelink(
      BuildContext context, StoryboardProvider p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('트랙 1로 되돌리기'),
        content: const Text('이 샷의 내용을 트랙 1의 것으로 되돌립니다.\n'
            '이 트랙에서 고친 프롬프트·프레임은 더 이상 쓰이지 않습니다.\n'
            '(이 트랙에서 뽑은 영상은 그대로 남습니다)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('되돌리기')),
        ],
      ),
    );
    if (ok == true) await p.relinkShot(shot);
  }
}

/// 따라가는(상속) 샷의 편집 영역을 통째로 잠근다 — 칸마다 readOnly를 물리는 대신 한 겹으로.
/// 잠긴 동안에도 **보이기는 그대로**여야 한다(트랙 1과 같은 내용을 쓰고 있다는 게 요점).
class _LockIfInherited extends StatelessWidget {
  const _LockIfInherited({required this.locked, required this.child});

  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) => locked
      ? IgnorePointer(child: Opacity(opacity: 0.55, child: child))
      : child;
}

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

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.icon,
    required this.title,
    required this.child,
    this.done,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final bool? done;

  @override
  Widget build(BuildContext context) {
    final lit = done ?? false;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: lit ? const Color(0x335BD1C0) : const Color(0x1AFFFFFF),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent2),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (done != null) _DoneBadge(done: done!),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0x14FFFFFF)),
          ),
          child,
        ],
      ),
    );
  }
}

class _DoneBadge extends StatelessWidget {
  const _DoneBadge({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: done ? accent2 : Colors.white24,
        ),
        const SizedBox(width: 4),
        Text(
          done ? '생성됨' : '미생성',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: done ? accent2 : Colors.white38,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: accent2,
      ),
    );
  }
}

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
        isDense: true,
        filled: true,
        fillColor: previewBg,
        border: const OutlineInputBorder(),
      ),
      onChanged: readOnly ? null : (_) => p.save(),
    );
  }
}

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

/// 작은 2단 토글 알약 — 프롬프트 원본/번역 전환용.
class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.left,
    required this.right,
    required this.rightSelected,
    required this.onChanged,
  });

  final String left;
  final String right;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String t, bool selected, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: selected ? accent2 : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(t,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.black : const Color(0x88FFFFFF))),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(left, !rightSelected, () => onChanged(false)),
        seg(right, rightSelected, () => onChanged(true)),
      ]),
    );
  }
}

class _GenButton extends StatelessWidget {
  const _GenButton({
    required this.label,
    required this.icon,
    required this.busyKey,
    required this.onGen,
    this.enabled = true,
    this.disabledHint,
  });

  final String label;
  final IconData icon;
  final String busyKey;
  final VoidCallback onGen;
  final bool enabled;
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    final busy = StoryboardScope.of(context).isBusy(busyKey);
    final btn = FilledButton.icon(
      onPressed: (busy || !enabled) ? null : onGen,
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(busy ? '생성 중…' : label),
    );
    if (!enabled && disabledHint != null) {
      return Tooltip(message: disabledHint!, child: btn);
    }
    return btn;
  }
}

class _OutputBlock extends StatelessWidget {
  const _OutputBlock({
    required this.title,
    required this.path,
    required this.busyKey,
    this.isVideo = false,
    this.deleteTarget,
    this.trimTarget,
  });

  final String title;
  final String? path;
  final String busyKey;
  final bool isVideo;

  /// 지정하면 '삭제' 버튼이 붙는다 — 이 샷의 해당 생성물(프레임/영상)만 지운다.
  final ({Shot shot, GenMode mode})? deleteTarget;

  /// 지정하면 '트림' 버튼이 붙는다(영상 전용) — 프레임 단위로 보며 앞뒤를 잘라낸다.
  final Shot? trimTarget;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 제목 오른쪽에 다루기 버튼(열기·폴더·트림·삭제)을 아이콘만 붙인다 — 미리보기 아래에
        // 따로 줄을 두면 패널만 길어진다. 생성물이 있을 때만 보인다.
        Row(
          children: [
            _SectionLabel(title),
            const Spacer(),
            if (path != null) ...[
              _MediaAction(
                icon: Icons.open_in_new,
                label: '열기',
                onTap: () => p.openFile(path!),
              ),
              _MediaAction(
                icon: Icons.folder_open_outlined,
                label: '폴더에서 보기',
                onTap: () => p.revealInFinder(path!),
              ),
              if (trimTarget != null)
                _MediaAction(
                  icon: Icons.content_cut,
                  label: '트림',
                  onTap: () async {
                    final seconds =
                        await showVideoTrimDialog(context, path: path!);
                    if (seconds != null) {
                      await p.applyTrim(trimTarget!, seconds);
                    }
                  },
                ),
              if (deleteTarget != null)
                _MediaAction(
                  icon: Icons.delete_outline,
                  label: '삭제',
                  color: Colors.redAccent,
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('$title 삭제'),
                        content: Text(
                          '이 샷의 $title을(를) 지웁니다.\n'
                          '파일도 함께 삭제되며 되돌릴 수 없습니다.\n\n'
                          '${path!.split('/').last}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('취소'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.redAccent),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('삭제'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await p.removeMedia(
                          deleteTarget!.shot, deleteTarget!.mode);
                    }
                  },
                ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: previewBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: path != null
                  ? const Color(0x335BD1C0)
                  : const Color(0x14FFFFFF),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: OutputPreview(
            path: path,
            version: p.verOf(busyKey),
            busy: p.isBusy(busyKey),
            isVideo: isVideo,
            fit: BoxFit.contain,
            onOpen: path == null ? null : () => p.openFile(path!),
            // 이미지(시작·끝장면)는 클릭하면 확대 팝업 — 영상은 탭이 재생이라 제외.
            onImageTap: (isVideo || path == null)
                ? null
                : () => showImageZoomDialog(
                      context,
                      path: path!,
                      version: p.verOf(busyKey),
                      title: title,
                    ),
            // 영상은 그 자리서 재생하지 말고 팝업으로 크게 — 씬의 영상들을 이어서 재생하며
            // 대사 음성·씬 배경음도 함께 튼다.
            onVideoTap: (isVideo && path != null)
                ? () => showVideoPlayDialog(context,
                    playlist: p.scenePlaylist(),
                    startPath: path!,
                    bgmPath: p.scenePlayBgmPath)
                : null,
          ),
        ),
      ],
    );
  }
}

/// 제목 옆 액션 아이콘 하나(열기·폴더·트림·삭제) — 라벨은 툴팁으로만.
class _MediaAction extends StatelessWidget {
  const _MediaAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label; // 툴팁
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: label,
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        color: color ?? Colors.white70,
        icon: Icon(icon),
      );
}
