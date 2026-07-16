import 'dart:io';

import 'package:framework/framework.dart';

import '../../app_icon/app_icon_generator.dart';
import '../../store_item.dart';
import '../models/project.dart';
import '../models/store_device.dart';
import 'project_assets.dart';

/// A single planned write into a game's repo — surfaced to the user before any
/// destructive deploy so they can see exactly what will be overwritten.
class DeployItem {
  DeployItem(this.label, this.count);
  final String label; // human-readable target, e.g. "iOS 아이콘"
  final int count; // number of files
}

/// Result of a deploy run.
class DeployResult {
  DeployResult(this.written, this.details);
  final int written;
  final List<String> details;
}

/// Pushes a project's AUTHORED assets (edited in the app-owned working folder)
/// straight into its game's real repo — fastlane screenshot folders + native
/// app-icon locations — so nothing has to be zipped or copied by hand.
///
/// This writes into the checked-out game source, so callers must confirm first.
class GameDeployer {
  GameDeployer(this.game);
  final StoreItem game;
  final _assets = ProjectAssets();

  /// Preview the writes for [p] without touching disk (icon count + per-device /
  /// per-locale screenshot counts). Empty list ⇒ nothing to deploy.
  Future<List<DeployItem>> plan(Project p) async {
    final items = <DeployItem>[];
    if (await _assets.appIcon(p) != null) {
      items.add(DeployItem('앱 아이콘 (iOS·Android·macOS)', 1));
    }
    for (final locale in p.screenshotLocales) {
      for (final d in kStoreDevices) {
        final shots = await _assets.screenshots(p, d.code, locale);
        if (shots.isEmpty) continue;
        items.add(DeployItem(
            '스샷 · ${d.code} · $locale', shots.length));
      }
    }
    return items;
  }

  /// Execute the deploy for [p]. Overwrites the game's app-icon set and the
  /// per-locale fastlane screenshot folders from the authored assets.
  Future<DeployResult> deploy(Project p) async {
    if (!game.existsSync()) {
      throw StateError('게임 폴더를 찾을 수 없습니다: ${game.fastlaneRoot}');
    }
    final details = <String>[];
    var written = 0;

    written += await _deployIcon(p, details);
    written += await _deployScreenshots(p, details);

    return DeployResult(written, details);
  }

  // ---- app icon ----

  Future<int> _deployIcon(Project p, List<String> details) async {
    final icon = await _assets.appIcon(p);
    if (icon == null) return 0;
    final srcBytes = await icon.readAsBytes();

    // Reuse the generator to render a full tree into a temp build dir, then copy
    // each file to its real Flutter location. Keeping transparency preserves the
    // authored look; the generator still forces the iOS marketing slot opaque.
    final build = Directory('${p.dir.path}/_iconbuild');
    if (await build.exists()) await build.delete(recursive: true);
    await build.create(recursive: true);
    await AppIconGenerator.generate(
      sourceBytes: srcBytes,
      outDir: build.path,
      ios: true,
      android: true,
      macos: true,
      keepTransparency: true,
    );

    var n = 0;
    // iOS + macOS appiconset trees copy 1:1 (including Contents.json).
    n += await _copyTree(Directory('${build.path}/ios/AppIcon.appiconset'),
        game.iosAppIconSet);
    // Only if the game actually has a macOS target (its xcassets dir exists) —
    // otherwise skip so we never create a stray iconset.
    if (await game.macosAppIconSet.parent.exists()) {
      n += await _copyTree(Directory('${build.path}/macos/AppIcon.appiconset'),
          game.macosAppIconSet);
    }
    // Android legacy launcher icons: build/android/mipmap-* → res/mipmap-*.
    final androidBuild = Directory('${build.path}/android');
    if (await androidBuild.exists()) {
      await for (final e in androidBuild.list()) {
        if (e is! Directory) continue;
        final base = e.path.split(Platform.pathSeparator).last;
        if (!base.startsWith('mipmap-')) continue;
        n += await _copyTree(e, Directory('${game.androidResDir.path}/$base'));
      }
    }
    // Google Play store icon (512) → every authored locale's images/icon.png.
    final play = File('${build.path}/android/playstore-icon.png');
    if (await play.exists()) {
      final bytes = await play.readAsBytes();
      for (final locale in p.screenshotLocales) {
        final dir = game.androidImagesDir(androidLocaleFor(locale));
        await dir.create(recursive: true);
        await File('${dir.path}/icon.png').writeAsBytes(bytes);
        n++;
      }
    }

    await build.delete(recursive: true);
    details.add('앱 아이콘: $n개 파일');
    return n;
  }

