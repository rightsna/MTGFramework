import 'dart:io';

import '../models/project.dart';

/// Reads a project's asset files for previews: the single app icon and the set
/// of store screenshots. Screenshots are document folders under screenshots/
/// (each with sources + layout + a composed preview.png); this returns the
/// preview files, whose parent directory is the editable document.
class ProjectAssets {
  /// The project's app icon image, or null if none has been set yet.
  Future<File?> appIcon(Project p) async {
    final f = p.appIconFile;
    return await f.exists() ? f : null;
  }

  /// The project's feature graphic (1024×500) for [locale], or null if none.
  Future<File?> featureGraphic(Project p, String locale) async {
    final f = p.featureGraphicFileFor(locale);
    return await f.exists() ? f : null;
  }

  /// Feature graphic file (or null) keyed by every locale the project authors.
  Future<Map<String, File?>> featureGraphicsByLocale(Project p) async {
    final out = <String, File?>{};
    for (final locale in p.screenshotLocales) {
      out[locale] = await featureGraphic(p, locale);
    }
    return out;
  }

  /// One preview per screenshot document for ([device], [locale]), name-sorted
  /// (empty if none). Prefers `preview.jpg`, falling back to a legacy
  /// `preview.png`. The document folder to (re)open is each file's parent.
  Future<List<File>> screenshots(
      Project p, String device, String locale) async {
    final dir = p.screenshotsDirFor(device, locale);
    if (!await dir.exists()) return [];
    final previews = <File>[];
    await for (final e in dir.list()) {
      if (e is Directory) {
        final preview = docPreview(e);
        if (preview != null) previews.add(preview);
      }
    }
    previews.sort((a, b) =>
        a.parent.path.toLowerCase().compareTo(b.parent.path.toLowerCase()));
    return previews;
  }

  /// The composed preview file inside a screenshot document folder [docDir], or
  /// null if none. Prefers `preview.jpg` over a legacy `preview.png`.
  static File? docPreview(Directory docDir) {
    final jpg = File('${docDir.path}/preview.jpg');
    if (jpg.existsSync()) return jpg;
    final png = File('${docDir.path}/preview.png');
    if (png.existsSync()) return png;
    return null;
  }

  /// Previews for [device], keyed by locale.
  Future<Map<String, List<File>>> screenshotsByLocale(
      Project p, String device) async {
    final out = <String, List<File>>{};
    for (final locale in p.screenshotLocales) {
      out[locale] = await screenshots(p, device, locale);
    }
    return out;
  }
}
