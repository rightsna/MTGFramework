import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_locale.dart';
import '../../controllers/store_shot_controller.dart';
import '../../models/store_shot_doc.dart';
import '../widgets/panel_controls.dart';
import 'source_actions.dart';

/// 우측 패널 "배경" 탭: 출력 프레임 크기 + 배경 채움 방식 + 배경 소스
/// 불러오기/편집. 상태와 합성은 [StoreShotController]가 소유하고, 이 탭은
/// 파일 선택·이미지 에디터(=BuildContext 단계)만 처리해 결과를 컨트롤러로 넘긴다.
class BackgroundTab extends StatelessWidget {
  const BackgroundTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StoreShotController>();
    final busy = c.busy;

    Future<void> pick() async {
      final picked = await pickImageFile();
      if (picked != null) {
        await c.setBackground(picked.bytes, name: picked.name);
      }
    }

    Future<void> edit() async {
      final bytes = c.bgBytes;
      if (bytes == null) return;
      final edited =
          await editImage(context, bytes, tr(context, '배경 편집', 'Edit background'));
      if (edited != null) {
        await c.replaceBackground(edited,
            note: (ko: '배경 편집 반영됨', en: 'Background edit applied'));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionTitle(tr(context, '프레임 크기 (출력)', 'Frame size (output)')),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final preset in kExportPresets)
              ChoiceChip(
                label: Text(preset.label, style: const TextStyle(fontSize: 11)),
                selected: c.frameW == preset.w && c.frameH == preset.h,
                onSelected:
                    busy ? null : (_) => c.applyFramePreset(preset.w, preset.h),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: c.frameWCtrl,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr(context, '너비(px)', 'Width (px)'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => c.onFrameFieldsChanged(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('×'),
            ),
            Expanded(
              child: TextField(
                controller: c.frameHCtrl,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr(context, '높이(px)', 'Height (px)'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => c.onFrameFieldsChanged(),
              ),
            ),
          ],
        ),
        const Divider(height: 28),
        SectionTitle(tr(context, '배경 이미지', 'Background image')),
        SourceTile(
          label: tr(context, '배경', 'Background'),
          name: c.bgName,
          hint:
              tr(context, '프레임을 채울 배경 이미지', 'Background image to fill the frame'),
          onPick: busy ? null : pick,
          onEdit: busy ? null : edit,
        ),
        const SizedBox(height: 14),
        Text(tr(context, '채움 방식', 'Fit'), style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        SegmentedButton<BgFit>(
          segments: [
            ButtonSegment(
                value: BgFit.cover, label: Text(tr(context, '채움(크롭)', 'Cover'))),
            ButtonSegment(
                value: BgFit.fill, label: Text(tr(context, '늘이기', 'Fill'))),
          ],
          selected: {c.bgFit},
          onSelectionChanged: busy ? null : (s) => c.setBgFit(s.first),
        ),
        const SizedBox(height: 8),
        Text(
          c.bgFit == BgFit.cover
              ? tr(context, '비율을 유지하며 프레임을 가득 채우고 넘치는 부분은 잘립니다.',
                  'Keeps aspect ratio, fills the frame, and crops the overflow.')
              : tr(context, '비율을 무시하고 프레임 크기에 정확히 늘여 채웁니다.',
                  'Stretches to exactly fill the frame, ignoring aspect ratio.'),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