  // ---- screenshots ----

  Future<int> _deployScreenshots(Project p, List<String> details) async {
    var total = 0;
    for (final locale in p.screenshotLocales) {
      final iosLocale = locale;
      final androidLocale = androidLocaleFor(locale);

      // Gather previews per device, resized to the device's required store size.
      final mobile = await _sizedShots(p, 'mobile', locale);
      final ipad = await _sizedShots(p, 'ipad', locale);

      // iOS: mobile + ipad both go into one per-locale folder (deliver splits by
      // resolution). Clear this locale's folder, then rewrite.
      if (mobile.isNotEmpty || ipad.isNotEmpty) {
        final dir = game.iosScreenshotsDir(iosLocale);
        await _resetDir(dir);
        var i = 1;
        for (final b in mobile) {
          await File('${dir.path}/mobile_${_pad(i++)}.png').writeAsBytes(b);
          total++;
        }
        i = 1;
        for (final b in ipad) {
          await File('${dir.path}/ipad_${_pad(i++)}.png').writeAsBytes(b);
          total++;
        }
        details.add('iOS 스샷 · $iosLocale: ${mobile.length + ipad.length}개');
      }

      // Android phone screenshots ← mobile.
      if (mobile.isNotEmpty) {
        final dir = Directory(
            '${game.androidImagesDir(androidLocale).path}/phoneScreenshots');
        await _resetDir(dir);
        var i = 1;
        for (final b in mobile) {
          await File('${dir.path}/s${i++}.png').writeAsBytes(b);
          total++;
        }
        details.add('Android 폰 스샷 · $androidLocale: ${mobile.length}개');
      }

      // Android tablet screenshots ← ipad (same set into 7" and 10" slots).
      if (ipad.isNotEmpty) {
        for (final slot in const ['sevenInchScreenshots', 'tenInchScreenshots']) {
          final dir = Directory(
              '${game.androidImagesDir(androidLocale).path}/$slot');
          await _resetDir(dir);
          var i = 1;
          for (final b in ipad) {
            await File('${dir.path}/pad${i++}.png').writeAsBytes(b);
            total++;
          }
        }
        details.add('Android 태블릿 스샷 · $androidLocale: ${ipad.length}개 ×2슬롯');
      }
    }
    return total;
  }

  /// Read each preview.png for ([device], [locale]) and re-encode it at the
  /// device's exact App Store dimensions (stores reject off-size images).
  Future<List<List<int>>> _sizedShots(
      Project p, String device, String locale) async {
    final dev = storeDeviceByCode(device);
    final previews = await _assets.screenshots(p, device, locale);
    final out = <List<int>>[];
    for (final f in previews) {
      var bytes = await f.readAsBytes();
      if (dev != null) {
        bytes = await Future(() => ImageOps.encodePng(
            ImageOps.resize(ImageOps.decode(bytes), dev.exportW, dev.exportH)));
      }
      out.add(bytes);
    }
    return out;
  }

  // ---- fs helpers ----

  /// Empty [dir] (creating it) so a redeploy never leaves stale, gap-numbered
  /// files behind. Only PNGs are removed — other files are left untouched.
  Future<void> _resetDir(Directory dir) async {
    await dir.create(recursive: true);
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.png')) {
        await e.delete();
      }
    }
  }

  Future<int> _copyTree(Directory src, Directory dst) async {
    if (!await src.exists()) return 0;
    await dst.create(recursive: true);
    var n = 0;
    await for (final e in src.list()) {
      final base = e.path.split(Platform.pathSeparator).last;
      if (e is File) {
        await e.copy('${dst.path}/$base');
        n++;
      } else if (e is Directory) {
        n += await _copyTree(e, Directory('${dst.path}/$base'));
      }
    }
    return n;
  }

  static String _pad(int i) => i.toString().padLeft(2, '0');
}
