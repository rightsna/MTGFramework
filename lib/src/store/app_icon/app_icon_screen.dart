import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:framework/framework.dart';
import '../l10n/app_locale.dart';
import 'app_icon_generator.dart';
import 'widgets/app_icon_preview.dart';

const XTypeGroup _imageTypes = XTypeGroup(
  label: 'images',
  extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'tif', 'tiff'],
);

/// 16진수 색상('#RRGGBB' / 'RGB')을 파싱. 실패하면 null.
({int r, int g, int b})? _parseHex(String s) {
  var h = s.trim().replaceAll('#', '');
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return (r: (v >> 16) & 0xff, g: (v >> 8) & 0xff, b: v & 0xff);
}

/// 앱 아이콘 제너레이터: 정사각 소스 이미지 한 장으로 iOS(AppIcon.appiconset +
/// Contents.json) / Android(밀도별 mipmap + Play 512) / macOS(AppIcon.appiconset +
/// Contents.json) 아이콘 세트를 일괄 생성한다.
class AppIconScreen extends StatefulWidget {
  const AppIconScreen({
    super.key,
    this.projectIconTarget,
    this.title,
    this.subtitle,
  });

  /// When set (project context), a "저장" button writes the source as this
  /// project's app icon (the project card preview reads it). Null = standalone
  /// use, where only "내보내기" is shown.
  final File? projectIconTarget;

  /// AppBar title/subtitle. When [title] is null the screen renders no AppBar.
  final String? title;
  final String? subtitle;

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  Uint8List? _srcBytes;
  String? _srcName;
  int _srcW = 0;
  int _srcH = 0;

  bool _ios = true;
  bool _android = true;
  bool _macos = true;
  bool _keepTransparency = true;
  final _bgCtrl = TextEditingController(text: 'FFFFFF');

  bool _busy = false;
  double _progress = 0;
  String _status = '';

