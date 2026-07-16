import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'image_ops.dart';

/// The reusable editing core of the Image Editor: a canvas plus Crop / Flood
/// Alpha / Resize tools, driven entirely off an in-memory [img.Image]. It owns
/// no I/O — callers feed it an initial image and read the latest edited image
/// back through [onChanged], then save it however they like (a stage's item
/// icon, …).
///
/// Exposed via [showImageEditDialog] (used by the App Icon / Store Screenshot
/// editors to touch up a source), and embeddable directly with a [toolFooter].
class ImageEditWorkspace extends StatefulWidget {
  /// The image to edit. Passing a different instance reloads the workspace
  /// (resetting tool state), so callers switch images by swapping this in.
  final img.Image image;

  /// Called once on load and after every applied edit, with the current
  /// working image — the caller's source of truth for saving.
  final ValueChanged<img.Image> onChanged;

  /// Optional widget pinned to the bottom of the right tool column (e.g. the
  /// screen's save panel). Null in the dialog, which uses its own actions.
  final Widget? toolFooter;

  const ImageEditWorkspace({
    super.key,
    required this.image,
    required this.onChanged,
    this.toolFooter,
  });

  @override
  State<ImageEditWorkspace> createState() => _ImageEditWorkspaceState();
}

// Order matters: the toolbar renders one button per value. Flood Alpha sits
// second (it's the default selected tool on open), and `eraser` last places it
// immediately left of the separate Reset button.
enum _EditTool { view, floodAlpha, crop, resize, eraser }

extension on _EditTool {
  String get label {
    switch (this) {
      case _EditTool.view:
        return 'View';
      case _EditTool.crop:
        return 'Crop';
      case _EditTool.floodAlpha:
        return 'Flood Alpha';
      case _EditTool.resize:
        return 'Resize';
      case _EditTool.eraser:
        return '지우개';
    }
  }

  IconData get icon {
    switch (this) {
      case _EditTool.view:
        return Icons.pan_tool_alt_outlined;
      case _EditTool.crop:
        return Icons.crop;
      case _EditTool.floodAlpha:
        return Icons.colorize;
      case _EditTool.resize:
        return Icons.aspect_ratio;
      case _EditTool.eraser:
        return Icons.format_color_reset;
    }
  }
}

/// [setState] that is safe to call from callbacks the framework can fire
/// while the widget tree is LOCKED — e.g. a gesture recognizer disposed
/// mid-gesture (an applied edit bumps the canvas key, unmounting the old
/// [_Canvas]) synchronously fires onPanCancel, and a removed [MouseRegion]
/// fires onExit. Calling setState there throws "called when widget tree was
/// locked", so during the frame's persistent-callbacks phase the update is
/// deferred to after the frame instead.
mixin _SafeSetState<T extends StatefulWidget> on State<T> {
  void setStateSafe(VoidCallback fn) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }
}

