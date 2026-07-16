import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_locale.dart';
import '../controllers/store_shot_controller.dart';
import 'preview_view.dart';
import 'tabs/background_tab.dart';
import 'tabs/export_tab.dart';
import 'tabs/objects_tab.dart';
import 'tabs/screenshot_tab.dart';

/// Store Screenshot composer. 외부 배경 1장 + 실제 앱 스크린샷(+옵션 캐릭터)을
/// 불러와, 스크린샷을 하단에서 살짝 걸치는 모바일 프레임처럼 합성한 뒤 스토어용
/// PNG/JPG로 내보낸다.
///
/// 이 위젯은 얇은 셸이다: 모든 상태·로직은 [StoreShotController]가 소유하고
/// (provider로 하위에 공급), 좌측 [PreviewView]와 우측 탭들이 그것을 구독·호출한다.
class StoreShotScreen extends StatefulWidget {
  const StoreShotScreen({
    super.key,
    this.projectScreenshotsDir,
    this.docDir,
    this.defaultExportW,
    this.defaultExportH,
  });

  /// When set (project context), "저장" writes a screenshot *document* (source
  /// images + layout + composed preview) into a subfolder of this dir, so the
  /// card thumbnails fill and the shot can be reopened for editing. Null =
  /// standalone use, where only "내보내기" is shown.
  final Directory? projectScreenshotsDir;

  /// An existing screenshot document folder to load and edit on open. Null = a
  /// new screenshot.
  final Directory? docDir;

  /// Default frame (output) size for this device class (e.g. 1242×2688 for
  /// iPhone). Null falls back to the iPhone preset.
  final int? defaultExportW;
  final int? defaultExportH;

  @override
  State<StoreShotScreen> createState() => _StoreShotScreenState();
}

class _StoreShotScreenState extends State<StoreShotScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late final StoreShotController _c;
  int _lastToastSeq = 0;

  @override
  void initState() {
    super.initState();
    _c = StoreShotController(
      frameW: widget.defaultExportW ?? 1242,
      frameH: widget.defaultExportH ?? 2688,
    )..addListener(_onControllerChanged);
    _tab = TabController(length: 4, vsync: this)
      ..addListener(() {
        // 탭 인덱스가 바뀌면 즉시 리빌드(미리보기 핸들 표시는 스크린샷 탭에서만).
        if (mounted) setState(() {});
      });
    if (widget.docDir != null) _c.loadDir(widget.docDir!);
  }

  /// 컨트롤러의 토스트 신호를 스낵바로 띄운다(상태 텍스트는 각 위젯이 직접 표시).
  void _onControllerChanged() {
    if (!mounted || _c.toastSeq == _lastToastSeq) return;
    _lastToastSeq = _c.toastSeq;
    final msg = tr(context, _c.toast.ko, _c.toast.en);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _tab.dispose();
    _c.removeListener(_onControllerChanged);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _c,
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildPreview()),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 340, child: _buildSidePanel()),
                ],
              ),
            ),
            if (widget.projectScreenshotsDir != null) _buildSaveBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() => PreviewView(
        isScreenshotTab: _tab.index == 1,
        isObjectsTab: _tab.index == 2,
      );

  Widget _buildSidePanel() {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          tabs: [
            Tab(text: tr(context, '배경', 'Background')),
            Tab(text: tr(context, '스크린샷', 'Screenshot')),
            Tab(text: tr(context, '오브젝트', 'Objects')),
            Tab(text: tr(context, '내보내기', 'Export')),
          ],
        ),
        _tabGuide(),
        Expanded(
          // IndexedStack (not TabBarView) — tapping a tab switches instantly
          // with no slide animation, and each tab keeps its scroll position.
          child: IndexedStack(
            index: _tab.index,
            children: const [
              BackgroundTab(),
              ScreenshotTab(),
              ObjectsTab(),
              ExportTab(),
            ],
          ),
        ),
      ],
    );
  }

  /// 탭 바로 아래 안내 배너 — 현재 탭이 무엇을 하는 곳인지 한 줄로 설명한다.
  Widget _tabGuide() {
    final (ko, en) = switch (_tab.index) {
      0 => (
          '출력 프레임 크기를 정하고, 프레임을 채울 배경 이미지를 불러오거나 AI로 생성합니다.',
          'Set the output frame size and load (or AI-generate) the background that fills it.'
        ),
      1 => (
          '실제 앱 화면 캡처를 폰 프레임으로 얹습니다. 미리보기에서 드래그·모서리로 위치/크기를 조절하세요.',
          'Place your app screenshot as a phone frame. Drag it (and its corners) in the preview.'
        ),
      2 => (
          '캐릭터·로고 같은 투명 PNG를 여러 개 얹습니다. 선택해 미리보기에서 옮기고 크기를 조절하세요.',
          'Add multiple transparent PNGs (characters, logos). Select one to move/resize it in the preview.'
        ),
      _ => (
          '완성된 이미지를 PNG/JPG로 내보냅니다. 크기는 배경 탭의 프레임이 정합니다.',
          'Export the finished image as PNG/JPG. The size comes from the Background tab frame.'
        ),
    };
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr(context, ko, en),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 전체 너비 저장 바. 변경사항이 있을 때(dirty)만 활성화된다.
  Widget _buildSaveBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        child: Consumer<StoreShotController>(
          builder: (context, c, _) => FilledButton.icon(
            onPressed: (c.ready && c.dirty && !c.busy)
                ? () => c.saveToProject(widget.projectScreenshotsDir!)
                : null,
            icon: c.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(c.busy
                ? tr(context, '저장 중…', 'Saving…')
                : tr(context, '저장', 'Save')),
          ),
        ),
      ),
    );
  }
}
