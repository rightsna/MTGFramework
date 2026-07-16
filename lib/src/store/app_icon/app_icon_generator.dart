import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:framework/framework.dart';

/// 한 장의 아이콘 출력 규격. [relPath]는 출력 폴더 기준 상대 경로, [px]는 정사각
/// 픽셀 크기. [opaque]가 true면 알파를 배경색으로 평탄화한다(iOS 마케팅 아이콘처럼
/// 투명을 허용하지 않는 슬롯).
class IconSpec {
  final String relPath;
  final int px;
  final bool opaque;
  const IconSpec(this.relPath, this.px, {this.opaque = false});
}

/// 표준 flutter_launcher_icons 형식의 iOS appiconset(iPhone + iPad + 마케팅).
/// 같은 픽셀 크기라도 Xcode가 파일명으로 슬롯을 구분하므로 파일명 단위로 적는다.
const _iosIcons = <IconSpec>[
  IconSpec('ios/AppIcon.appiconset/Icon-App-20x20@1x.png', 20),
  IconSpec('ios/AppIcon.appiconset/Icon-App-20x20@2x.png', 40),
  IconSpec('ios/AppIcon.appiconset/Icon-App-20x20@3x.png', 60),
  IconSpec('ios/AppIcon.appiconset/Icon-App-29x29@1x.png', 29),
  IconSpec('ios/AppIcon.appiconset/Icon-App-29x29@2x.png', 58),
  IconSpec('ios/AppIcon.appiconset/Icon-App-29x29@3x.png', 87),
  IconSpec('ios/AppIcon.appiconset/Icon-App-40x40@1x.png', 40),
  IconSpec('ios/AppIcon.appiconset/Icon-App-40x40@2x.png', 80),
  IconSpec('ios/AppIcon.appiconset/Icon-App-40x40@3x.png', 120),
  IconSpec('ios/AppIcon.appiconset/Icon-App-60x60@2x.png', 120),
  IconSpec('ios/AppIcon.appiconset/Icon-App-60x60@3x.png', 180),
  IconSpec('ios/AppIcon.appiconset/Icon-App-76x76@1x.png', 76),
  IconSpec('ios/AppIcon.appiconset/Icon-App-76x76@2x.png', 152),
  IconSpec('ios/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png', 167),
  // 마케팅(App Store) 아이콘은 알파를 허용하지 않으므로 항상 평탄화.
  IconSpec('ios/AppIcon.appiconset/Icon-App-1024x1024@1x.png', 1024,
      opaque: true),
];

/// Android 레거시 런처 아이콘(밀도별 mipmap) + Play 스토어 512 아이콘.
const _androidIcons = <IconSpec>[
  IconSpec('android/mipmap-mdpi/ic_launcher.png', 48),
  IconSpec('android/mipmap-hdpi/ic_launcher.png', 72),
  IconSpec('android/mipmap-xhdpi/ic_launcher.png', 96),
  IconSpec('android/mipmap-xxhdpi/ic_launcher.png', 144),
  IconSpec('android/mipmap-xxxhdpi/ic_launcher.png', 192),
  IconSpec('android/playstore-icon.png', 512),
];

/// macOS AppIcon.appiconset — Flutter macOS Runner 네이밍(고유 PNG 7장; 아래
/// [_macosContentsJson]이 10개 size×scale 슬롯을 이 7장에 매핑한다). macOS 아이콘은
/// 투명을 허용하므로 iOS 마케팅 슬롯 같은 opaque 강제가 없다.
const _macosIcons = <IconSpec>[
  IconSpec('macos/AppIcon.appiconset/app_icon_16.png', 16),
  IconSpec('macos/AppIcon.appiconset/app_icon_32.png', 32),
  IconSpec('macos/AppIcon.appiconset/app_icon_64.png', 64),
  IconSpec('macos/AppIcon.appiconset/app_icon_128.png', 128),
  IconSpec('macos/AppIcon.appiconset/app_icon_256.png', 256),
  IconSpec('macos/AppIcon.appiconset/app_icon_512.png', 512),
  IconSpec('macos/AppIcon.appiconset/app_icon_1024.png', 1024),
];

