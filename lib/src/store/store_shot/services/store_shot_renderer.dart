import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:framework/framework.dart';
import 'package:image/image.dart' as img;

import 'store_shot_composer.dart';

/// 스토어 샷의 무거운 픽셀 작업(디코드·축소·합성·인코딩)을 모두 백그라운드
/// 아이솔레이트에서 실행하는 서비스. 미리보기는 순수 위젯으로 그리므로(합성 없음)
/// 여기 합성은 내보내기/문서 저장 때만 쓰인다.
class StoreShotRenderer {
  const StoreShotRenderer._();

  /// 소스 바이트를 디코드 + 최대 변 [maxSide]로 축소한 이미지를 만든다(오프스레드).
  /// 미리보기 위젯이 폰/캐릭터 비율을 알아내는 데 쓰고, 원본은 따로 보관한다.
  static Future<img.Image> decodeDownscaled(Uint8List bytes, int maxSide) =>
      Isolate.run(() => _downscale(ImageOps.decode(bytes), maxSide));

  /// 프레임([canvasW]×[canvasH]) 크기로 직접 합성 → PNG/JPG 인코딩까지 한
  /// 아이솔레이트에서 처리해 인코딩된 바이트를 돌려준다. 내보내기·문서 미리보기
  /// 저장에 공용으로 쓴다(프레임이 곧 출력 크기라 별도 리사이즈가 없다).
  static Future<Uint8List> encode({
    required int canvasW,
    required int canvasH,
    required Uint8List backgroundBytes,
    BgFit bgFit = BgFit.cover,
    Uint8List? screenshotBytes,
    List<({Uint8List bytes, ObjectLayout layout})> objects = const [],
    required StoreShotParams params,
    bool jpg = false,
    int quality = 90,
  }) {
    return Isolate.run(() {
      final bg = ImageOps.decode(backgroundBytes);
      final shot =
          screenshotBytes == null ? null : ImageOps.decode(screenshotBytes);
      final objs = [
        for (final o in objects)
          (image: ImageOps.decode(o.bytes), layout: o.layout),
      ];
      final composed = composeStoreShot(
        canvasW: canvasW,
        canvasH: canvasH,
        background: bg,
        bgFit: bgFit,
        screenshot: shot,
        objects: objs,
        p: params,
      );
      return jpg
          ? ImageOps.encodeJpg(composed, quality: quality)
          : ImageOps.encodePng(composed);
    });
  }

  /// 바이트의 원본(디코드) 픽셀 크기만 오프스레드로 알아낸다 — 옛 문서(프레임
  /// 정보 없음)를 배경 원본 크기로 마이그레이션할 때 사용.
  static Future<(int, int)> decodeSize(Uint8List bytes) =>
      Isolate.run(() {
        final im = ImageOps.decode(bytes);
        return (im.width, im.height);
      });

  static img.Image _downscale(img.Image im, int maxSide) {
    final longest = math.max(im.width, im.height);
    if (longest <= maxSide) return im;
    final s = maxSide / longest;
    return img.copyResize(
      im,
      width: math.max(1, (im.width * s).round()),
      height: math.max(1, (im.height * s).round()),
    );
  }
}
