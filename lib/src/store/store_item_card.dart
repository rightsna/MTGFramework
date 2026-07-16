import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_locale.dart';
import 'app_icon/app_icon_screen.dart';
import 'feature_graphic/feature_graphic_screen.dart';
import 'project/models/project.dart';
import 'project/models/store_device.dart';
import 'project/models/store_locale.dart';
import 'project/services/game_deployer.dart';
import 'project/services/project_assets.dart';
import 'project/services/project_store.dart';
import 'project/views/editor_host.dart';
import 'project/views/widgets/language_picker_dialog.dart';
import 'project/views/widgets/project_card.dart';
import 'store_item.dart';
import 'store_shot/views/store_shot_screen.dart';

/// Native macOS bridge (see the host app's MainFlutterWindow.swift) for
/// revealing a folder in Finder. The host app must register this channel name.
const MethodChannel _systemChannel = MethodChannel('launch_kit/system');

/// A single, fully-wired store-publishing card for one [StoreItem]. Give it a
/// [StoreItem] (title + storageDir + fastlaneRoot) and it handles everything:
/// loads the item's authored app icon + screenshots, opens the app-icon /
/// screenshot / feature-graphic editors, manages languages, and deploys the
/// rendered assets into the app's fastlane + native icon folders.
///
/// An [AppLocale] must be provided above this widget (for KO/EN strings).
class StoreItemCard extends StatefulWidget {
  const StoreItemCard({super.key, required this.item});

  final StoreItem item;

  @override
  State<StoreItemCard> createState() => _StoreItemCardState();
}

class _StoreItemCardState extends State<StoreItemCard> {
  final _store = ProjectStore();
  final _assets = ProjectAssets();

  Project? _project;
  File? _appIcon;
  Map<String, File?> _featureGraphicByLocale = const {};
  Map<String, Map<String, List<File>>> _shotsByDeviceLocale = const {};

  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Previews read fixed paths that the editors overwrite in place. Flutter's
    // ImageCache keys FileImage by path (+ resize width), not content, so drop
    // cached decodes here so freshly-saved bytes show instead of a stale one.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    try {
      final p =
          await _store.loadOrInit(widget.item.storageDir, widget.item.title);
      await _store.migrateScreenshotLayout(p);
      await _store.migrateFeatureGraphic(p);
      final byDevice = <String, Map<String, List<File>>>{};
      for (final d in kStoreDevices) {
        byDevice[d.code] = await _assets.screenshotsByLocale(p, d.code);
      }
      final icon = await _assets.appIcon(p);
      final graphics = await _assets.featureGraphicsByLocale(p);
      if (!mounted) return;
      setState(() {
        _project = p;
        _appIcon = icon;
        _featureGraphicByLocale = graphics;
        _shotsByDeviceLocale = byDevice;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[StoreItemCard load] 실패: $e\n$st');
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('로드 실패 / Load failed: $e');
    }
  }

  // ---- navigation into the editors ----