/// AppIcon.appiconset/Contents.json (Xcode 표준 형식). 위 [_iosIcons]의 파일명과
/// 1:1로 대응한다.
const _iosContentsJson = '''
{
  "images" : [
    { "size" : "20x20", "idiom" : "iphone", "filename" : "Icon-App-20x20@2x.png", "scale" : "2x" },
    { "size" : "20x20", "idiom" : "iphone", "filename" : "Icon-App-20x20@3x.png", "scale" : "3x" },
    { "size" : "29x29", "idiom" : "iphone", "filename" : "Icon-App-29x29@1x.png", "scale" : "1x" },
    { "size" : "29x29", "idiom" : "iphone", "filename" : "Icon-App-29x29@2x.png", "scale" : "2x" },
    { "size" : "29x29", "idiom" : "iphone", "filename" : "Icon-App-29x29@3x.png", "scale" : "3x" },
    { "size" : "40x40", "idiom" : "iphone", "filename" : "Icon-App-40x40@2x.png", "scale" : "2x" },
    { "size" : "40x40", "idiom" : "iphone", "filename" : "Icon-App-40x40@3x.png", "scale" : "3x" },
    { "size" : "60x60", "idiom" : "iphone", "filename" : "Icon-App-60x60@2x.png", "scale" : "2x" },
    { "size" : "60x60", "idiom" : "iphone", "filename" : "Icon-App-60x60@3x.png", "scale" : "3x" },
    { "size" : "20x20", "idiom" : "ipad", "filename" : "Icon-App-20x20@1x.png", "scale" : "1x" },
    { "size" : "20x20", "idiom" : "ipad", "filename" : "Icon-App-20x20@2x.png", "scale" : "2x" },
    { "size" : "29x29", "idiom" : "ipad", "filename" : "Icon-App-29x29@1x.png", "scale" : "1x" },
    { "size" : "29x29", "idiom" : "ipad", "filename" : "Icon-App-29x29@2x.png", "scale" : "2x" },
    { "size" : "40x40", "idiom" : "ipad", "filename" : "Icon-App-40x40@1x.png", "scale" : "1x" },
    { "size" : "40x40", "idiom" : "ipad", "filename" : "Icon-App-40x40@2x.png", "scale" : "2x" },
    { "size" : "76x76", "idiom" : "ipad", "filename" : "Icon-App-76x76@1x.png", "scale" : "1x" },
    { "size" : "76x76", "idiom" : "ipad", "filename" : "Icon-App-76x76@2x.png", "scale" : "2x" },
    { "size" : "83.5x83.5", "idiom" : "ipad", "filename" : "Icon-App-83.5x83.5@2x.png", "scale" : "2x" },
    { "size" : "1024x1024", "idiom" : "ios-marketing", "filename" : "Icon-App-1024x1024@1x.png", "scale" : "1x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
''';

/// macOS AppIcon.appiconset/Contents.json — 10개 size×scale 슬롯을 [_macosIcons]의
/// 7개 파일에 매핑한다(Xcode/Flutter 표준).
const _macosContentsJson = '''
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "app_icon_16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "app_icon_32.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "app_icon_32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "app_icon_64.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "app_icon_128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "app_icon_256.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "app_icon_256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "app_icon_512.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "app_icon_512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "app_icon_1024.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
''';

/// 생성 결과 요약.
class IconGenResult {
  final int written;
  final List<String> failed;
  final String outDir;
  const IconGenResult({
    required this.written,
    required this.failed,
    required this.outDir,
  });
}

