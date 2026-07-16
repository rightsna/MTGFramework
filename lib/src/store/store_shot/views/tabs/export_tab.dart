import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_locale.dart';
import '../../controllers/store_shot_controller.dart';
import '../widgets/panel_controls.dart';
import 'source_actions.dart';

/// 우측 패널 "내보내기" 탭: 출력 형식(PNG/JPG + 품질) + 내보내기 버튼 + 상태.
/// 출력 크기는 "배경" 탭 프레임이 결정하므로 안내만 보여준다. 합성 바이트는
/// [StoreShotController]가 만들고, 저장 위치 선택·파일 쓰기는 이 탭이 한다.
class ExportTab extends StatelessWidget {
  const ExportTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StoreShotController>();
    final busy = c.busy;

    Future<void> export() async {
      if (c.frameW <= 0 || c.frameH <= 0) {
        c.emitToast('프레임 크기를 올바르게 입력하세요', 'Enter a valid frame size');
        return;
      }
      final ext = c.exportJpg ? 'jpg' : 'png';
      final location = await getSaveLocation(
        acceptedTypeGroups: [
          XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
        ],
        suggestedName:
            'result_${baseName(c.shotName ?? c.bgName ?? 'store')}.$ext',
      );
      if (location == null) return;
      final bytes = await c.buildExportBytes();
      if (bytes == null) return;
      try {
        var path = location.path;
        if (!path.toLowerCase().endsWith('.$ext')) path = '$path.$ext';
        await File(path).writeAsBytes(bytes);
        c.emitToast('저장됨: $path', 'Saved: $path');
      } catch (e) {
        c.emitToast('내보내기 실패: $e', 'Export failed: $e');
      }
    }

    final status = c.status;
    return ListView(
      padding: const EdgeInsets.all(12),
      shrinkWrap: true,
      children: [
        SectionTitle(tr(context, '출력 크기', 'Output size')),
        Text('${c.frameW} × ${c.frameH} px',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            tr(context, '크기는 "배경" 탭의 프레임에서 바꿉니다.',
                'Change the size in the frame on the "Background" tab.'),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        const Divider(height: 28),
        SectionTitle(tr(context, '출력 형식', 'Output format')),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('PNG')),
            ButtonSegment(value: true, label: Text('JPG')),
          ],
          selected: {c.exportJpg},
          onSelectionChanged: busy ? null : (s) => c.setExportJpg(s.first),
        ),
        if (c.exportJpg) ...[
          const SizedBox(height: 12),
          Text('${tr(context, 'JPG 품질', 'JPG quality')}: ${c.jpgQuality}'),
          Slider(
            value: c.jpgQuality.toDouble(),
            min: 1,
            max: 100,
            divisions: 99,
            label: '${c.jpgQuality}',
            onChanged: busy ? null : (v) => c.setJpgQuality(v.round()),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (!c.ready || busy) ? null : export,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_alt),
          label: Text(busy
              ? tr(context, '내보내는 중…', 'Exporting…')
              : c.exportJpg
                  ? tr(context, 'JPG 내보내기', 'Export JPG')
                  : tr(context, 'PNG 내보내기', 'Export PNG')),
        ),
        if (status.ko.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              tr(context, status.ko, status.en),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
