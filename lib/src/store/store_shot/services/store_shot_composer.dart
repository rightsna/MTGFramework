import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/store_shot_params.dart';

export '../models/store_shot_params.dart';

/// [canvasW]×[canvasH] 프레임(캔버스)을 만들고 그 위에 배경 → (옵션)스크린샷
/// 프레임 → 오브젝트들을 합성한다. 배경은 [bgFit]에 따라 프레임에 채운다
/// (cover=비율유지+크롭, fill=늘이기). 스크린샷은 하단에서 살짝 걸치도록(상단
/// 좌우 모서리만 둥글게, 두꺼운 테두리) 올리며, 캔버스 밖으로 넘어간 하단은
/// 자연스럽게 잘린다. [objects]는 각자 [ObjectLayout.inFront]에 따라 폰 뒤/앞
/// 레이어로, 리스트 순서대로 쌓인다. 출력 크기는 프레임과 동일.
img.Image composeStoreShot({
  required int canvasW,
  required int canvasH,
  required img.Image background,
  BgFit bgFit = BgFit.cover,
  img.Image? screenshot,
  List<({img.Image image, ObjectLayout layout})> objects = const [],
  required StoreShotParams p,
}) {
  final canvas = img.Image(
      width: math.max(1, canvasW), height: math.max(1, canvasH), numChannels: 4);
  _drawBackground(canvas, background, bgFit);

  // 폰 뒤에 깔리는 오브젝트는 스크린샷 프레임보다 먼저(순서 유지) 합성한다.
  for (final o in objects) {
    if (!o.layout.inFront) _compositeObject(canvas, o.image, o.layout);
  }

  if (screenshot != null) {
    _compositePhone(canvas, screenshot, p);
  }

  // 폰 앞에 오는 오브젝트는 프레임 위에 마지막으로(순서 유지) 합성한다.
  for (final o in objects) {
    if (o.layout.inFront) _compositeObject(canvas, o.image, o.layout);
  }
  return canvas;
}

/// 배경을 [fit]에 맞춰 [canvas]에 그린다(제자리 수정). cover는 비율을 유지한 채
/// 프레임을 가득 채우고 넘치는 부분을 가운데 기준으로 크롭, fill은 프레임 크기에
/// 정확히 늘여 채운다.
void _drawBackground(img.Image canvas, img.Image background, BgFit fit) {
  final cw = canvas.width;
  final ch = canvas.height;
  if (fit == BgFit.fill) {
    final resized = img.copyResize(background,
        width: cw, height: ch, interpolation: img.Interpolation.cubic);
    img.compositeImage(canvas, resized);
    return;
  }
  // cover: 긴 쪽 기준으로 프레임을 덮는 배율 → 리샘플 → 가운데 정렬(넘침은 잘림).
  final scale = math.max(cw / background.width, ch / background.height);
  final w = math.max(1, (background.width * scale).round());
  final h = math.max(1, (background.height * scale).round());
  final resized = img.copyResize(background,
      width: w, height: h, interpolation: img.Interpolation.cubic);
  img.compositeImage(canvas, resized,
      dstX: ((cw - w) / 2).round(), dstY: ((ch - h) / 2).round());
}

/// 스크린샷을 모바일 프레임으로 만들어 [canvas]에 합성한다(제자리 수정).
void _compositePhone(img.Image canvas, img.Image screenshot, StoreShotParams p) {
  final canvasW = canvas.width;
  final canvasH = canvas.height;

  final contentW = math.max(1, (p.widthFraction * canvasW).round());
  final bezel = math.max(0, (p.bezelFraction * contentW).round());
  final topRadius = math.max(0, (p.topRadiusFraction * contentW).round());
  final contentH =
      math.max(1, (contentW * screenshot.height / screenshot.width).round());

  // 스크린샷을 콘텐츠 크기로 리샘플 후 상단 모서리를 둥글게.
  var content = img.copyResize(
    screenshot,
    width: contentW,
    height: contentH,
    interpolation: img.Interpolation.cubic,
  );
  if (content.numChannels < 4) content = content.convert(numChannels: 4);
  _roundTopCorners(content, topRadius);

  // 테두리 박스: 상단 테두리만 더한 단색 라운드 사각형 위에 콘텐츠를 얹는다.
  // (하단은 캔버스 밖으로 잘리므로 테두리/라운드 불필요.)
  final boxW = contentW + bezel * 2;
  final boxH = contentH + bezel;
  final box = img.Image(width: boxW, height: boxH, numChannels: 4);
  img.fill(box, color: img.ColorRgba8(p.bezelR, p.bezelG, p.bezelB, 255));
  _roundTopCorners(box, topRadius + bezel);
  // 화면(스크린) 영역을 투명하게 뚫는다 — 투명 PNG 스크린샷의 투명 부분이
  // 베젤색이 아니라 뒤의 배경을 비추도록. (베젤 테두리는 그대로 남는다.)
  _clearRoundedTopRect(box, bezel, bezel, contentW, contentH, topRadius);
  img.compositeImage(box, content, dstX: bezel, dstY: bezel);

  // 가로는 centerXFraction(중심) 기준, 세로는 topFraction. 캔버스 경계를 넘는
  // 부분은 합성 시 잘린다.
  final left = (p.centerXFraction * canvasW - boxW / 2).round();
  final top = (p.topFraction * canvasH).round();
  img.compositeImage(canvas, box, dstX: left, dstY: top);
}