  /// Unsaved-changes flag for the project save (the source changed since the
  /// last save/load). Gates the bottom 저장 button.
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _loadExistingIcon();
  }

  /// If this project already has a saved app icon, load it as the source so
  /// re-opening the editor shows it instead of an empty start.
  Future<void> _loadExistingIcon() async {
    final target = widget.projectIconTarget;
    if (target == null || !await target.exists()) return;
    try {
      final bytes = await target.readAsBytes();
      final im = await Future(() => ImageOps.decode(bytes));
      if (!mounted) return;
      setState(() {
        _srcBytes = bytes;
        _srcName = target.path.split(Platform.pathSeparator).last;
        _srcW = im.width;
        _srcH = im.height;
        _dirty = false;
      });
    } catch (_) {
      // Unreadable/corrupt — just start empty.
    }
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  ({int r, int g, int b}) get _bg =>
      _parseHex(_bgCtrl.text) ?? (r: 255, g: 255, b: 255);

  bool get _isSquare => _srcW > 0 && _srcW == _srcH;

  bool get _canExport =>
      _srcBytes != null && (_ios || _android || _macos) && !_busy;

  bool get _canSave =>
      _srcBytes != null && widget.projectIconTarget != null && !_busy;

  // ---- 불러오기 ----

  Future<void> _pickSource() async {
    final loc = AppLocale.of(context);
    final f = await openFile(acceptedTypeGroups: const [_imageTypes]);
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await f.readAsBytes();
      final im = await Future(() => ImageOps.decode(bytes));
      if (!mounted) return;
      setState(() {
        _srcBytes = bytes;
        _srcName = f.name;
        _srcW = im.width;
        _srcH = im.height;
        _busy = false;
        _status = '';
        _dirty = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '${loc.t('이미지를 불러올 수 없습니다', 'Failed to load image')}: $e';
      });
    }
  }

  /// 현재 소스를 이미지 에디터(다이얼로그)로 편집하고, 그 결과를 다시 이 앱
  /// 아이콘의 소스로 반영한다 — 새 파일을 여는 게 아니라 이 아이콘을 편집.
  Future<void> _editSourceInImageEditor() async {
    final loc = AppLocale.of(context);
    final bytes = _srcBytes;
    if (bytes == null) return;
    final edited = await showImageEditDialog(
      context,
      pngBytes: bytes,
      title: loc.t('앱 아이콘 편집', 'Edit app icon'),
    );
    if (edited == null || !mounted) return;
    try {
      final im = await Future(() => ImageOps.decode(edited));
      if (!mounted) return;
      setState(() {
        _srcBytes = edited;
        _srcW = im.width;
        _srcH = im.height;
        _dirty = true;
        _status = loc.t('편집 반영됨 — 저장해야 프로젝트에 적용됩니다',
            'Edit applied — save to apply to the project');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '${loc.t('편집 반영 실패', 'Failed to apply edit')}: $e');
    }
  }

  // ---- 저장 / 내보내기 ----

  /// 프로젝트의 앱 아이콘으로 저장(소스를 PNG로 재인코딩). 프로젝트 카드
  /// 미리보기가 이 파일을 읽는다. 폴더 선택 없음 — 프로젝트 안으로 들어간다.
  Future<void> _saveToProject() async {
    final loc = AppLocale.of(context);
    final bytes = _srcBytes;
    final target = widget.projectIconTarget;
    if (bytes == null || target == null) return;
    setState(() {
      _busy = true;
      _status = loc.t('저장 중…', 'Saving…');
    });
    try {
      final png = await Future(() => ImageOps.encodePng(ImageOps.decode(bytes)));
      await target.writeAsBytes(png);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = loc.t('프로젝트에 저장됨', 'Saved to project');
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '${loc.t('저장 실패', 'Save failed')}: $e';
      });
    }
  }

  /// 아이콘 세트 내보내기: 누를 때 대상 폴더를 고른 뒤 iOS/Android 자산을 생성.
  Future<void> _export() async {
    final loc = AppLocale.of(context);
    final bytes = _srcBytes;
    if (bytes == null) return;
    final outDir = await getDirectoryPath();
    if (outDir == null || !mounted) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = loc.t('생성 중…', 'Generating…');
    });
    try {
      final bg = _bg;
      final result = await AppIconGenerator.generate(
        sourceBytes: bytes,
        outDir: outDir,
        ios: _ios,
        android: _android,
        macos: _macos,
        keepTransparency: _keepTransparency,
        bgR: bg.r,
        bgG: bg.g,
        bgB: bg.b,
        onProgress: (p, _) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '${loc.t('완료', 'Done')}: '
            '${loc.t('${result.written}개 생성', '${result.written} created')}'
            '${result.failed.isEmpty ? '' : ' · ${loc.t('실패 ${result.failed.length}개', '${result.failed.length} failed')}'}'
            ' → ${result.outDir}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '${loc.t('생성 실패', 'Generate failed')}: $e';
      });
    }
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.title == null ? null : _buildAppBar(),
      body: Column(
        children: [
          if (_busy && _progress > 0) LinearProgressIndicator(value: _progress),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 360, child: _buildSettings()),
                const VerticalDivider(width: 1),
                Expanded(
                  child: AppIconPreview(
                    srcBytes: _srcBytes,
                    bgColor: _keepTransparency
                        ? null
                        : Color.fromARGB(255, _bg.r, _bg.g, _bg.b),
                  ),
                ),
              ],
            ),
          ),
          if (widget.projectIconTarget != null) _buildSaveBar(),
        ],
      ),
    );
  }

  /// 하단 전체 너비 저장 바. 변경사항이 있을 때(_dirty)만 활성화된다.
  Widget _buildSaveBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: (_canSave && _dirty) ? _saveToProject : null,
          icon: const Icon(Icons.save_outlined),
          label: Text(tr(context, '저장', 'Save')),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final hasSrc = _srcBytes != null;
    return AppBar(
      titleSpacing: 0,
      title: widget.subtitle == null
          ? Text(widget.title!)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.title!, style: const TextStyle(fontSize: 16)),
                Text(widget.subtitle!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
      actions: [
        IconButton(
          tooltip: tr(context, '이미지 에디터', 'Image Editor'),
          icon: const Icon(Icons.image_outlined),
          onPressed: (!hasSrc || _busy) ? null : _editSourceInImageEditor,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSettings() {
    final bg = _bg;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _title(tr(context, '소스 이미지', 'Source image')),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickSource,
          icon: const Icon(Icons.file_upload_outlined, size: 18),
          label: Text(tr(context, '이미지 선택', 'Choose image')),
        ),
        if (_srcName != null) ...[
          const SizedBox(height: 8),
          Text(_srcName!,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis),
          Text(
            '$_srcW×$_srcH',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (!_isSquare)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr(
                  context,
                  '⚠ 정사각 이미지가 아닙니다 — 비율을 유지해 가운데에 맞춰 넣고\n'
                      '남는 영역은 배경색/투명으로 채웁니다. 1024×1024 권장.',
                  '⚠ Not a square image — it will be centered with its aspect '
                      'ratio kept, and the remaining area filled with the '
                      'background color/transparency. 1024×1024 recommended.',
                ),
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),
        ],
        const Divider(height: 28),
        _title(tr(context, '플랫폼', 'Platform')),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _ios,
          onChanged: _busy ? null : (v) => setState(() => _ios = v ?? false),
          title: const Text('iOS (AppIcon.appiconset + Contents.json)'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _android,
          onChanged:
              _busy ? null : (v) => setState(() => _android = v ?? false),
          title: const Text('Android (mipmap-* + Play 512)'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _macos,
          onChanged: _busy ? null : (v) => setState(() => _macos = v ?? false),
          title: const Text('macOS (AppIcon.appiconset + Contents.json)'),
        ),
        const Divider(height: 28),
        _title(tr(context, '배경', 'Background')),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _keepTransparency,
          onChanged: _busy
              ? null
              : (v) => setState(() => _keepTransparency = v ?? false),
          title: Text(tr(context, '투명 배경 유지', 'Keep transparency')),
          subtitle: Text(
            tr(
              context,
              'iOS 마케팅(1024) 아이콘은 App Store 규정상 항상 배경색으로 채웁니다.',
              'The iOS marketing (1024) icon is always filled with the '
                  'background color, per App Store rules.',
            ),
            style: const TextStyle(fontSize: 11),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color.fromARGB(255, bg.r, bg.g, bg.b),
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _bgCtrl,
                enabled: !_busy,
                decoration: _dec(label: tr(context, '배경색 (HEX)', 'Background color (HEX)')),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const Divider(height: 28),
        FilledButton.icon(
          onPressed: _canExport ? _export : null,
          icon: const Icon(Icons.ios_share),
          label: Text(tr(context, '내보내기', 'Export')),
        ),
        if (widget.projectIconTarget != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr(
                context,
                '저장(하단) = 이 프로젝트의 앱 아이콘으로 보관 · 내보내기 = 폴더를 '
                    '골라 iOS/Android/macOS 아이콘 세트 생성',
                'Save (bottom) = keep as this project\'s app icon · Export = '
                    'choose a folder to generate the iOS/Android/macOS icon set',
              ),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _status,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      );

  InputDecoration _dec({String? label}) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      );
}
