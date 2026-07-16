import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ImageOps {
  /// Crop to (x, y, w, h) in pixel coords. Returns a new image.
  static img.Image crop(img.Image src, int x, int y, int w, int h) {
    final cx = x.clamp(0, src.width - 1);
    final cy = y.clamp(0, src.height - 1);
    final cw = w.clamp(1, src.width - cx);
    final ch = h.clamp(1, src.height - cy);
    return img.copyCrop(src, x: cx, y: cy, width: cw, height: ch);
  }

  /// Resize to (w, h). interpolation: nearest | average | linear | cubic.
  static img.Image resize(img.Image src, int w, int h,
      {img.Interpolation interpolation = img.Interpolation.average}) {
    return img.copyResize(src, width: w, height: h,
        interpolation: interpolation);
  }

  /// Tight bounding box of every pixel whose alpha is greater than
  /// [alphaThreshold] — i.e. the visible content once transparent margins are
  /// ignored. Returns null when the image is fully (≤threshold) transparent.
  /// Scans the raw RGBA buffer directly, so it is cheap even on large images.
  static ({int x, int y, int w, int h})? opaqueBounds(
    img.Image src, {
    int alphaThreshold = 0,
  }) {
    final im = src.numChannels == 4 ? src : src.convert(numChannels: 4);
    final bytes = im.getBytes(order: img.ChannelOrder.rgba);
    final w = im.width;
    final h = im.height;
    var minX = w, minY = h, maxX = -1, maxY = -1;
    var i = 3; // alpha byte of the first pixel
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (bytes[i] > alphaThreshold) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
        i += 4;
      }
    }
    if (maxX < 0) return null; // nothing opaque
    return (x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1);
  }

  /// Auto-crop rect (pixels) for trimming transparent margins: grow [content] by
  /// [pad] on each side (clamped to the image), then — when [aspectW]/[aspectH]
  /// are positive — enlarge it to that ratio by only ever GROWING (so the
  /// content is never cut), centre it on the content, and translate it back
  /// inside [imgW]×[imgH]. With [aspectW]/[aspectH] ≤ 0 the padded box is
  /// returned as-is. The aspect-locked rect always fits the image because a rect
  /// of the image's own ratio is at most the image itself.
  static ({int x, int y, int w, int h}) contentCropRect({
    required ({int x, int y, int w, int h}) content,
    required int imgW,
    required int imgH,
    int pad = 0,
    int aspectW = 0,
    int aspectH = 0,
  }) {
    final left = (content.x - pad).clamp(0, imgW);
    final top = (content.y - pad).clamp(0, imgH);
    final right = (content.x + content.w + pad).clamp(0, imgW);
    final bottom = (content.y + content.h + pad).clamp(0, imgH);
    final cw = right - left;
    final ch = bottom - top;
    if (aspectW <= 0 || aspectH <= 0) {
      return (x: left, y: top, w: cw, h: ch);
    }
    final aspect = aspectW / aspectH;
    // Smallest size of this ratio that covers the padded box (grow-only), capped
    // at the image (guards float rounding; it can't truly exceed it).
    var rw = math.min(math.max(cw.toDouble(), ch * aspect), imgW.toDouble());
    var rh = math.min(rw / aspect, imgH.toDouble());
    rw = rh * aspect; // re-tie width to the (possibly capped) height
    rw = math.min(rw, imgW.toDouble());
    final ccx = (left + right) / 2.0;
    final ccy = (top + bottom) / 2.0;
    final rx = (ccx - rw / 2).clamp(0.0, imgW - rw);
    final ry = (ccy - rh / 2).clamp(0.0, imgH - rh);
    return (x: rx.round(), y: ry.round(), w: rw.round(), h: rh.round());
  }

  /// Flood-fill alpha from the 4 image borders. Any pixel within `tolerance`
  /// of [targetR,G,B] reachable from a border pixel is made transparent.
  /// Interior pixels of the same color (surrounded by different pixels) are
  /// preserved.
  ///
  /// tolerance is per-channel max-diff in [0, 255].
  static img.Image floodAlphaFromEdges(
    img.Image src, {
    required int targetR,
    required int targetG,
    required int targetB,
    int tolerance = 10,
  }) {
    final out = src.numChannels == 4
        ? img.Image.from(src)
        : src.convert(numChannels: 4);
    final w = out.width;
    final h = out.height;
    final seeds = <int>[];
    for (int x = 0; x < w; x++) {
      seeds.add(x); // top row
      seeds.add((h - 1) * w + x); // bottom row
    }
    for (int y = 0; y < h; y++) {
      seeds.add(y * w); // left column
      seeds.add(y * w + (w - 1)); // right column
    }
    _floodAlpha(out,
        targetR: targetR,
        targetG: targetG,
        targetB: targetB,
        tolerance: tolerance,
        seeds: seeds);
    return out;
  }

  /// Flood-fill alpha starting from a single picked pixel ([sx], [sy]), using
  /// that pixel's own color as the target. Clears a connected interior region
  /// the edge-seeded flood can't reach (e.g. a hole inside the subject).
  static img.Image floodAlphaFromPoint(
    img.Image src,
    int sx,
    int sy, {
    int tolerance = 10,
  }) {
    final out = src.numChannels == 4
        ? img.Image.from(src)
        : src.convert(numChannels: 4);
    if (sx < 0 || sy < 0 || sx >= out.width || sy >= out.height) return out;
    final seed = out.getPixel(sx, sy);
    _floodAlpha(out,
        targetR: seed.r.toInt(),
        targetG: seed.g.toInt(),
        targetB: seed.b.toInt(),
        tolerance: tolerance,
        seeds: [sy * out.width + sx]);
    return out;
  }

  /// Clear alpha (→ fully transparent) for every pixel within [radius] of the
  /// segment ([x0],[y0])–([x1],[y1]). The brush eraser calls this once per drag
  /// segment — a capsule (the swept disc), not a disc per sample point, so even
  /// a fast drag erases a continuous, gap-free band. Only pixels inside the
  /// segment's padded bounding box are touched, so it's cheap regardless of
  /// image size. Mutates [out] in place; [out] must be RGBA (4 channels) for the
  /// alpha write to take effect.
  static void eraseCapsule(
    img.Image out,
    double x0,
    double y0,
    double x1,
    double y1,
    double radius,
  ) {
    if (radius <= 0) return;
    final w = out.width;
    final h = out.height;
    final minX = math.max(0, (math.min(x0, x1) - radius).floor());
    final maxX = math.min(w - 1, (math.max(x0, x1) + radius).ceil());
    final minY = math.max(0, (math.min(y0, y1) - radius).floor());
    final maxY = math.min(h - 1, (math.max(y0, y1) + radius).ceil());
    if (minX > maxX || minY > maxY) return;
    final dx = x1 - x0;
    final dy = y1 - y0;
    final lenSq = dx * dx + dy * dy;
    final r2 = radius * radius;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        // Test the pixel's visual CENTER (x+0.5, y+0.5): the image is drawn so
        // index (x,y) covers the square [x,x+1)×[y,y+1), so the center is what
        // the on-screen brush ring (drawn at the true pointer) lines up with.
        // Sampling the integer corner instead would bias the erased band ~½px.
        final px = x + 0.5;
        final py = y + 0.5;
        // Closest point on the segment to this pixel, then its squared distance.
        var t = lenSq == 0 ? 0.0 : ((px - x0) * dx + (py - y0) * dy) / lenSq;
        if (t < 0) {
          t = 0;
        } else if (t > 1) {
          t = 1;
        }
        final ddx = px - (x0 + t * dx);
        final ddy = py - (y0 + t * dy);
        if (ddx * ddx + ddy * ddy <= r2) {
          // Zero the WHOLE pixel, not just alpha: leftover RGB under alpha-0
          // is invisible but a later flood seeded there would target it and
          // wipe everything of that color.
          if (out.getPixel(x, y).a != 0) out.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
  }

  /// Shared BFS: from each index in [seeds], make every connected pixel within
  /// [tolerance] of [targetR,G,B] transparent. Mutates [out] (assumed RGBA).
  static void _floodAlpha(
    img.Image out, {
    required int targetR,
    required int targetG,
    required int targetB,
    required int tolerance,
    required List<int> seeds,
  }) {
    final w = out.width;
    final h = out.height;
    final visited = Uint8List(w * h);
    final queue = <int>[];

    bool isTarget(int x, int y) {
      final px = out.getPixel(x, y);
      // If already transparent, treat as background to keep expansion clean.
      if (px.a == 0) return true;
      final dr = (px.r.toInt() - targetR).abs();
      final dg = (px.g.toInt() - targetG).abs();
      final db = (px.b.toInt() - targetB).abs();
      return dr <= tolerance && dg <= tolerance && db <= tolerance;
    }

    for (final idx in seeds) {
      if (idx < 0 || idx >= w * h || visited[idx] != 0) continue;
      visited[idx] = 1;
      if (isTarget(idx % w, idx ~/ w)) queue.add(idx);
    }

    while (queue.isNotEmpty) {
      final idx = queue.removeLast();
      final x = idx % w;
      final y = idx ~/ w;
      final px = out.getPixel(x, y);
      out.setPixelRgba(x, y, px.r, px.g, px.b, 0);

      void push(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) return;
        final ni = ny * w + nx;
        if (visited[ni] != 0) return;
        visited[ni] = 1;
        if (isTarget(nx, ny)) queue.add(ni);
      }

      push(x - 1, y);
      push(x + 1, y);
      push(x, y - 1);
      push(x, y + 1);
    }
  }

  /// Raw RGBA bytes of [image], PREMULTIPLIED by alpha — the format
  /// `ui.decodeImageFromPixels` expects (`PixelFormat.rgba8888` is documented
  /// as premultiplied). Handing it straight-alpha bytes makes transparent
  /// pixels blend additively: the flood keeps a pixel's old RGB under alpha 0,
  /// so a flood-cleared white background would glow solid white. Always
  /// returns a fresh buffer ([img.Image.getBytes] may return a view of the
  /// image's own data, which must not be mutated).
  static Uint8List premultipliedRgba(img.Image image) {
    final src = (image.numChannels == 4 ? image : image.convert(numChannels: 4))
        .getBytes(order: img.ChannelOrder.rgba);
    final out = Uint8List(src.length);
    for (var i = 0; i < src.length; i += 4) {
      final a = src[i + 3];
      if (a == 255) {
        out[i] = src[i];
        out[i + 1] = src[i + 1];
        out[i + 2] = src[i + 2];
      } else if (a != 0) {
        out[i] = src[i] * a ~/ 255;
        out[i + 1] = src[i + 1] * a ~/ 255;
        out[i + 2] = src[i + 2] * a ~/ 255;
      }
      out[i + 3] = a;
    }
    return out;
  }

  /// Decode PNG bytes to image. Throws if invalid.
  static img.Image decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('이미지를 디코드할 수 없습니다');
    }
    return decoded;
  }

  /// Encode image to PNG bytes (keeps alpha).
  static Uint8List encodePng(img.Image image) {
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Encode image to JPEG bytes (no alpha — for opaque art like backgrounds,
  /// much smaller than PNG).
  static Uint8List encodeJpg(img.Image image, {int quality = 90}) {
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }
}
