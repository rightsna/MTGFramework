import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_locale.dart';
import '../controllers/store_shot_controller.dart';
import '../models/store_shot_doc.dart';
import 'widgets/checker_painter.dart';

/// 좌측 미리보기: 프레임(캔버스) 안에 배경(cover/fill) · 스크린샷 폰 프레임 ·
/// 캐릭터를 **순수 Flutter 위젯**으로 그린다(픽셀 합성 없음 — 그건 내보내기/저장
/// 때만). 덕분에 편집(드래그/슬라이더/크기/채움) 중엔 아이솔레이트 합성 없이
/// 즉시·안정적으로 갱신된다. 내보내기 결과는 [composeStoreShot]가 동일 규칙으로
/// 픽셀 합성하므로 보이는 그대로 저장된다.
class PreviewView extends StatelessWidget {
  const PreviewView({
    super.key,
    required this.isScreenshotTab,
    required this.isObjectsTab,
  });

  /// 스크린샷 탭일 때만 폰 프레임 드래그/모서리 핸들을 보인다.
  final bool isScreenshotTab;

  /// 오브젝트 탭일 때만 오브젝트 선택/이동/리사이즈 핸들을 보인다.
  final bool isObjectsTab;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StoreShotController>();
    final bg = c.bgBytes;
    return ColoredBox(
      color: const Color(0xFF1A1A1D),
      child: bg == null
          ? Center(
              child: Text(
                tr(context, '배경 이미지를 불러오면\n미리보기가 표시됩니다',
                    'Load a background image\nto see a preview'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _frame(context, c, bg, constraints),
              ),
            ),
    );
  }

  Widget _frame(BuildContext context, StoreShotController c, Uint8List bg,
      BoxConstraints constraints) {
    final availW = constraints.maxWidth;
    final availH = constraints.maxHeight;
    final aspect = c.frameAspect;
    double dispW, dispH;
    if (availW / availH > aspect) {
      dispH = availH;
      dispW = availH * aspect;
    } else {
      dispW = availW;
      dispH = availW / aspect;
    }
    final offX = (availW - dispW) / 2;
    final offY = (availH - dispH) / 2;

    final showHandles = isScreenshotTab && c.shotBytes != null && !c.busy;

    return Stack(
      children: [
        // 프레임 내용(배경/캐릭터/폰) — 프레임 경계로 클립.
        Positioned(
          left: offX,
          top: offY,
          width: dispW,
          height: dispH,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: _frameContent(c, bg, dispW, dispH),
            ),
          ),
        ),
        if (showHandles) ..._frameHandles(context, c, dispW, dispH, offX, offY),
        if (isObjectsTab && !c.busy)
          ..._objectControls(context, c, dispW, dispH, offX, offY),
        // 최상위: 프레임 경계 형광 1px 테두리(클릭 통과).
        Positioned(
          left: offX,
          top: offY,
          width: dispW,
          height: dispH,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xFF39FF14), width: 1),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 배경 → (폰 뒤 캐릭터) → 폰 프레임 → (폰 앞 캐릭터) 순으로 쌓는다
  /// (composeStoreShot와 동일 순서/규칙).
  List<Widget> _frameContent(
      StoreShotController c, Uint8List bg, double dispW, double dispH) {
    return [
      // 투명 영역 식별용 체커(배경이 프레임을 덮으면 안 보임).
      const Positioned.fill(child: CustomPaint(painter: CheckerPainter())),
      Positioned.fill(
        child: Image.memory(
          bg,
          fit: c.bgFit == BgFit.cover ? BoxFit.cover : BoxFit.fill,
          gaplessPlayback: true,
        ),
      ),
      // 폰 뒤 오브젝트(순서 유지) → 폰 → 폰 앞 오브젝트.
      for (final o in c.objects)
        if (!o.layout.inFront) _objectWidget(o, dispW, dispH),
      ?_phone(c, dispW, dispH),
      for (final o in c.objects)
        if (o.layout.inFront) _objectWidget(o, dispW, dispH),
    ];
  }

