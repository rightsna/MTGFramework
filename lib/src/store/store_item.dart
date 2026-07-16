import 'dart:io';

/// One app the store kit authors + deploys assets for. This is the ENTIRE public
/// configuration of a [StoreItemCard]: give it a display [title], an editable
/// [storageDir] (app-owned working folder that holds the layered screenshot
/// documents + app-icon source), and the [fastlaneRoot] (the app's real repo
/// root) that final rendered assets deploy into.
class StoreItem {
  const StoreItem({
    required this.title,
    required this.storageDir,
    required this.fastlaneRoot,
  });

  /// Display name shown on the card.
  final String title;

  /// Absolute path to the editable working folder (screenshots/ docs +
  /// app_icon.png live here; created on first use).
  final String storageDir;

  /// Absolute path to the app's Flutter repo root — where authored assets are
  /// deployed (fastlane screenshot folders + native icon locations).
  final String fastlaneRoot;

  // ---- deploy targets (all derived from [fastlaneRoot]) ----

  /// iOS App Store screenshots for [iosLocale] — fastlane deliver reads every
  /// PNG here and picks the device slot by image resolution.
  Directory iosScreenshotsDir(String iosLocale) =>
      Directory('$fastlaneRoot/ios/fastlane/screenshots/$iosLocale');

  /// iOS app-icon asset catalog (the sized PNGs + Contents.json).
  Directory get iosAppIconSet =>
      Directory('$fastlaneRoot/ios/Runner/Assets.xcassets/AppIcon.appiconset');

  /// macOS app-icon asset catalog.
  Directory get macosAppIconSet =>
      Directory('$fastlaneRoot/macos/Runner/Assets.xcassets/AppIcon.appiconset');

  /// Android legacy launcher-icon resource root (holds the mipmap-* folders).
  Directory get androidResDir =>
      Directory('$fastlaneRoot/android/app/src/main/res');

  /// Google Play images folder for [androidLocale] (holds icon.png +
  /// phoneScreenshots/ / sevenInchScreenshots/ / tenInchScreenshots/).
  Directory androidImagesDir(String androidLocale) => Directory(
      '$fastlaneRoot/android/fastlane/metadata/android/$androidLocale/images');

  bool existsSync() => Directory(fastlaneRoot).existsSync();
}

/// Map an App Store Connect localization code (also the iOS screenshot folder
/// name) to the matching Google Play locale folder. Falls back to the code
/// as-is for locales not listed.
String androidLocaleFor(String ascCode) => switch (ascCode) {
      'ko' => 'ko-KR',
      'en-US' => 'en-US',
      'ja' => 'ja-JP',
      'zh-Hans' => 'zh-CN',
      'zh-Hant' => 'zh-TW',
      'ru' => 'ru-RU',
      'it' => 'it-IT',
      _ => ascCode,
    };
