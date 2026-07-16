import 'dart:convert';
import 'dart:io';

import '../models/project.dart';
import '../models/store_device.dart';
import '../models/store_locale.dart';
import 'project_assets.dart';

/// Loads / initializes ONE store item's editable working folder and manages its
/// screenshot documents (locales, layout migrations, clone, delete). Everything
/// is keyed by an absolute [storageDir] — there is no global project list or
/// current-project pointer; each [StoreItemCard] owns its own working folder.
class ProjectStore {
  static const _enc = JsonEncoder.withIndent('  ');

  /// Load the project rooted at [storageDir], titled [title]. Creates the folder
  /// (with screenshots/ + project.json) on first access so authoring works
  /// immediately. Existing project.json supplies the authored locales.
  Future<Project> loadOrInit(String storageDir, String title) async {
    final dir = Directory(storageDir);
    final meta = File('${dir.path}/project.json');
    if (await meta.exists()) {
      final read = (await _read(dir))!;
      return Project(
        name: title,
        dir: dir,
        createdAt: read.createdAt,
        screenshotLocales: read.screenshotLocales,
      );
    }
    await dir.create(recursive: true);
    final p = Project(name: title, dir: dir, createdAt: DateTime(2024));
    await p.screenshotsDir.create();
    await _writeMeta(p);
    return p;
  }

  // ---- internals ----

  Future<Project?> _read(Directory dir) async {
    final meta = File('${dir.path}/project.json');
    if (!await meta.exists()) return null;
    try {
      final map =
          (jsonDecode(await meta.readAsString()) as Map).cast<String, dynamic>();
      final id = dir.path.split(Platform.pathSeparator).last;
      return Project(
        name: map['name'] as String? ?? id,
        dir: dir,
        createdAt:
            DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime(2020),
        screenshotLocales:
            (map['screenshotLocales'] as List?)?.whereType<String>().toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMeta(Project p) => p.metaFile.writeAsString(_enc.convert({
        'name': p.name,
        'createdAt': p.createdAt.toIso8601String(),
        'screenshotLocales': p.screenshotLocales,
      }));

  /// Persist a changed set of screenshot languages for [p] (non-destructive —
  /// removing a locale only hides its folder; the files stay on disk). At least
  /// one locale is kept. Returns the updated project.
  Future<Project> setLocales(Project p, List<String> locales) async {
    final cleaned = locales.where((e) => e.trim().isNotEmpty).toList();
    final updated = p.copyWith(
        screenshotLocales:
            cleaned.isEmpty ? kDefaultScreenshotLocales : cleaned);
    await _writeMeta(updated);
    return updated;
  }

  /// Bring an older screenshot layout up to the current
  /// `screenshots/<device>/<locale>/<doc>/` shape. Handles both pre-multilingual
  /// docs sitting directly under `screenshots/` and the device-less
  /// `screenshots/<locale>/` layout, folding everything into the default device
  /// ([kDefaultDevice]). Device folders that already exist are left alone, so
  /// this is idempotent and safe to run on every load.
  Future<void> migrateScreenshotLayout(Project p) async {
    final root = p.screenshotsDir;
    if (!await root.exists()) return;
    final defaultLocale =
        p.screenshotLocales.isNotEmpty ? p.screenshotLocales.first : 'ko';

    final looseDocs = <Directory>[]; // pre-multilingual docs at root
    final localeDirs = <Directory>[]; // device-less `screenshots/<locale>/`
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final base = e.path.split(Platform.pathSeparator).last;
      if (kKnownDeviceCodes.contains(base)) continue; // already device-layered
      final isDoc = ProjectAssets.docPreview(e) != null ||
          await File('${e.path}/doc.json').exists();
      (isDoc ? looseDocs : localeDirs).add(e);
    }
    if (looseDocs.isEmpty && localeDirs.isEmpty) return;

    final deviceDir = Directory('${root.path}/$kDefaultDevice');
    await deviceDir.create(recursive: true);

    // Loose docs → <device>/<defaultLocale>/.
    if (looseDocs.isNotEmpty) {
      final target = Directory('${deviceDir.path}/$defaultLocale');
      await target.create(recursive: true);
      for (final d in looseDocs) {
        await _moveDirInto(target, d);
      }
    }
    // `<locale>/` folders → `<device>/<locale>/` (merging if the target exists).
    for (final d in localeDirs) {
      final base = d.path.split(Platform.pathSeparator).last;
      final dest = Directory('${deviceDir.path}/$base');
      if (await dest.exists()) {
        await for (final doc in d.list()) {
          if (doc is Directory) await _moveDirInto(dest, doc);
        }
        await d.delete(recursive: true);
      } else {
        await d.rename(dest.path);
      }
    }
  }

  /// Move a legacy single `feature_graphic.png` into the per-language layout
  /// (`feature_graphic/<primaryLocale>.png`). Idempotent; no-op once migrated.
  Future<void> migrateFeatureGraphic(Project p) async {
    final legacy = p.legacyFeatureGraphicFile;
    if (!await legacy.exists()) return;
    final primary =
        p.screenshotLocales.isNotEmpty ? p.screenshotLocales.first : 'ko';
    final dest = p.featureGraphicFileFor(primary);
    if (await dest.exists()) return; // already have one — leave the legacy file
    await dest.parent.create(recursive: true);
    await legacy.rename(dest.path);
  }

  /// Move [src] into [targetParent], keeping its folder name (suffixing on a
  /// name clash). [targetParent] is created if missing.
  Future<void> _moveDirInto(Directory targetParent, Directory src) async {
    await targetParent.create(recursive: true);
    final base = src.path.split(Platform.pathSeparator).last;
    var dest = '${targetParent.path}/$base';
    for (var i = 2; await Directory(dest).exists(); i++) {
      dest = '${targetParent.path}/${base}_$i';
    }
    await src.rename(dest);
  }

  /// Copy every screenshot document from locale [from] into locale [to] within
  /// [device], as a starting point for a newly-added language. Only populates an
  /// EMPTY target (if [to] already has any document it's left untouched), so this
  /// never clobbers existing work. No-op when [from] has nothing or equals [to].
  Future<void> cloneScreenshots(Project p,
      {required String device,
      required String from,
      required String to}) async {
    if (from == to) return;
    final src = p.screenshotsDirFor(device, from);
    if (!await src.exists()) return;
    final dst = p.screenshotsDirFor(device, to);

    // Skip if the target already holds a document (preview/doc.json).
    if (await dst.exists()) {
      await for (final e in dst.list()) {
        if (e is! Directory) continue;
        if (ProjectAssets.docPreview(e) != null ||
            await File('${e.path}/doc.json').exists()) {
          return;
        }
      }
    } else {
      await dst.create(recursive: true);
    }

    await for (final e in src.list()) {
      if (e is! Directory) continue;
      final base = e.path.split(Platform.pathSeparator).last;
      await _copyDir(e, Directory('${dst.path}/$base'));
    }
  }

  Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list()) {
      final base = e.path.split(Platform.pathSeparator).last;
      if (e is File) {
        await e.copy('${dst.path}/$base');
      } else if (e is Directory) {
        await _copyDir(e, Directory('${dst.path}/$base'));
      }
    }
  }

  /// Permanently delete a single screenshot document (its whole folder —
  /// sources + layout + preview). [docDir] is a screenshot document directory (a
  /// preview file's parent). Ignores a missing folder.
  Future<void> deleteScreenshotDoc(Directory docDir) async {
    if (await docDir.exists()) await docDir.delete(recursive: true);
  }
}
