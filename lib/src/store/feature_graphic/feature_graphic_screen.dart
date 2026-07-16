import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:framework/framework.dart';
import '../l10n/app_locale.dart';


const XTypeGroup _imageTypes = XTypeGroup(
  label: 'images',
  extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'tif', 'tiff'],
);

/// Google Play feature graphic size — exactly 1024×500.
const int _fgW = 1024;
const int _fgH = 500;

/// Feature graphic editor: manage a project's single 1024×500 banner the same
/// way as the app icon — load a source, optionally edit it / generate with AI,
/// then save it into the project (always normalized to exactly 1024×500 by
/// scaling to fill and centre-cropping). Mirrors [AppIconScreen]'s structure.
class FeatureGraphicScreen extends StatefulWidget {
  const FeatureGraphicScreen({
    super.key,
    this.projectTarget,
    this.title,
    this.subtitle,
  });

  /// When set (project context), a "저장" button writes the normalized 1024×500
  /// PNG to this file (the project card preview reads it).
  final File? projectTarget;

  final String? title;
  final String? subtitle;

  @override
  State<FeatureGraphicScreen> createState() => _FeatureGraphicScreenState();
}

class _FeatureGraphicScreenState extends State<FeatureGraphicScreen> {
  Uint8List? _srcBytes;
  String? _srcName;
  int _srcW = 0;
  int _srcH = 0;

  bool _busy = false;
  String _status = '';
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final target = widget.projectTarget;
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
      // corrupt — start empty
    }
  }

  bool get _isExactSize => _srcW == _fgW && _srcH == _fgH;
  bool get _canSave =>
      _srcBytes != null && widget.projectTarget != null && !_busy;

  /// Normalize [bytes] to exactly 1024×500 by resizing to the target size
  /// (adjusts the aspect ratio — no cropping). Returns PNG bytes.
  Future<Uint8List> _normalize(Uint8List bytes) {
    return Future(() => ImageOps.encodePng(
        ImageOps.resize(ImageOps.decode(bytes), _fgW, _fgH)));
  }

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

  Future<void> _editInImageEditor() async {
    final loc = AppLocale.of(context);
    final bytes = _srcBytes;
    if (bytes == null) return;
    final edited = await showImageEditDialog(
      context,
      pngBytes: bytes,
      title: loc.t('그래픽 이미지 편집', 'Edit feature graphic'),
    );
    if (edited == null || !mounted) return;
    await _applyResult(edited,
        loc.t('편집 반영됨 — 저장해야 적용됩니다', 'Edit applied — save to apply'));
  }

  Future<void> _applyResult(Uint8List bytes, String okStatus) async {
    try {
      final im = await Future(() => ImageOps.decode(bytes));
      if (!mounted) return;
      setState(() {
        _srcBytes = bytes;
        _srcW = im.width;
        _srcH = im.height;
        _dirty = true;
        _status = okStatus;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '${AppLocale.of(context).t('반영 실패', 'Failed')}: $e');
    }
  }

  Future<void> _saveToProject() async {
    final loc = AppLocale.of(context);
    final bytes = _srcBytes;
    final target = widget.projectTarget;
    if (bytes == null || target == null) return;
    setState(() {
      _busy = true;
      _status = loc.t('저장 중…', 'Saving…');
    });
    try {
      // The per-language target lives in feature_graphic/<locale>.png — create
      // the folder on first save (writeAsBytes won't make missing parents).
      if (!await target.parent.exists()) {
        await target.parent.create(recursive: true);
      }
      await target.writeAsBytes(await _normalize(bytes));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = loc.t('프로젝트에 저장됨 (1024×500)', 'Saved to project (1024×500)');
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

  Future<void> _export() async {
    final loc = AppLocale.of(context);
    final bytes = _srcBytes;
    if (bytes == null) return;
    final location = await getSaveLocation(
      suggestedName: 'feature_graphic.png',
      acceptedTypeGroups: const [XTypeGroup(label: 'PNG', extensions: ['png'])],
    );
    if (location == null) return;
    setState(() => _busy = true);
    try {
      final png = await _normalize(bytes);
      var path = location.path;
      if (!path.toLowerCase().endsWith('.png')) path = '$path.png';
      await File(path).writeAsBytes(png);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '${loc.t('내보냄', 'Exported')} (1024×500): $path';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '${loc.t('내보내기 실패', 'Export failed')}: $e';
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
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 360, child: _buildSettings()),
                const VerticalDivider(width: 1),
                Expanded(child: _buildPreview()),
              ],
            ),
          ),
          if (widget.projectTarget != null) _buildSaveBar(),
        ],
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
          onPressed: (!hasSrc || _busy) ? null : _editInImageEditor,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

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

  Widget _buildSettings() {
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
          Text('$_srcW×$_srcH',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (!_isExactSize)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr(
                  context,
                  '저장 시 1024×500으로 크기가 조정됩니다 (잘라내지 않고 비율을 맞춤).',
                  'On save it is resized to 1024×500 (ratio adjusted, not cropped).',
                ),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
        ],
        const Divider(height: 28),
        Text(
          tr(context, 'Google Play 그래픽 이미지: PNG/JPEG, 1024×500, 최대 15MB.',
              'Google Play feature graphic: PNG/JPEG, 1024×500, max 15MB.'),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const Divider(height: 28),
        FilledButton.icon(
          onPressed: (_srcBytes == null || _busy) ? null : _export,
          icon: const Icon(Icons.ios_share),
          label: Text(tr(context, '내보내기 (PNG)', 'Export (PNG)')),
        ),
        if (widget.projectTarget != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr(context, '저장(하단) = 이 프로젝트의 그래픽 이미지로 보관.',
                  'Save (bottom) = keep as this project\'s feature graphic.'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_status,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget _buildPreview() {
    if (_srcBytes == null) {
      return ColoredBox(
        color: const Color(0xFF1A1A1D),
        child: Center(
          child: Text(
              tr(context, '소스 이미지를 선택하세요 (1024×500 권장)',
                  'Choose a source image (1024×500 recommended)'),
              style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    // Show how it lands in the 1024×500 frame (resized to fit = BoxFit.fill).
    return ColoredBox(
      color: const Color(0xFF1A1A1D),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: _fgW / _fgH,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(_srcBytes!, fit: BoxFit.fill),
                ),
              ),
              const SizedBox(height: 8),
              const Text('1024 × 500',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      );
}
