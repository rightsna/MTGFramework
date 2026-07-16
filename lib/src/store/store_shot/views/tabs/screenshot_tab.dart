import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_locale.dart';
import '../../controllers/store_shot_controller.dart';
import '../../models/store_shot_doc.dart';
import '../widgets/panel_controls.dart';
import 'source_actions.dart';

/// 우측 패널 "스크린샷" 탭: 스크린샷 소스 + 정렬/모서리/베젤 레이아웃. 레이아웃
/// 값은 [StoreShotController]에서 읽고, 변경 시 컨트롤러로 반영한다(소스 I/O는 이
/// 탭이, 합성·상태는 컨트롤러가 담당).
class ScreenshotTab extends StatelessWidget {
  const ScreenshotTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StoreShotController>();
    final busy = c.busy;
    final ready = c.ready;
    final hasShot = c.shotPreview != null;
    final doc = c.currentDoc;

    Future<void> pick() async {
      final picked = await pickImageFile();
      if (picked != null) {
        await c.setScreenshot(picked.bytes, name: picked.name);
      }
    }

    Future<void> edit() async {
      final bytes = c.shotBytes;
      if (bytes == null) return;
      final edited = await editImage(
          context, bytes, tr(context, '스크린샷 편집', 'Edit screenshot'));
      if (edited != null) {
        await c.replaceScreenshot(edited,
            note: (ko: '스크린샷 편집 반영됨', en: 'Screenshot edit applied'));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionTitle(tr(context, '스크린샷 (옵션)', 'Screenshot (optional)')),
        SourceTile(
          label: tr(context, '스크린샷', 'Screenshot'),
          name: c.shotName,
          hint: tr(context, '실제 앱 스크린샷 — 없으면 배경만 내보냅니다',
              'Real app screenshot — without it only the background exports'),
          onPick: busy ? null : pick,
          onEdit: busy ? null : edit,
          onClear: busy ? null : c.clearScreenshot,
        ),
        const Divider(height: 28),
        SectionTitle(tr(context, '레이아웃', 'Layout')),
        Text(
          tr(
              context,
              '미리보기에서 스크린샷을 드래그해 옮기고, 모서리를 끌어 크기를 조절하세요.',
              'Drag the screenshot in the preview to move it, and drag a corner '
                  'to resize.'),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        AlignRow(
          label: tr(context, '수평', 'Horizontal'),
          icons: const [
            Icons.align_horizontal_left,
            Icons.align_horizontal_center,
            Icons.align_horizontal_right,
          ],
          onTap: hasShot ? c.alignH : null,
        ),
        const SizedBox(height: 6),
        AlignRow(
          label: tr(context, '수직', 'Vertical'),
          icons: const [
            Icons.align_vertical_top,
            Icons.align_vertical_center,
            Icons.align_vertical_bottom,
          ],
          onTap: hasShot ? c.alignV : null,
        ),
        const Divider(height: 28),
        LabeledSlider(
          label: tr(context, '모서리', 'Corner'),
          valueText: '${(doc.topRadiusFraction * 100).round()}%',
          value: doc.topRadiusFraction,
          min: 0.0,
          max: 0.20,
          enabled: ready,
          onChanged: (v) => c.applyDoc(doc.copyWith(topRadiusFraction: v)),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(tr(context, '테두리', 'Bezel')),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  BezelSwatch(
                    color: null,
                    selected: doc.noBezel,
                    onTap: () => c.applyDoc(doc.copyWith(noBezel: true)),
                  ),
                  for (var i = 0; i < kBezelPresets.length; i++)
                    BezelSwatch(
                      color: Color.fromARGB(255, kBezelPresets[i].r,
                          kBezelPresets[i].g, kBezelPresets[i].b),
                      selected: !doc.noBezel && doc.bezelIndex == i,
                      onTap: () =>
                          c.applyDoc(doc.copyWith(noBezel: false, bezelIndex: i)),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (!doc.noBezel)
          LabeledSlider(
            label: tr(context, '두께', 'Thickness'),
            valueText: '${(doc.bezelFraction * 100).toStringAsFixed(1)}%',
            value: doc.bezelFraction,
            min: 0.0,
            max: 0.06,
            enabled: ready,
            onChanged: (v) => c.applyDoc(doc.copyWith(bezelFraction: v)),
          ),
      ],
    );
  }
}