  /// 스크린샷을 모바일 프레임(상단 라운드 + 테두리)으로 만든 위젯. 하단은 프레임
  /// 클립으로 잘린다. 스크린샷 비율은 [StoreShotController.shotPreview]에서 얻는다.
  Widget? _phone(StoreShotController c, double dispW, double dispH) {
    final bytes = c.shotBytes;
    final sp = c.shotPreview;
    if (bytes == null || sp == null) return null;
    final contentW = c.widthFraction * dispW;
    final bezel = (c.noBezel ? 0.0 : c.bezelFraction) * contentW;
    final topRadius = c.topRadiusFraction * contentW;
    final contentH = contentW * sp.height / sp.width;
    final boxW = contentW + bezel * 2;
    final boxH = contentH + bezel;
    final left = c.centerXFraction * dispW - boxW / 2;
    final top = c.topFraction * dispH;
    final p = c.params;
    final bezelColor = Color.fromARGB(255, p.bezelR, p.bezelG, p.bezelB);

    return Positioned(
      left: left,
      top: top,
      width: boxW,
      height: boxH,
      child: ClipRRect(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(topRadius + bezel)),
        child: ColoredBox(
          color: c.noBezel ? const Color(0x00000000) : bezelColor,
          child: Padding(
            padding: EdgeInsets.fromLTRB(bezel, bezel, bezel, 0),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(topRadius)),
              child: Image.memory(
                bytes,
                width: contentW,
                height: contentH,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 오브젝트(투명 컷아웃): 가로 중심·하단 기준선으로 배치, 비율은 미리보기 축소본.
  Widget _objectWidget(ShotObject o, double dispW, double dispH) {
    final cp = o.preview;
    final l = o.layout;
    final cw = l.widthFraction * dispW;
    final ch = cw * cp.height / cp.width;
    final left = l.centerXFraction * dispW - cw / 2;
    final top = l.bottomFraction * dispH - ch;
    return Positioned(
      left: left,
      top: top,
      width: cw,
      height: ch,
      child: Image.memory(o.bytes, fit: BoxFit.fill, gaplessPlayback: true),
    );
  }

  /// 오브젝트 탭 오버레이: 비선택 오브젝트는 탭하면 선택되고, 선택 오브젝트엔
  /// 이동(본체 드래그) + 모서리 리사이즈 핸들을 붙인다.
  List<Widget> _objectControls(BuildContext context, StoreShotController c,
      double dispW, double dispH, double offX, double offY) {
    final primary = Theme.of(context).colorScheme.primary;
    const hs = 16.0;
    final out = <Widget>[];

    for (var i = 0; i < c.objects.length; i++) {
      final o = c.objects[i];
      final l = o.layout;
      final w = l.widthFraction * dispW;
      final h = w * o.preview.height / o.preview.width;
      final x = offX + l.centerXFraction * dispW - w / 2;
      final y = offY + l.bottomFraction * dispH - h;
      final selected = c.selectedObject == i;

      if (!selected) {
        // 선택용 탭 타깃(옅은 테두리로 위치 힌트).
        out.add(Positioned(
          left: x,
          top: y,
          width: w,
          height: h,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => c.selectObject(i),
            child: DecoratedBox(
              decoration:
                  BoxDecoration(border: Border.all(color: Colors.white24)),
            ),
          ),
        ));
        continue;
      }

      // 선택됨: 본체 이동 + 모서리 리사이즈.
      Widget corner(double cx, double cy, bool rightSide, MouseCursor cursor) {
        return Positioned(
          left: cx - hs / 2,
          top: cy - hs / 2,
          width: hs,
          height: hs,
          child: MouseRegion(
            cursor: cursor,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => c.resizeObject(i, d.delta.dx, rightSide, dispW),
              child: Container(
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
        );
      }

      out.addAll([
        Positioned(
          left: x,
          top: y,
          width: w,
          height: h,
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) =>
                  c.moveObject(i, d.delta.dx, d.delta.dy, dispW, dispH),
              child: DecoratedBox(
                decoration:
                    BoxDecoration(border: Border.all(color: primary, width: 1.5)),
              ),
            ),
          ),
        ),
        corner(x, y, false, SystemMouseCursors.resizeUpLeftDownRight),
        corner(x + w, y, true, SystemMouseCursors.resizeUpRightDownLeft),
        corner(x, y + h, false, SystemMouseCursors.resizeUpRightDownLeft),
        corner(x + w, y + h, true, SystemMouseCursors.resizeUpLeftDownRight),
      ]);
    }
    return out;
  }

  List<Widget> _frameHandles(BuildContext context, StoreShotController c,
      double dispW, double dispH, double offX, double offY) {
    final boxWFrac = c.boxWFrac;
    final boxHFrac = c.boxHFrac ?? 0;
    final leftFrac = c.centerXFraction - boxWFrac / 2;
    final x = offX + leftFrac * dispW;
    final y = offY + c.topFraction * dispH;
    final double w = (boxWFrac * dispW).clamp(2.0, dispW * 3).toDouble();
    final double h = (boxHFrac * dispH).clamp(2.0, dispH * 3).toDouble();
    final primary = Theme.of(context).colorScheme.primary;
    const hs = 16.0;

    Widget corner(double cx, double cy, bool rightSide, MouseCursor cursor) {
      return Positioned(
        left: cx - hs / 2,
        top: cy - hs / 2,
        width: hs,
        height: hs,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => c.resizeFrame(d.delta.dx, rightSide, dispW),
            child: Container(
              decoration: BoxDecoration(
                color: primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ),
      );
    }

    return [
      Positioned(
        left: x,
        top: y,
        width: w,
        height: h,
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) =>
                c.moveFrame(d.delta.dx, d.delta.dy, dispW, dispH),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: primary, width: 1.5),
              ),
            ),
          ),
        ),
      ),
      corner(x, y, false, SystemMouseCursors.resizeUpLeftDownRight),
      corner(x + w, y, true, SystemMouseCursors.resizeUpRightDownLeft),
      corner(x, y + h, false, SystemMouseCursors.resizeUpRightDownLeft),
      corner(x + w, y + h, true, SystemMouseCursors.resizeUpLeftDownRight),
    ];
  }
}
