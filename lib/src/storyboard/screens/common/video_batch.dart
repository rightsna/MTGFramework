import 'package:flutter/material.dart';

import '../../providers/storyboard_provider.dart';
import '../ui.dart';

/// 영상 일괄 생성 몸통 — 씬 탭의 칸(선택 씬의 모든 샷 영상을 한 번에).
///
/// 생성은 GPU 시간(=돈)이 드는 일이라, 누르기 전에 **무엇이 돌고 무엇이 빠지는지**를
/// 먼저 보여준다: 재료(시작·끝 프레임·프롬프트)가 모자란 샷은 경고로 드러내고,
/// 실제로 몇 개를 만들지는 버튼에 적어둔 뒤 확인까지 받는다.
///
/// 진행 상태는 [StoryboardProvider]가 들고 있어서(한 번에 하나만 돈다) 탭을 벗어나도
/// 생성은 계속되고, 다시 오면 진행 중인 게 그대로 보인다.
class VideoBatch extends StatefulWidget {
  const VideoBatch({super.key});

  @override
  State<VideoBatch> createState() => _VideoBatchState();
}

class _VideoBatchState extends State<VideoBatch> {
  /// 기본은 건너뛰기 — 이미 만들어 둔 영상(=이미 쓴 GPU 시간)을 실수로 날리지 않는 쪽이 안전하다.
  bool _skipExisting = true;

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final plan = p.sceneVideoPlan(skipExisting: _skipExisting);
    final backend = p.settings.videoBackend;
    final blockReason = p.videoBlockReasonOf(backend);
    final running = p.batchRunning;
    final n = plan.ready.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '이 씬의 모든 샷 영상을 한 번에 만듭니다 (${backend.label}).',
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
        const SizedBox(height: 10),
        _BatchCounts(plan: plan),
        const SizedBox(height: 6),
        // 기본 ON(건너뛰기)이라 껐을 때 뭐가 달라지는지를 부제에 적는다.
        SwitchListTile(
          value: _skipExisting,
          onChanged: running ? null : (v) => setState(() => _skipExisting = v),
          title: const Text(
            '이미 생성된 영상 건너뛰기',
            style: TextStyle(fontSize: 12.5),
          ),
          subtitle: Text(
            _skipExisting
                ? '영상이 있는 샷은 그대로 둡니다'
                : '영상이 있는 샷도 덮어서 새로 만듭니다',
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
          dense: true,
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (plan.blocked.isNotEmpty) ...[
          const SizedBox(height: 4),
          _BatchWarning(blocked: plan.blocked),
        ],
        const SizedBox(height: 12),
        if (running) ...[
          LinearProgressIndicator(
            value: p.batchTotal == 0 ? null : p.batchDone / p.batchTotal,
            minHeight: 6,
            backgroundColor: previewBg,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${p.batchDone} / ${p.batchTotal} 생성됨',
                style: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: p.cancelBatch,
                style:
                    TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text('중지'),
              ),
            ],
          ),
          const Text(
            '지금 만드는 샷까지 끝내고 멈춥니다.',
            style: TextStyle(fontSize: 11, color: Colors.white30),
          ),
        ] else
          FilledButton.icon(
            onPressed:
                (blockReason != null || n == 0) ? null : () => _start(p, plan),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text(n == 0 ? '생성할 샷 없음' : '영상 $n개 생성'),
          ),
        if (blockReason != null) ...[
          const SizedBox(height: 6),
          Text(
            blockReason,
            style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
          ),
        ],
      ],
    );
  }

  /// 돈이 드는 작업이라 시작 전에 한 번 더 확인받는다 — 특히 덮어쓰기는 되돌릴 수 없다.
  Future<void> _start(StoryboardProvider p, SceneVideoPlan plan) async {
    final n = plan.ready.length;
    final overwrite = _skipExisting
        ? 0
        : plan.ready.where((s) => s.videoPath != null).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('영상 $n개 생성'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이 씬에서 샷 $n개의 영상을 순서대로 만듭니다. 몇 분씩 걸릴 수 있습니다.'),
            if (overwrite > 0) ...[
              const SizedBox(height: 10),
              Text(
                '이 중 $overwrite개는 이미 영상이 있습니다 — 덮어쓰며 되돌릴 수 없습니다.\n'
                '남기려면 "이미 생성된 영상 건너뛰기"를 켜세요.',
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ],
            if (plan.blocked.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '준비가 안 된 샷 ${plan.blocked.length}개는 건너뜁니다.',
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('생성'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await p.genSceneVideos(skipExisting: _skipExisting);
  }
}

/// 계획 요약 — 생성 / 건너뜀 / 준비 안 됨 개수.
class _BatchCounts extends StatelessWidget {
  const _BatchCounts({required this.plan});
  final SceneVideoPlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: previewBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _Count('생성', plan.ready.length, accent2),
          if (plan.skipped.isNotEmpty)
            _Count('건너뜀', plan.skipped.length, Colors.white38),
          if (plan.blocked.isNotEmpty)
            _Count('준비 안 됨', plan.blocked.length, Colors.orangeAccent),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.n, this.color);
  final String label;
  final int n;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$n',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      );
}

/// 재료가 빠져 못 도는 샷들을 이유까지 찍어준다 — 뭘 채워야 할지 바로 알 수 있게.
/// 여러 씬을 한 번에 볼 때는 목록이 길어질 수 있어 스크롤로 가둔다.
class _BatchWarning extends StatelessWidget {
  const _BatchWarning({required this.blocked});
  final List<BlockedShot> blocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 15, color: Colors.orangeAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '샷 ${blocked.length}개는 재료가 빠져 건너뜁니다',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.orangeAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final b in blocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• ${b.label} — ${b.missing.join(', ')} 없음',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white60),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