  Future<void> _openAppIcon() async {
    final p = _project;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => AppIconScreen(
          title: tr(ctx, '앱 아이콘', 'App Icon'),
          subtitle: p.name,
          projectIconTarget: p.appIconFile,
        ),
      ));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _shotSubtitle(BuildContext ctx, String device, String locale) {
    final english = AppLocale.of(ctx).english;
    return '${_project!.name} · ${storeDeviceLabel(device, english: english)}'
        ' · ${storeLocaleLabel(locale, english: english)}';
  }

  Future<void> _openFeatureGraphic(String locale) async {
    final p = _project;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => FeatureGraphicScreen(
          title: tr(ctx, '그래픽 이미지', 'Feature Graphic'),
          subtitle:
              '${p.name} · ${storeLocaleLabel(locale, english: AppLocale.of(ctx).english)}',
          projectTarget: p.featureGraphicFileFor(locale),
        ),
      ));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openNewScreenshot(String device, String locale) async {
    final p = _project;
    if (p == null || _busy) return;
    final dev = storeDeviceByCode(device);
    setState(() => _busy = true);
    try {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => EditorHost(
          title: tr(ctx, '새 스샷', 'New Screenshot'),
          subtitle: _shotSubtitle(ctx, device, locale),
          child: StoreShotScreen(
            projectScreenshotsDir: p.screenshotsDirFor(device, locale),
            defaultExportW: dev?.exportW,
            defaultExportH: dev?.exportH,
          ),
        ),
      ));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openScreenshotDoc(
      String device, String locale, File preview) async {
    final p = _project;
    if (p == null || _busy) return;
    final dev = storeDeviceByCode(device);
    setState(() => _busy = true);
    try {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => EditorHost(
          title: tr(ctx, '스샷 편집', 'Edit Screenshot'),
          subtitle: _shotSubtitle(ctx, device, locale),
          child: StoreShotScreen(
            projectScreenshotsDir: p.screenshotsDirFor(device, locale),
            docDir: preview.parent,
            defaultExportW: dev?.exportW,
            defaultExportH: dev?.exportH,
          ),
        ),
      ));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteScreenshot(File preview) async {
    final loc = AppLocale.of(context);
    final ok = await _confirm(
      loc.t('스크린샷 삭제', 'Delete screenshot'),
      loc.t('이 스크린샷을 영구 삭제할까요?', 'Permanently delete this screenshot?'),
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _store.deleteScreenshotDoc(preview.parent);
      await _load();
    } catch (e) {
      _toast('${loc.t('삭제 실패', 'Delete failed')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Add/remove which languages this item authors screenshots for. With the
  /// clone toggle on, each newly-added language is seeded with a copy of the
  /// FIRST (primary) language's screenshots.
  Future<void> _manageLanguages() async {
    final p = _project;
    if (p == null) return;
    final loc = AppLocale.of(context);
    final primary = p.screenshotLocales.first;
    final result = await showDialog<LangPickResult>(
      context: context,
      builder: (ctx) => LanguagePickerDialog(
        initial: p.screenshotLocales,
        primaryLabel: storeLocaleLabel(primary, english: loc.english),
      ),
    );
    if (result == null) return;
    final before = p.screenshotLocales.toSet();
    final newlyAdded =
        result.locales.where((c) => !before.contains(c)).toList();
    setState(() => _busy = true);
    try {
      final updated = await _store.setLocales(p, result.locales);
      if (result.cloneNewFromPrimary) {
        for (final to in newlyAdded) {
          for (final d in kStoreDevices) {
            await _store.cloneScreenshots(updated,
                device: d.code, from: primary, to: to);
          }
        }
        if (newlyAdded.isNotEmpty) {
          _toast(loc.t('복제됨: ${newlyAdded.length}개 언어',
              'Cloned into ${newlyAdded.length} language(s)'));
        }
      }
      await _load();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- deploy to fastlane ----

  Future<void> _deployToFastlane() async {
    final p = _project;
    if (p == null) return;
    final loc = AppLocale.of(context);
    final item = widget.item;
    final deployer = GameDeployer(item);
    final items = await deployer.plan(p);
    if (items.isEmpty) {
      _toast(loc.t('배포할 자산이 없습니다 (아이콘/스샷을 먼저 저장하세요)',
          'Nothing to deploy — save an app icon or screenshot first'));
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item.title} ${tr(ctx, 'fastlane 배포', 'Deploy')}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(ctx, '아래 자산을 게임 저장소에 덮어씁니다:',
                'The following assets overwrite the game repo:')),
            const SizedBox(height: 4),
            Text(item.fastlaneRoot,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 12),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• ${it.label} (${it.count})',
                    style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, '취소', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, '배포', 'Deploy')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final result = await deployer.deploy(p);
      if (mounted) {
        _toast('${loc.t('배포 완료', 'Deployed')} — '
            '${result.written}${loc.t('개 파일', ' files')}');
      }
    } catch (e) {
      _toast('${loc.t('배포 실패', 'Deploy failed')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Open the game repo folder in Finder via the native NSWorkspace channel.
  Future<void> _revealInFinder() async {
    final path = widget.item.fastlaneRoot;
    try {
      final ok = await _systemChannel
          .invokeMethod<bool>('revealInFinder', {'path': path});
      if (ok != true) _toast(path);
    } catch (_) {
      _toast(path);
    }
  }

  // ---- helpers ----

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, '취소', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, '삭제', 'Delete')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    if (_loading || p == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return ProjectCard(
      name: p.name,
      appIcon: _appIcon,
      featureGraphicByLocale: _featureGraphicByLocale,
      locales: p.screenshotLocales,
      shotsByDeviceLocale: _shotsByDeviceLocale,
      enabled: !_busy,
      onOpenIcon: _openAppIcon,
      onOpenGraphic: _openFeatureGraphic,
      onNewScreenshot: _openNewScreenshot,
      onOpenScreenshot: _openScreenshotDoc,
      onDeleteScreenshot: _deleteScreenshot,
      onManageLanguages: _manageLanguages,
      onDeploy: _deployToFastlane,
      onReveal: _revealInFinder,
    );
  }
}