/// 오브젝트(투명 컷아웃)를 [layout] 비율대로 리샘플해 [canvas]에 합성한다(제자리
/// 수정). 가로는 중심 기준, 세로는 하단(기준선) 기준이라 "서 있는" 배치가
/// 자연스럽고, 캔버스 밖으로 넘어간 부분은 합성 시 잘린다.
void _compositeObject(
    img.Image canvas, img.Image object, ObjectLayout layout) {
  final canvasW = canvas.width;
  final canvasH = canvas.height;

  final contentW = math.max(1, (layout.widthFraction * canvasW).round());
  final contentH =
      math.max(1, (contentW * object.height / object.width).round());
  var content = img.copyResize(
    object,
    width: contentW,
    height: contentH,
    interpolation: img.Interpolation.cubic,
  );
  if (content.numChannels < 4) content = content.convert(numChannels: 4);

  final centerX = layout.centerXFraction * canvasW;
  final left = (centerX - contentW / 2).round();
  final bottom = layout.bottomFraction * canvasH;
  final top = (bottom - contentH).round();
  img.compositeImage(canvas, content, dstX: left, dstY: top);
}

/// RGBA 이미지 [im]의 상단 좌우 모서리를 반경 [r]로 둥글게(알파 0) 깎는다.
/// 경계 1px는 커버리지로 부드럽게 처리. 제자리 수정.
void _roundTopCorners(img.Image im, int r) {
  if (r <= 0) return;
  final w = im.width;
  final h = im.height;
  r = math.min(r, math.min(w ~/ 2, h));
  for (var y = 0; y < r; y++) {
    final dy = y + 0.5 - r; // 두 호 모두 중심 y = r
    for (var x = 0; x < r; x++) {
      // 좌상단 — 호 중심 (r, r)
      final dxL = x + 0.5 - r;
      _mulAlpha(im, x, y, (r - math.sqrt(dxL * dxL + dy * dy)).clamp(0.0, 1.0));
      // 우상단 — 호 중심 (w - r, r)
      final xr = w - 1 - x;
      final dxR = xr + 0.5 - (w - r);
      _mulAlpha(im, xr, y, (r - math.sqrt(dxR * dxR + dy * dy)).clamp(0.0, 1.0));
    }
  }
}

/// [im] 안의 사각형 (x0,y0,w,h)에서 상단 모서리를 반경 [r]로 둥글게 한 "스크린"
/// 영역을 알파 0(투명)으로 만든다 — 베젤 박스에서 화면 구멍을 뚫는 용도. 모서리
/// 바깥(베젤이 화면 모서리를 감싸는 삼각형)은 건드리지 않는다. 제자리 수정.
void _clearRoundedTopRect(img.Image im, int x0, int y0, int w, int h, int r) {
  r = math.max(0, math.min(r, math.min(w ~/ 2, h)));
  for (var yy = 0; yy < h; yy++) {
    var xStart = 0;
    var xEnd = w;
    if (yy < r) {
      // 상단 r행: 둥근 모서리 호 안쪽만 비운다(호 중심 (r,r)/(w-r,r), 반경 r).
      final dy = r - (yy + 0.5);
      final dx = math.sqrt(math.max(0.0, r * r - dy * dy));
      xStart = (r - dx).floor().clamp(0, w);
      xEnd = (w - r + dx).ceil().clamp(0, w);
    }
    for (var xx = xStart; xx < xEnd; xx++) {
      final px = im.getPixel(x0 + xx, y0 + yy);
      im.setPixelRgba(x0 + xx, y0 + yy, px.r, px.g, px.b, 0);
    }
  }
}

void _mulAlpha(img.Image im, int x, int y, double f) {
  if (f >= 1.0) return;
  final px = im.getPixel(x, y);
  im.setPixelRgba(x, y, px.r, px.g, px.b, (px.a.toDouble() * f).round());
}
