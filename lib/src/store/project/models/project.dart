import 'dart:io';

import 'store_locale.dart';

/// The editable working folder for one StoreItem: its assets are a single app
/// icon (app_icon.png) and store screenshots grouped by device then language
/// (`screenshots/<device>/<locale>/<doc>/`), plus a small project.json holding
/// the authored locales. [dir] is the item's storageDir; [name] is its title.
class Project {
  Project({
    required this.name,
    required this.dir,
    required this.createdAt,
    List<String>? screenshotLocales,
  }) : screenshotLocales =
            (screenshotLocales == null || screenshotLocales.isEmpty)
                ? kDefaultScreenshotLocales
                : screenshotLocales;

  final String name;
  final Directory dir;
  final DateTime createdAt;

  /// App Store localizations this project authors screenshots for; each is a
  /// folder name under [screenshotsDir]. Never empty (defaults applied).
  final List<String> screenshotLocales;

  /// Stable on-disk id (the folder name).
  String get id => dir.path.split(Platform.pathSeparator).last;

  /// The project's single app icon image (may not exist yet).
  File get appIconFile => File('${dir.path}/app_icon.png');

  /// Legacy single feature graphic path (pre per-language). Kept only so it can
  /// be migrated into [featureGraphicFileFor].
  File get legacyFeatureGraphicFile => File('${dir.path}/feature_graphic.png');

  /// Folder holding the per-language feature graphics.
  Directory get featureGraphicDir => Directory('${dir.path}/feature_graphic');

  /// The Google Play feature graphic (1024×500) for [locale]; may not exist yet.
  File featureGraphicFileFor(String locale) =>
      File('${featureGraphicDir.path}/$locale.png');

  /// Root folder holding the per-device, per-language screenshot folders:
  /// `screenshots/<device>/<locale>/<doc>/`.
  Directory get screenshotsDir => Directory('${dir.path}/screenshots');

  /// Folder for a whole device class (holds its per-locale folders).
  Directory screenshotsDeviceDir(String device) =>
      Directory('${screenshotsDir.path}/$device');

  /// Folder holding the screenshots for ([device], [locale]) — zero or more
  /// documents.
  Directory screenshotsDirFor(String device, String locale) =>
      Directory('${screenshotsDir.path}/$device/$locale');

  File get metaFile => File('${dir.path}/project.json');

  Project copyWith({String? name, List<String>? screenshotLocales}) => Project(
        name: name ?? this.name,
        dir: dir,
        createdAt: createdAt,
        screenshotLocales: screenshotLocales ?? this.screenshotLocales,
      );
}