class _ImageEditWorkspaceState extends State<ImageEditWorkspace>
    with _SafeSetState {
  late img.Image _original;
  img.Image? _working;
  ui.Image? _uiImage;
  int _uiVersion = 0;

  _EditTool _tool = _EditTool.floodAlpha;

  Rect? _cropRect;

  /// When on, "투명 여백 자동 감지" proposes a square (1:1) region instead of
  /// keeping the original image ratio. Defaults on.
  bool _autoCropSquare = true;

  int _floodR = 255, _floodG = 255, _floodB = 255;
  int _floodTolerance = 10;

  // ---- Drag-to-erase (magic erase) state ----
  // Press a point to seed a point-flood, then drag outward: the farther the
  // pointer is dragged from the seed, the higher the tolerance, so more of the
  // connected region is erased. A live preview tracks the drag; release commits.
  Offset? _floodSeed; // seed pixel (image space); non-null while dragging
  Offset? _floodDragPos; // current pointer (image space)
  int _floodDragTol = 0; // tolerance derived from the drag distance
  ui.Image? _floodPreviewUi; // live preview shown instead of _uiImage
  bool _floodPreviewBusy = false; // a preview flood is being computed
  int? _floodPendingTol; // latest tolerance requested while one was in flight
  int _floodGen = 0; // bumped per drag; stale preview work from older gens drops
  int? _floodLastRenderedTol; // tolerance the current _floodPreviewUi shows
  img.Image? _floodPreviewBase; // downscaled _working snapshot, re-flooded live
  double _floodPreviewScale = 1.0; // _floodPreviewBase size ÷ _working size

  // ---- Brush eraser state ----
  // A few fixed circular brush diameters (image px); the canvas draws a ring at
  // the cursor so the actual footprint is visible before erasing.
  static const List<int> _brushSizes = [8, 16, 32, 64, 128];
  int _brushSize = 32;

  /// Previous erase point (image space) within the active stroke, so each drag
  /// segment erases a gap-free capsule from there to the new point. Null when no
  /// stroke is in progress.
  Offset? _erasePrev;

  // Coalesced live re-render during an erase stroke: only one fast decode runs
  // at a time; the latest request while busy is run next (like the flood
  // preview). Keeps a fast drag from queueing dozens of decodes.
  bool _eraseRenderBusy = false;
  bool _eraseRenderPending = false;

  int _resizeW = 0, _resizeH = 0;
  bool _keepAspect = true;
  img.Interpolation _resizeInterp = img.Interpolation.average;

  /// Most-recent-first list of applied resize sizes (deduped, capped at 5),
  /// shown under the Resize tool as quick-pick chips. Session-global (static) so
  /// it survives switching images, reopening the editor, and the edit dialog —
  /// each of which builds a fresh workspace State.
  static final List<({int w, int h})> _resizeHistory = [];

  /// 되돌리기 스냅샷: 각 항목은 한 번의 편집(크롭/플러드/리사이즈/매직 지우개)
  /// 또는 한 번의 브러시 스트로크 직전의 working 이미지다. [_maxUndo]개까지만
  /// 보관하며(초과 시 가장 오래된 것부터 버림), 새 이미지를 로드하면 비운다.
  final List<img.Image> _undoStack = [];
  static const int _maxUndo = 20;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load(widget.image);
  }

  @override
  void didUpdateWidget(covariant ImageEditWorkspace old) {
    super.didUpdateWidget(old);
    if (!identical(old.image, widget.image)) {
      _load(widget.image);
    }
  }

  Future<void> _load(img.Image image) async {
    setState(() => _busy = true);
    try {
      final working = img.Image.from(image);
      final ui_ = await _toUi(working);
      if (!mounted) return;
      setState(() {
        _original = image;
        _working = working;
        _uiImage = ui_;
        _uiVersion++;
        _tool = _EditTool.floodAlpha;
        _cropRect = null;
        _clearFloodDragState();
        _undoStack.clear();
        _resizeW = working.width;
        _resizeH = working.height;
      });
      widget.onChanged(working);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ui.Image> _toUi(img.Image image) async {
    final png = ImageOps.encodePng(image);
    return decodeImageFromList(png);
  }

  /// Apply [next] as the new working image. Records the outgoing image as an
  /// undo step unless [pushUndo] is false (set by [_undo] so restoring a
  /// snapshot doesn't itself become a new step).
  Future<void> _applyAndRefresh(img.Image next, {bool pushUndo = true}) async {
    setState(() => _busy = true);
    try {
      final ui_ = await _toUi(next);
      if (!mounted) return;
      final prev = _working;
      setState(() {
        if (pushUndo && prev != null) _pushUndo(prev);
        _working = next;
        _uiImage = ui_;
        _uiVersion++;
        _cropRect = null;
        _clearFloodDragState();
        _resizeW = next.width;
        _resizeH = next.height;
      });
      widget.onChanged(next);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() => _applyAndRefresh(img.Image.from(_original));

  /// Record [image] (a stable working image no longer being mutated, or a copy
  /// for the in-place brush) as an undo step, capped at [_maxUndo].
  void _pushUndo(img.Image image) {
    _undoStack.add(image);
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
  }

  /// 되돌리기: restore the most recent pre-edit snapshot. No-op when the stack is
  /// empty or an edit is in flight.
  Future<void> _undo() async {
    if (_undoStack.isEmpty || _busy) return;
    await _applyAndRefresh(_undoStack.removeLast(), pushUndo: false);
  }

  Future<void> _applyCrop() async {
    final wImg = _working;
    final r = _cropRect;
    if (wImg == null || r == null) return;
    final next = ImageOps.crop(
      wImg,
      r.left.round(),
      r.top.round(),
      r.width.round(),
      r.height.round(),
    );
    await _applyAndRefresh(next);
  }

  /// Auto-select the visible content: find the opaque bounding box, grow it by
  /// a small padding AND back out to the original image ratio (so the crop keeps
  /// the same proportions), then set it as the crop rect — the user taps Apply,
  /// so the proposed region is visible first. No-op on a fully transparent image.
  Future<void> _autoCropToContent() async {
    final wImg = _working;
    if (wImg == null || _busy) return;
    setState(() => _busy = true);
    try {
      final b = await Future(() => ImageOps.opaqueBounds(wImg));
      if (!mounted || b == null) return;
      final r = ImageOps.contentCropRect(
        content: b,
        imgW: wImg.width,
        imgH: wImg.height,
        pad: math.max(2, (math.max(b.w, b.h) * 0.04).round()),
        // Square (1:1) when requested, otherwise keep the original image ratio.
        aspectW: _autoCropSquare ? 1 : wImg.width,
        aspectH: _autoCropSquare ? 1 : wImg.height,
      );
      setState(() => _cropRect = Rect.fromLTWH(
          r.x.toDouble(), r.y.toDouble(), r.w.toDouble(), r.h.toDouble()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyFlood() async {
    final wImg = _working;
    if (wImg == null) return;
    final next = await Future(() => ImageOps.floodAlphaFromEdges(
          wImg,
          targetR: _floodR,
          targetG: _floodG,
          targetB: _floodB,
          tolerance: _floodTolerance,
        ));
    await _applyAndRefresh(next);
  }

  // ---- Drag-to-erase (magic erase) ----

  /// Tolerance for a drag of [dist] image-pixels from the seed. Normalised by
  /// the image's short side so the feel is the same on a tiny icon and a large
  /// background: dragging ~half the short side reaches full (255) tolerance.
  int _tolForDistance(double dist) {
    final wImg = _working;
    if (wImg == null) return 0;
    final span = math.min(wImg.width, wImg.height).toDouble();
    if (span <= 0) return 0;
    return ((dist / (span * 0.5)) * 255.0).clamp(0.0, 255.0).round();
  }

  /// Press: seed the point-flood at ([x], [y]) and show the amber overlay at
  /// once. The downscaled snapshot used for the live preview is built off the
  /// synchronous path (a big resize would otherwise hitch the press), then
  /// re-flooded for every drag step; the full-resolution flood runs only once,
  /// on release.
  void _onFloodDragStart(int x, int y) {
    final wImg = _working;
    if (wImg == null || _busy) return;
    if (x < 0 || y < 0 || x >= wImg.width || y >= wImg.height) return;
    setState(() {
      _floodGen++;
      _floodSeed = Offset(x.toDouble(), y.toDouble());
      _floodDragPos = _floodSeed;
      _floodDragTol = 0;
      _floodPreviewUi = null;
      _floodLastRenderedTol = null;
      _floodPreviewBase = null;
      _floodPreviewScale = 1.0;
    });
    _prepareFloodBase(_floodGen, wImg);
  }

  /// Build (off the UI path) the downscaled base for [gen]'s drag, then kick off
  /// its first preview. Abandoned if a newer drag started meanwhile.
  Future<void> _prepareFloodBase(int gen, img.Image wImg) async {
    final scale = _previewScaleFor(wImg);
    final base = scale < 1.0
        ? await Future(() => ImageOps.resize(
            wImg,
            math.max(1, (wImg.width * scale).round()),
            math.max(1, (wImg.height * scale).round())))
        : wImg;
    if (!mounted || _floodGen != gen || _floodSeed == null) return;
    _floodPreviewBase = base;
    _floodPreviewScale = identical(base, wImg) ? 1.0 : scale;
    _requestFloodPreview(_floodDragTol);
  }

  /// Drag: distance from the seed sets the tolerance; preview tracks it live.
  void _onFloodDragUpdate(double x, double y) {
    final seed = _floodSeed;
    if (seed == null) return;
    final tol = _tolForDistance((Offset(x, y) - seed).distance);
    setState(() {
      _floodDragPos = Offset(x, y);
      _floodDragTol = tol;
    });
    _requestFloodPreview(tol);
  }

  /// Release: commit the full-resolution flood at the final tolerance, then
  /// clear the (downscaled) preview. [_busy] is held across the whole commit so
  /// a fresh pan can't start and have its state wiped by this commit's refresh.
  Future<void> _onFloodDragEnd() async {
    final seed = _floodSeed;
    final base = _working;
    final tol = _floodDragTol;
    setState(() {
      _busy = true;
      _clearFloodDragState();
    });
    if (seed == null || base == null) {
      setState(() => _busy = false);
      return;
    }
    // try/finally so a throw in the full-res flood can't leave _busy stuck true
    // (that would permanently disable every apply/reset button + further drags).
    try {
      final sx = seed.dx.round().clamp(0, base.width - 1);
      final sy = seed.dy.round().clamp(0, base.height - 1);
      final next = await Future(
          () => ImageOps.floodAlphaFromPoint(base, sx, sy, tolerance: tol));
      await _applyAndRefresh(next); // also toggles _busy off in its own finally
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  /// Cancel (pointer lost mid-drag): drop the uncommitted preview. Fired
  /// synchronously from the recognizer's dispose when the canvas is swapped
  /// out mid-gesture, so it must go through [setStateSafe].
  void _onFloodDragCancel() => setStateSafe(_clearFloodDragState);

  /// Recompute the live preview at [tol] on the downscaled base. Only one flood
  /// runs at a time; the latest tolerance requested while busy is coalesced and
  /// run next. Each run is tagged with the current drag generation so work from
  /// a drag that has since ended or been replaced is discarded rather than
  /// painted onto a newer drag.
  Future<void> _requestFloodPreview(int tol) async {
    if (_floodPreviewBusy) {
      _floodPendingTol = tol;
      return;
    }
    if (tol == _floodLastRenderedTol) return; // idle & already showing this tol
    final gen = _floodGen;
    _floodPreviewBusy = true;
    var current = tol;
    try {
      while (true) {
        final seed = _floodSeed;
        final base = _floodPreviewBase;
        if (seed == null || base == null || _floodGen != gen) return;
        final sx = (seed.dx * _floodPreviewScale).round().clamp(0, base.width - 1);
        final sy =
            (seed.dy * _floodPreviewScale).round().clamp(0, base.height - 1);
        final preview = await Future(
            () => ImageOps.floodAlphaFromPoint(base, sx, sy, tolerance: current));
        final ui_ = await _toUiFast(preview);
        if (!mounted || _floodSeed == null || _floodGen != gen) return;
        setState(() {
          _floodPreviewUi = ui_;
          _floodLastRenderedTol = current;
        });
        final pending = _floodPendingTol;
        _floodPendingTol = null;
        if (pending == null || pending == current) break;
        current = pending;
      }
    } finally {
      _floodPreviewBusy = false;
    }
  }

  /// Longest-side cap for the cheap live preview; the commit stays full-res.
  double _previewScaleFor(img.Image im) {
    const maxSide = 900;
    final longest = math.max(im.width, im.height);
    return longest > maxSide ? maxSide / longest : 1.0;
  }

  void _clearFloodDragState() {
    _floodSeed = null;
    _floodDragPos = null;
    _floodDragTol = 0;
    _floodPreviewUi = null;
    _floodPendingTol = null;
    _floodLastRenderedTol = null;
    _floodPreviewBase = null;
    _floodPreviewScale = 1.0;
    // Also drop any in-progress erase stroke (called on load / apply / tool
    // switch), so switching away mid-drag can't keep erasing.
    _erasePrev = null;
  }

  /// Fast [img.Image] → [ui.Image] via raw RGBA (no PNG round-trip), so the
  /// live preview stays responsive during a drag. The bytes must be
  /// premultiplied (see [ImageOps.premultipliedRgba]) or transparent pixels
  /// with leftover RGB render as solid color.
  Future<ui.Image> _toUiFast(img.Image image) {
    final rgba = ImageOps.premultipliedRgba(image);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<void> _applyResize() async {
    final wImg = _working;
    if (wImg == null) return;
    final w = _resizeW.clamp(1, 8192);
    final h = _resizeH.clamp(1, 8192);
    _pushResizeHistory(w, h);
    final next = ImageOps.resize(wImg, w, h, interpolation: _resizeInterp);
    await _applyAndRefresh(next);
  }

  /// Record an applied resize size, most-recent-first, deduped, capped at 5.
  void _pushResizeHistory(int w, int h) {
    _resizeHistory.removeWhere((e) => e.w == w && e.h == h);
    _resizeHistory.insert(0, (w: w, h: h));
    if (_resizeHistory.length > 5) {
      _resizeHistory.removeRange(5, _resizeHistory.length);
    }
  }

  void _onPickColor(int x, int y) {
    final wImg = _working;
    if (wImg == null) return;
    if (x < 0 || y < 0 || x >= wImg.width || y >= wImg.height) return;
    final p = wImg.getPixel(x, y);
    setState(() {
      _floodR = p.r.toInt();
      _floodG = p.g.toInt();
      _floodB = p.b.toInt();
    });
  }

  // ---- Brush eraser ----

  double get _brushRadius => _brushSize / 2.0;

  /// Diameter of the panel's preview dot. The real brushes (up to 128px) can't
  /// fit the 36px swatch, so map each size by RANK to a distinct, growing dot —
  /// every selectable size reads as larger than the previous one. (A true
  /// proportional dot would clip the two biggest sizes to the same swatch.)
  double get _brushDotPreviewPx {
    final i = _brushSizes.indexOf(_brushSize);
    return 8.0 + (i < 0 ? 0 : i) * 6.0; // [8,16,32,64,128] → 8,14,20,26,32 px
  }

  /// Ensure [_working] has an alpha channel so erased pixels can go transparent.
  /// A loaded opaque source (e.g. a JPG) decodes to 3 channels; converting swaps
  /// in a new instance, so re-publish it to the caller. Pixels are unchanged, so
  /// the displayed image needs no separate refresh.
  void _ensureWorkingRgba() {
    final wImg = _working;
    if (wImg == null || wImg.numChannels == 4) return;
    final rgba = wImg.convert(numChannels: 4);
    _working = rgba;
    widget.onChanged(rgba);
  }

  /// Press / single tap: start a stroke and erase a dot at ([x], [y]).
  void _onEraseStart(double x, double y) {
    final wImg = _working;
    if (wImg == null || _busy) return;
    // Snapshot the pre-stroke image (a copy — the brush mutates in place) so the
    // whole stroke is a single undo step.
    _pushUndo(img.Image.from(wImg));
    _ensureWorkingRgba();
    ImageOps.eraseCapsule(_working!, x, y, x, y, _brushRadius);
    _erasePrev = Offset(x, y);
    _scheduleEraseRender();
  }

  /// Drag: erase the capsule swept from the previous point to ([x], [y]) so a
  /// fast drag leaves no gaps.
  void _onEraseUpdate(double x, double y) {
    final prev = _erasePrev;
    final cur = _working;
    if (prev == null || cur == null) return;
    ImageOps.eraseCapsule(cur, prev.dx, prev.dy, x, y, _brushRadius);
    _erasePrev = Offset(x, y);
    _scheduleEraseRender();
  }

  /// Release: end the stroke and publish the final image (mutated in place, so
  /// the caller's reference already sees it — this just signals completion). The
  /// trailing render guarantees the last segment is shown even if the most
  /// recent live render was still in flight when the finger lifted.
  void _onEraseEnd() {
    if (_erasePrev == null) return;
    _erasePrev = null;
    final cur = _working;
    if (cur != null) widget.onChanged(cur);
    _scheduleEraseRender();
  }

  /// Pointer lost mid-stroke (gesture arena stolen, window deactivated, …). The
  /// brush erases in place with no per-stroke snapshot, so pixels already cleared
  /// stay cleared — the expected behavior for a brush. Commit exactly like a
  /// normal release rather than pretending to roll the stroke back.
  void _onEraseCancel() => _onEraseEnd();

  /// Refresh the displayed image during an erase stroke. Uses the fast RGBA
  /// path (no PNG round-trip) and coalesces so only one decode runs at a time.
  /// Crucially it does NOT bump [_uiVersion]: that key drives the [_Canvas]'s
  /// identity, and rebuilding it mid-drag would kill the live erase gesture;
  /// the painter picks up the new image by reference via shouldRepaint.
  void _scheduleEraseRender() {
    if (_eraseRenderBusy) {
      _eraseRenderPending = true;
      return;
    }
    _eraseRenderBusy = true;
    _runEraseRender();
  }

  Future<void> _runEraseRender() async {
    try {
      while (true) {
        final wImg = _working;
        if (wImg == null) break;
        final ui_ = await _toUiFast(wImg);
        if (!mounted) return;
        setState(() => _uiImage = ui_);
        if (!_eraseRenderPending) break;
        _eraseRenderPending = false;
      }
    } finally {
      _eraseRenderBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ⌘Z / Ctrl+Z undo. autofocus keeps the shortcut live after canvas clicks;
    // a focused text field (Resize inputs) gets the keystroke first for text
    // undo, so the two don't fight.
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        },
        child: Row(
          children: [
            Expanded(child: _buildCenter()),
            const VerticalDivider(width: 1),
            SizedBox(width: 320, child: _buildRight()),
          ],
        ),
      ),
    );
  }

  Widget _buildCenter() {
    final ui_ = _uiImage;
    final wImg = _working;
    if (ui_ == null || wImg == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        Positioned.fill(
          child: _Canvas(
            key: ValueKey(_uiVersion),
            // While dragging-to-erase, show the live (possibly downscaled) flood
            // preview, but fit/overlay against the full working dimensions so the
            // displayed rect and the amber overlay stay put.
            image: _floodPreviewUi ?? ui_,
            logicalW: wImg.width,
            logicalH: wImg.height,
            tool: _tool,
            cropRect: _cropRect,
            floodSeed: _floodSeed,
            floodDragPos: _floodDragPos,
            floodTol: _floodDragTol,
            onCropRect: (r) => setState(() => _cropRect = r),
            onPickColor: _onPickColor,
            onFloodDragStart: _onFloodDragStart,
            onFloodDragUpdate: _onFloodDragUpdate,
            onFloodDragEnd: _onFloodDragEnd,
            onFloodDragCancel: _onFloodDragCancel,
            eraseRadius: _brushRadius,
            onEraseStart: _onEraseStart,
            onEraseUpdate: _onEraseUpdate,
            onEraseEnd: _onEraseEnd,
            onEraseCancel: _onEraseCancel,
          ),
        ),
        if (_busy)
          const Positioned(
            right: 12,
            top: 12,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  Widget _buildRight() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolBar(),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: _toolPanel(),
          ),
        ),
        if (widget.toolFooter != null) ...[
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(12), child: widget.toolFooter!),
        ],
      ],
    );
  }

  Widget _toolBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final t in _EditTool.values)
            Tooltip(
              message: t.label,
              child: IconButton(
                onPressed: _working == null
                    ? null
                    : () => setState(() {
                          _tool = t;
                          _clearFloodDragState();
                        }),
                isSelected: _tool == t,
                icon: Icon(t.icon),
                style: IconButton.styleFrom(
                  backgroundColor: _tool == t
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                ),
              ),
            ),
          Tooltip(
            message: '되돌리기 (⌘Z)',
            child: IconButton(
              onPressed: (_busy || _undoStack.isEmpty) ? null : _undo,
              icon: const Icon(Icons.undo),
            ),
          ),
          Tooltip(
            message: 'Reset',
            child: IconButton(
              onPressed: _busy ? null : _reset,
              icon: const Icon(Icons.restart_alt),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolPanel() {
    final wImg = _working;
    if (wImg == null) return const SizedBox.shrink();
    switch (_tool) {
      case _EditTool.view:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('Image'),
            Text('현재 크기: ${wImg.width} × ${wImg.height} px',
                style: const TextStyle(fontSize: 12)),
          ],
        );

      case _EditTool.crop:
        final r = _cropRect;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('Crop'),
            const Text(
              '캔버스에서 드래그로 영역을 선택한 뒤 Apply를 누르세요.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (r == null)
              const Text('영역 미지정',
                  style: TextStyle(color: Colors.grey, fontSize: 12))
            else
              Text(
                'x: ${r.left.toStringAsFixed(0)}  '
                'y: ${r.top.toStringAsFixed(0)}\n'
                'w: ${r.width.toStringAsFixed(0)}  '
                'h: ${r.height.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.content_cut, size: 16),
              label: const Text('투명 여백 자동 감지'),
              onPressed: _busy ? null : _autoCropToContent,
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _autoCropSquare,
              title: const Text('정사각형 비율', style: TextStyle(fontSize: 13)),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _autoCropSquare = v ?? false),
            ),
            const Text(
              '불투명한 내용 영역을 찾아 적당한 여백을 두고 자동 선택합니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_cropRect == null || _busy) ? null : _applyCrop,
              child: const Text('Apply Crop'),
            ),
          ],
        );

      case _EditTool.floodAlpha:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('Flood Alpha'),
            const Text(
              '캔버스를 클릭해 외곽 배경색을 픽한 뒤,\n허용오차를 조정하고 Apply를 누르세요.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, _floodR, _floodG, _floodB),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 8),
                Text('R:$_floodR  G:$_floodG  B:$_floodB',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Tolerance: $_floodTolerance',
                style: const TextStyle(fontSize: 12)),
            Slider(
              value: _floodTolerance.toDouble(),
              min: 0,
              max: 128,
              divisions: 128,
              label: '$_floodTolerance',
              onChanged: (v) => setState(() => _floodTolerance = v.round()),
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: _busy ? null : _applyFlood,
              child: const Text('Apply Flood (바깥 기준)'),
            ),
            const Divider(height: 24),
            _sectionTitle('특정 영역 지우기 (드래그)'),
            const Text(
              '지울 지점을 누른 채 바깥으로 드래그하세요.\n'
              '멀어질수록 허용오차가 커져 같은 색 영역이 더 넓게\n'
              '지워집니다. 손을 떼면 적용됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.auto_fix_high,
                    size: 16,
                    color: _floodSeed != null
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey),
                const SizedBox(width: 6),
                Text(
                  _floodSeed != null
                      ? '드래그 중 — 허용오차 $_floodDragTol'
                      : '대기 중 (캔버스에서 드래그)',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        );

      case _EditTool.eraser:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('지우개'),
            const Text(
              '브러시 크기를 고른 뒤 캔버스에서 드래그하면\n지나간 자리가 즉시 투명해집니다.\n(클릭 한 번으로 점 하나만 지울 수도 있어요.)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            const Text('브러시 크기 (지름, px)', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _brushSizes)
                  ChoiceChip(
                    label: Text('$s', style: const TextStyle(fontSize: 12)),
                    selected: _brushSize == s,
                    onSelected: (_) => setState(() => _brushSize = s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // A filled dot previewing the brush's relative size.
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: Container(
                      width: _brushDotPreviewPx,
                      height: _brushDotPreviewPx,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('현재 브러시: ${_brushSize}px',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        );

      case _EditTool.resize:
        return _ResizePanel(
          width: _resizeW,
          height: _resizeH,
          aspectLock: _keepAspect,
          original: wImg,
          interpolation: _resizeInterp,
          onChanged: (w, h, keep, interp) => setState(() {
            _resizeW = w;
            _resizeH = h;
            _keepAspect = keep;
            _resizeInterp = interp;
          }),
          onApply: _applyResize,
          history: _resizeHistory,
          onPickHistory: (w, h) => setState(() {
            _resizeW = w;
            _resizeH = h;
          }),
          busy: _busy,
        );
    }
  }
}

/// Open the reusable editor in a dialog seeded with [pngBytes]. Returns the
/// edited image as PNG bytes when the user saves, or null if they cancel.
Future<Uint8List?> showImageEditDialog(
  BuildContext context, {
  required Uint8List pngBytes,
  String title = '이미지 편집',
}) async {
  final img.Image decoded;
  try {
    decoded = ImageOps.decode(pngBytes);
  } catch (_) {
    return null;
  }
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ImageEditDialog(title: title, image: decoded),
  );
}

class _ImageEditDialog extends StatefulWidget {
  final String title;
  final img.Image image;
  const _ImageEditDialog({required this.title, required this.image});

  @override
  State<_ImageEditDialog> createState() => _ImageEditDialogState();
}

class _ImageEditDialogState extends State<_ImageEditDialog> {
  img.Image? _current;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: math.min(size.width - 48, 1100),
        height: math.min(size.height - 48, 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ImageEditWorkspace(
                image: widget.image,
                onChanged: (im) => _current = im,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.save_alt),
                    label: const Text('저장'),
                    onPressed: () {
                      final im = _current;
                      if (im == null) {
                        Navigator.of(context).pop();
                        return;
                      }
                      Navigator.of(context).pop(ImageOps.encodePng(im));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Canvas with tool-specific gesture handling
// =====================================================================
class _Canvas extends StatefulWidget {
  final ui.Image image;

  /// Logical image size used for fitting and overlay coords. Equals [image]'s
  /// size normally, but during a drag [image] may be a downscaled preview while
  /// these stay the full working size, so the displayed rect doesn't jump.
  final int logicalW;
  final int logicalH;

  final _EditTool tool;
  final Rect? cropRect;

  /// Drag-to-erase overlay state (image space), null when not dragging.
  final Offset? floodSeed;
  final Offset? floodDragPos;
  final int floodTol;

  final ValueChanged<Rect?> onCropRect;

  /// A tap (not a drag) in Flood Alpha picks the edge-flood background color.
  final void Function(int x, int y) onPickColor;

  /// Drag-to-erase: press seeds the point-flood, drag sets the tolerance from
  /// the distance, release commits, cancel (pointer lost) drops the preview.
  final void Function(int x, int y) onFloodDragStart;
  final void Function(double x, double y) onFloodDragUpdate;
  final VoidCallback onFloodDragEnd;
  final VoidCallback onFloodDragCancel;

  /// Brush eraser: [eraseRadius] is the brush radius in image px (drives the
  /// cursor ring); the callbacks carry the pointer in image space. A tap erases
  /// a dot; a drag erases the swept path; release commits; cancel also commits
  /// (the in-place erase has no per-stroke undo — Reset reverts everything).
  final double eraseRadius;
  final void Function(double x, double y) onEraseStart;
  final void Function(double x, double y) onEraseUpdate;
  final VoidCallback onEraseEnd;
  final VoidCallback onEraseCancel;

  const _Canvas({
    super.key,
    required this.image,
    required this.logicalW,
    required this.logicalH,
    required this.tool,
    required this.cropRect,
    required this.floodSeed,
    required this.floodDragPos,
    required this.floodTol,
    required this.onCropRect,
    required this.onPickColor,
    required this.onFloodDragStart,
    required this.onFloodDragUpdate,
    required this.onFloodDragEnd,
    required this.onFloodDragCancel,
    required this.eraseRadius,
    required this.onEraseStart,
    required this.onEraseUpdate,
    required this.onEraseEnd,
    required this.onEraseCancel,
  });

  @override
  State<_Canvas> createState() => _CanvasState();
}

class _CanvasState extends State<_Canvas> with _SafeSetState {
  Offset? _dragStart;
  Offset? _dragCurrent;

  /// Pointer position in screen space, tracked only for the eraser so the brush
  /// ring can follow the cursor on hover and the finger during a drag.
  Offset? _hoverScreen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final fit = _fit(
          imageW: widget.logicalW.toDouble(),
          imageH: widget.logicalH.toDouble(),
          containerW: c.maxWidth,
          containerH: c.maxHeight,
        );

        Offset toImage(Offset s) => Offset(
              (s.dx - fit.offset.dx) / fit.scale,
              (s.dy - fit.offset.dy) / fit.scale,
            );

        final crop = widget.tool == _EditTool.crop;
        final flood = widget.tool == _EditTool.floodAlpha;
        final eraser = widget.tool == _EditTool.eraser;
        final panActive = crop || flood || eraser;

        final gesture = GestureDetector(
          behavior: HitTestBehavior.opaque,
          // A tap (no drag): Flood Alpha picks the edge-flood color; the eraser
          // erases a single dot. Using onTapUp (not onTapDown) means a drag,
          // which the pan recognizer claims, never also fires here.
          onTapUp: (!flood && !eraser)
              ? null
              : (d) {
                  final p = toImage(d.localPosition);
                  if (flood) {
                    widget.onPickColor(p.dx.round(), p.dy.round());
                  } else {
                    widget.onEraseStart(p.dx, p.dy);
                    widget.onEraseEnd();
                  }
                },
          onPanStart: !panActive
              ? null
              : (d) {
                  final p = toImage(d.localPosition);
                  if (crop) {
                    setState(() {
                      _dragStart = p;
                      _dragCurrent = p;
                    });
                  } else if (flood) {
                    widget.onFloodDragStart(p.dx.round(), p.dy.round());
                  } else {
                    setState(() => _hoverScreen = d.localPosition);
                    widget.onEraseStart(p.dx, p.dy);
                  }
                },
          onPanUpdate: !panActive
              ? null
              : (d) {
                  final p = toImage(d.localPosition);
                  if (crop) {
                    setState(() => _dragCurrent = p);
                  } else if (flood) {
                    widget.onFloodDragUpdate(p.dx, p.dy);
                  } else {
                    setState(() => _hoverScreen = d.localPosition);
                    widget.onEraseUpdate(p.dx, p.dy);
                  }
                },
          onPanEnd: !panActive
              ? null
              : (_) {
                  if (eraser) {
                    widget.onEraseEnd();
                    return;
                  }
                  if (flood) {
                    widget.onFloodDragEnd();
                    return;
                  }
                  final s = _dragStart;
                  final e = _dragCurrent;
                  setState(() {
                    _dragStart = null;
                    _dragCurrent = null;
                  });
                  if (s == null || e == null) return;
                  final r = Rect.fromPoints(s, e);
                  if (r.width < 2 || r.height < 2) {
                    widget.onCropRect(null);
                    return;
                  }
                  final clamped = Rect.fromLTRB(
                    r.left.clamp(0.0, widget.logicalW.toDouble()),
                    r.top.clamp(0.0, widget.logicalH.toDouble()),
                    r.right.clamp(0.0, widget.logicalW.toDouble()),
                    r.bottom.clamp(0.0, widget.logicalH.toDouble()),
                  );
                  widget.onCropRect(clamped);
                },
          // Pointer cancelled mid-drag (lost the arena, window deactivated, …):
          // crop and flood discard the in-progress preview (no commit yet); the
          // eraser keeps what it already cleared (it erases in place — see
          // _onEraseCancel) and commits like a normal release.
          onPanCancel: !panActive
              ? null
              : () {
                  if (crop) {
                    setStateSafe(() {
                      _dragStart = null;
                      _dragCurrent = null;
                    });
                  } else if (flood) {
                    widget.onFloodDragCancel();
                  } else {
                    widget.onEraseCancel();
                  }
                },
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _CanvasPainter(
              image: widget.image,
              fit: fit,
              cropRect: widget.cropRect,
              dragRect: (_dragStart != null && _dragCurrent != null)
                  ? Rect.fromPoints(_dragStart!, _dragCurrent!)
                  : null,
              floodSeed: widget.floodSeed,
              floodDragPos: widget.floodDragPos,
              floodTol: widget.floodTol,
              eraseRingCenter: eraser ? _hoverScreen : null,
              eraseRingRadius: widget.eraseRadius * fit.scale,
            ),
          ),
        );

        // The eraser draws a brush ring that tracks the cursor; a MouseRegion
        // feeds it hover positions (drag positions come from the pan handlers).
        if (!eraser) return gesture;
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          onHover: (e) => setState(() => _hoverScreen = e.localPosition),
          onExit: (_) => setStateSafe(() => _hoverScreen = null),
          child: gesture,
        );
      },
    );
  }

  static _Fit _fit({
    required double imageW,
    required double imageH,
    required double containerW,
    required double containerH,
  }) {
    final scale = math.min(containerW / imageW, containerH / imageH);
    final dw = imageW * scale;
    final dh = imageH * scale;
    return _Fit(
      scale: scale,
      offset: Offset((containerW - dw) / 2, (containerH - dh) / 2),
      size: Size(dw, dh),
    );
  }
}

class _Fit {
  final double scale;
  final Offset offset;
  final Size size;
  _Fit({required this.scale, required this.offset, required this.size});
}

class _CanvasPainter extends CustomPainter {
  final ui.Image image;
  final _Fit fit;
  final Rect? cropRect;
  final Rect? dragRect;

  /// Drag-to-erase overlay (image space): seed point, current pointer, and the
  /// tolerance the drag distance maps to. All null/0 when not dragging.
  final Offset? floodSeed;
  final Offset? floodDragPos;
  final int floodTol;

  /// Brush-eraser cursor ring (screen space): centre + radius. Null/0 when the
  /// eraser isn't active or the pointer has left the canvas.
  final Offset? eraseRingCenter;
  final double eraseRingRadius;

  _CanvasPainter({
    required this.image,
    required this.fit,
    required this.cropRect,
    required this.dragRect,
    required this.floodSeed,
    required this.floodDragPos,
    required this.floodTol,
    required this.eraseRingCenter,
    required this.eraseRingRadius,
  });

  Rect _toScreen(Rect r) => Rect.fromLTRB(
        r.left * fit.scale + fit.offset.dx,
        r.top * fit.scale + fit.offset.dy,
        r.right * fit.scale + fit.offset.dx,
        r.bottom * fit.scale + fit.offset.dy,
      );

  Offset _toScreenPt(Offset o) => Offset(
        o.dx * fit.scale + fit.offset.dx,
        o.dy * fit.scale + fit.offset.dy,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF1E1E1E);
    canvas.drawRect(Offset.zero & size, bg);

    _drawChecker(canvas, fit.offset & fit.size);

    final src =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = fit.offset & fit.size;
    canvas.drawImageRect(image, src, dst, Paint());

    final cr = cropRect ?? dragRect;
    if (cr != null) {
      final r = _toScreen(cr);
      final fill = Paint()..color = Colors.cyan.withValues(alpha: 0.18);
      final stroke = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRect(r, fill);
      canvas.drawRect(r, stroke);
    }

    _drawFloodDrag(canvas);
    _drawEraseRing(canvas);
  }

  /// Brush footprint: a white ring over a dark halo (so it reads on any art)
  /// with a centre dot, drawn at the cursor while the eraser tool is active.
  void _drawEraseRing(Canvas canvas) {
    final center = eraseRingCenter;
    if (center == null || eraseRingRadius <= 0) return;
    canvas.drawCircle(
      center,
      eraseRingRadius,
      Paint()
        ..color = const Color(0x99000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      center,
      eraseRingRadius,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(center, 1.5, Paint()..color = const Color(0xFFFFFFFF));
  }

  /// Drag-to-erase feedback: a ring from the seed whose radius follows the
  /// pointer (bigger = higher tolerance), plus the live tolerance readout.
  void _drawFloodDrag(Canvas canvas) {
    final seed = floodSeed;
    final pos = floodDragPos;
    if (seed == null || pos == null) return;
    final sc = _toScreenPt(seed);
    final pc = _toScreenPt(pos);
    final radius = (pc - sc).distance;
    const accentColor = Color(0xFFD81B60); // 자주색 (crimson), visible on any art
    final accent = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (radius > 1) canvas.drawCircle(sc, radius, accent);
    canvas.drawLine(sc, pc, accent);
    canvas.drawCircle(sc, 3.5, Paint()..color = accentColor);

    final tp = TextPainter(
      text: TextSpan(
        text: 'tol $floodTol',
        style: const TextStyle(
          color: accentColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pc + const Offset(10, -6));
  }

  void _drawChecker(Canvas canvas, Rect area) {
    const cell = 12.0;
    final dark = Paint()..color = const Color(0xFF2A2A2A);
    final light = Paint()..color = const Color(0xFF3A3A3A);
    canvas.save();
    canvas.clipRect(area);
    final cols = (area.width / cell).ceil() + 1;
    final rows = (area.height / cell).ceil() + 1;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final x = area.left + c * cell;
        final y = area.top + r * cell;
        final paint = ((r + c) & 1) == 0 ? dark : light;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) =>
      old.image != image ||
      old.fit.scale != fit.scale ||
      old.fit.offset != fit.offset ||
      old.cropRect != cropRect ||
      old.dragRect != dragRect ||
      old.floodSeed != floodSeed ||
      old.floodDragPos != floodDragPos ||
      old.floodTol != floodTol ||
      old.eraseRingCenter != eraseRingCenter ||
      old.eraseRingRadius != eraseRingRadius;
}

// =====================================================================
// Resize panel (stateful so input controllers don't reset on parent rebuild)
// =====================================================================
class _ResizePanel extends StatefulWidget {
  final int width;
  final int height;
  final bool aspectLock;
  final img.Image original;
  final img.Interpolation interpolation;
  final void Function(
      int width, int height, bool keep, img.Interpolation interp) onChanged;
  final Future<void> Function() onApply;

  /// Recently applied sizes (most-recent-first) and a tap handler that loads one
  /// back into the width/height fields.
  final List<({int w, int h})> history;
  final void Function(int width, int height) onPickHistory;
  final bool busy;

  const _ResizePanel({
    required this.width,
    required this.height,
    required this.aspectLock,
    required this.original,
    required this.interpolation,
    required this.onChanged,
    required this.onApply,
    required this.history,
    required this.onPickHistory,
    required this.busy,
  });

  @override
  State<_ResizePanel> createState() => _ResizePanelState();
}

class _ResizePanelState extends State<_ResizePanel> {
  late final TextEditingController _wCtrl;
  late final TextEditingController _hCtrl;

  @override
  void initState() {
    super.initState();
    _wCtrl = TextEditingController(text: widget.width.toString());
    _hCtrl = TextEditingController(text: widget.height.toString());
  }

  @override
  void didUpdateWidget(covariant _ResizePanel old) {
    super.didUpdateWidget(old);
    if (widget.width != int.tryParse(_wCtrl.text)) {
      _wCtrl.text = widget.width.toString();
    }
    if (widget.height != int.tryParse(_hCtrl.text)) {
      _hCtrl.text = widget.height.toString();
    }
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  double get _aspect => widget.original.width / widget.original.height;

  void _setW(String s) {
    final w = int.tryParse(s.trim());
    if (w == null || w <= 0) return;
    int h = widget.height;
    if (widget.aspectLock) {
      h = (w / _aspect).round().clamp(1, 8192);
      _hCtrl.text = h.toString();
    }
    widget.onChanged(w, h, widget.aspectLock, widget.interpolation);
  }

  void _setH(String s) {
    final h = int.tryParse(s.trim());
    if (h == null || h <= 0) return;
    int w = widget.width;
    if (widget.aspectLock) {
      w = (h * _aspect).round().clamp(1, 8192);
      _wCtrl.text = w.toString();
    }
    widget.onChanged(w, h, widget.aspectLock, widget.interpolation);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Resize'),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _wCtrl,
              keyboardType: TextInputType.number,
              decoration: _dec(label: 'Width'),
              onSubmitted: _setW,
              onChanged: _setW,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _hCtrl,
              keyboardType: TextInputType.number,
              decoration: _dec(label: 'Height'),
              onSubmitted: _setH,
              onChanged: _setH,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: widget.aspectLock,
          title: const Text('비율 유지', style: TextStyle(fontSize: 13)),
          onChanged: (v) => widget.onChanged(widget.width, widget.height,
              v ?? widget.aspectLock, widget.interpolation),
        ),
        DropdownButtonFormField<img.Interpolation>(
          initialValue: widget.interpolation,
          decoration: _dec(label: 'Interpolation'),
          isDense: true,
          items: const [
            DropdownMenuItem(
                value: img.Interpolation.nearest, child: Text('Nearest')),
            DropdownMenuItem(
                value: img.Interpolation.average, child: Text('Average')),
            DropdownMenuItem(
                value: img.Interpolation.linear, child: Text('Linear')),
            DropdownMenuItem(
                value: img.Interpolation.cubic, child: Text('Cubic')),
          ],
          onChanged: (v) {
            if (v != null) {
              widget.onChanged(
                  widget.width, widget.height, widget.aspectLock, v);
            }
          },
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: widget.busy ? null : () => widget.onApply(),
          child: const Text('Apply Resize'),
        ),
        if (widget.history.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('최근 리사이즈 (최대 5)',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in widget.history)
                ActionChip(
                  label: Text('${e.w}×${e.h}',
                      style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onPressed:
                      widget.busy ? null : () => widget.onPickHistory(e.w, e.h),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// shared helpers

InputDecoration _dec({String? label, String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    );

Widget _sectionTitle(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