/// 한 장의 소스 이미지에서 iOS/Android 앱 아이콘 세트를 생성한다.
class AppIconGenerator {
  /// 생성 대상 스펙 목록(미리보기/카운트 용).
  static List<IconSpec> specs({
    required bool ios,
    required bool android,
    required bool macos,
  }) =>
      [
        if (ios) ..._iosIcons,
        if (android) ..._androidIcons,
        if (macos) ..._macosIcons,
      ];

  /// 소스를 [size]×[size] 정사각 캔버스에 비율 유지(contain)로 그려 아이콘 한 장을
  /// 만든다. [bg]가 주어지면 그 색으로 채워 합성하고 알파 채널을 제거한 불투명(RGB)
  /// 이미지를 반환한다(App Store는 마케팅 아이콘에 알파 채널 자체를 허용하지 않음).
  /// null이면 투명 배경(RGBA) 위에 합성한다. 정사각 소스는 빈틈 없이 꽉 찬다.
  static img.Image renderIcon(img.Image src, int size, {img.Color? bg}) {
    final scale = math.min(size / src.width, size / src.height);
    final w = math.max(1, (src.width * scale).round());
    final h = math.max(1, (src.height * scale).round());
    final resized = (w == src.width && h == src.height)
        ? src
        : img.copyResize(src,
            width: w, height: h, interpolation: img.Interpolation.average);
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    if (bg != null) img.fill(canvas, color: bg);
    img.compositeImage(
      canvas,
      resized,
      dstX: ((size - w) / 2).round(),
      dstY: ((size - h) / 2).round(),
    );
    // 배경을 깐 경우 알파 채널을 떨어뜨려 완전한 불투명 PNG로 만든다.
    return bg != null ? canvas.convert(numChannels: 3) : canvas;
  }

  /// 아이콘 세트를 [outDir] 아래에 기록한다. [keepTransparency]가 true면 (마케팅
  /// 아이콘을 제외하고) 알파를 유지하고, false면 모든 아이콘을 (bgR,bgG,bgB)로
  /// 평탄화한다. 진행률은 [onProgress]로 보고한다.
  static Future<IconGenResult> generate({
    required Uint8List sourceBytes,
    required String outDir,
    required bool ios,
    required bool android,
    required bool macos,
    required bool keepTransparency,
    int bgR = 255,
    int bgG = 255,
    int bgB = 255,
    void Function(double progress, String label)? onProgress,
  }) async {
    final src = await Future(() => ImageOps.decode(sourceBytes));
    final bg = img.ColorRgba8(bgR, bgG, bgB, 255);
    final specs = AppIconGenerator.specs(ios: ios, android: android, macos: macos);

    var written = 0;
    final failed = <String>[];

    for (var i = 0; i < specs.length; i++) {
      final spec = specs[i];
      onProgress?.call(i / specs.length, spec.relPath);
      try {
        final bytes = await Future(() {
          final useBg = spec.opaque || !keepTransparency ? bg : null;
          final icon = renderIcon(src, spec.px, bg: useBg);
          return ImageOps.encodePng(icon);
        });
        final file = File('$outDir/${spec.relPath}');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        written++;
      } catch (_) {
        failed.add(spec.relPath);
      }
    }

    if (ios) {
      try {
        final f = File('$outDir/ios/AppIcon.appiconset/Contents.json');
        await f.parent.create(recursive: true);
        await f.writeAsString(_iosContentsJson);
        written++;
      } catch (_) {
        failed.add('ios/AppIcon.appiconset/Contents.json');
      }
    }

    if (macos) {
      try {
        final f = File('$outDir/macos/AppIcon.appiconset/Contents.json');
        await f.parent.create(recursive: true);
        await f.writeAsString(_macosContentsJson);
        written++;
      } catch (_) {
        failed.add('macos/AppIcon.appiconset/Contents.json');
      }
    }

    onProgress?.call(1, '완료');
    return IconGenResult(written: written, failed: failed, outDir: outDir);
  }
}
