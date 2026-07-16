import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/store_shot_doc.dart';
import '../services/store_shot_renderer.dart';
import '../services/store_shot_store.dart';

/// 짧은 안내 문구(KO/EN). 컨트롤러는 context가 없어 직접 로컬라이즈하지 못하므로
/// 두 언어를 함께 담아 두고, UI가 현재 언어로 골라 보여준다.
typedef StatusMsg = ({String ko, String en});

/// 런타임 오브젝트: 원본 바이트 + 미리보기 축소본(비율 계산용) + 이름 + 레이아웃.
class ShotObject {
  ShotObject({
    required this.bytes,
    required this.preview,
    required this.name,
    this.layout = const ObjectLayout(),
  });

  Uint8List bytes;
  img.Image preview;
  String name;
  ObjectLayout layout;
}

/// Store Screenshot 화면의 단일 상태원(ChangeNotifier). 소스 이미지(배경/스크린샷/
/// 캐릭터) · 레이아웃 비율 · 출력 프레임 · 합성 미리보기 · 내보내기/저장까지 전부
/// 여기서 소유한다. 파일 선택·이미지 에디터·AI 다이얼로그·저장 위치 선택처럼
/// BuildContext가 필요한 단계는 UI(탭/화면)가 처리하고, 결과 바이트만 이 컨트롤러로
/// 넘긴다. 무거운 픽셀 작업은 [StoreShotRenderer](아이솔레이트)에 위임한다.
class StoreShotController extends ChangeNotifier {
  StoreShotController({int frameW = 1242, int frameH = 2688})
      : _frameW = frameW,
        _frameH = frameH {
    frameWCtrl = TextEditingController(text: '$frameW');
    frameHCtrl = TextEditingController(text: '$frameH');
  }

  // ── 소스(원본 바이트 + 미리보기 축소본 + 이름) ──
  Uint8List? bgBytes, shotBytes;
  img.Image? bgPreview, shotPreview;
  String? bgName, shotName;

  /// 오브젝트(추가 이미지) 목록 — 리스트 순서대로 합성/표시된다.
  final List<ShotObject> objects = [];

  /// 미리보기에서 선택된(이동/리사이즈 핸들이 붙는) 오브젝트 인덱스. 없으면 null.
  int? selectedObject;

  // ── 레이아웃(모두 캔버스 대비 비율) ──
  double widthFraction = 0.72;
  double topFraction = 0.30;
  double centerXFraction = 0.5;
  double topRadiusFraction = 0.06;
  double bezelFraction = 0.022;
  int bezelIndex = 0;
  bool noBezel = false;

  // ── 출력 프레임(= 내보내기 픽셀 크기) + 형식 ──
  int _frameW;
  int _frameH;
  BgFit bgFit = BgFit.cover;
  late final TextEditingController frameWCtrl;
  late final TextEditingController frameHCtrl;
  bool exportJpg = false;
  int jpgQuality = 90;

  int get frameW => _frameW;
  int get frameH => _frameH;

  // ── 진행/상태 ──
  bool busy = false;
  bool dirty = false; // 저장되지 않은 변경
  StatusMsg status = (ko: '', en: '');

  /// 토스트(스낵바)용 신호: [toast]가 마지막 메시지, [toastSeq]가 바뀔 때 UI가
  /// 스낵바를 띄운다(같은 메시지 연속도 구분되도록 시퀀스로).
  StatusMsg toast = (ko: '', en: '');
  int toastSeq = 0;

  Directory? sessionDoc;

  /// dispose 이후 진행 중이던 async 작업(저장의 busy 해제, 디바운스된 합성 등)이
  /// notifyListeners를 호출하면 "used after disposed" 예외가 난다 — 가드로 무시.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // ── 파생 값 ──
  StoreShotDoc get currentDoc => StoreShotDoc(
        frameW: _frameW,
        frameH: _frameH,
        bgFit: bgFit,
        widthFraction: widthFraction,
        topFraction: topFraction,
        centerXFraction: centerXFraction,
        topRadiusFraction: topRadiusFraction,
        bezelFraction: bezelFraction,
        bezelIndex: bezelIndex,
        noBezel: noBezel,
        objects: [for (final o in objects) o.layout],
      );

  StoreShotParams get params => currentDoc.toParams();
  double get frameAspect => _frameW / _frameH;
  bool get ready => bgBytes != null;

  /// 베젤 포함 프레임 박스 너비 ÷ 캔버스 너비.
  double get boxWFrac =>
      widthFraction * (1 + 2 * (noBezel ? 0.0 : bezelFraction));

  /// 베젤 포함 프레임 박스 높이 ÷ 캔버스 높이 (스샷 비율 필요, 없으면 null).
  double? get boxHFrac {
    final shot = shotPreview;
    if (shot == null) return null;
    final bezelFrac = noBezel ? 0.0 : bezelFraction;
    return widthFraction * frameAspect * (shot.height / shot.width + bezelFrac);
  }

  // ── 상태/토스트 헬퍼 ──
  void setStatus(String ko, String en) {
    status = (ko: ko, en: en);
    notifyListeners();
  }

  void emitToast(String ko, String en) {
    status = (ko: ko, en: en);
    toast = (ko: ko, en: en);
    toastSeq++;
    notifyListeners();
  }

  Future<void> _withBusy(Future<void> Function() body) async {
    busy = true;
    notifyListeners();
    try {
      await body();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ── 소스 설정(파일/에디터/AI 결과를 UI가 바이트로 넘김) ──

  Future<void> setBackground(Uint8List bytes, {required String name}) =>
      _withBusy(() async {
        try {
          final p = await StoreShotRenderer.decodeDownscaled(bytes, 1000);
          bgBytes = bytes;
          bgName = name;
          bgPreview = p;
          dirty = true;
          setStatus(
              '배경: $name (${p.width}×${p.height} 미리보기)', 'Background: $name');
        } catch (e) {
          emitToast('배경 로드 실패: $e', 'Failed to load background: $e');
        }
      });

  /// 이미지 에디터/AI 결과로 배경을 교체. [aiName]을 주면 이름까지 바꾼다.
  Future<void> replaceBackground(Uint8List bytes,
          {String? aiName, required StatusMsg note}) =>
      _withBusy(() async {
        try {
          final p = await StoreShotRenderer.decodeDownscaled(bytes, 1000);
          bgBytes = bytes;
          if (aiName != null) bgName = aiName;
          bgPreview = p;
          dirty = true;
          setStatus(note.ko, note.en);
        } catch (e) {
          emitToast('반영 실패: $e', 'Failed to apply: $e');
        }
      });

  Future<void> setScreenshot(Uint8List bytes, {required String name}) =>
      _withBusy(() async {
        try {
          final p = await StoreShotRenderer.decodeDownscaled(bytes, 1400);
          shotBytes = bytes;
          shotName = name;
          shotPreview = p;
          _alignToBottom();
          dirty = true;
          setStatus('스크린샷: $name', 'Screenshot: $name');
        } catch (e) {
          emitToast('스크린샷 로드 실패: $e', 'Failed to load screenshot: $e');
        }
      });

  Future<void> replaceScreenshot(Uint8List bytes, {required StatusMsg note}) =>
      _withBusy(() async {
        try {
          final p = await StoreShotRenderer.decodeDownscaled(bytes, 1400);
          shotBytes = bytes;
          shotPreview = p;
          _alignToBottom();
          dirty = true;
          setStatus(note.ko, note.en);
        } catch (e) {
          emitToast('반영 실패: $e', 'Failed to apply: $e');
        }
      });

  void clearScreenshot() {
    shotBytes = null;
    shotName = null;
    shotPreview = null;
    dirty = true;
    setStatus('스크린샷 제거됨', 'Screenshot removed');
  }

  // ── 오브젝트(복수) ──

  /// 새 오브젝트를 목록 끝에 추가하고 바로 선택(미리보기에서 이동/리사이즈하도록).
  Future<void> addObject(Uint8List bytes, {required String name}) =>
      _withBusy(() async {
        try {
          final p = await StoreShotRenderer.decodeDownscaled(bytes, 1000);
          objects.add(ShotObject(bytes: bytes, preview: p, name: name));
          selectedObject = objects.length - 1;
          dirty = true;
          setStatus('오브젝트 추가: $name', 'Object added: $name');
        } catch (e) {
          emitToast('오브젝트 로드 실패: $e', 'Failed to load object: $e');
        }
      });

  /// 미리보기에서 조작할 오브젝트를 선택(null=해제).
  void selectObject(int? index) {
    selectedObject =
        (index != null && index >= 0 && index < objects.length) ? index : null;
    notifyListeners();
  }

  /// 선택 오브젝트를 미리보기 드래그로 이동(화면 dx/dy, 표시 너비/높이).
  void moveObject(int index, double dx, double dy, double dispW, double dispH) {
    if (index < 0 || index >= objects.length) return;
    final l = objects[index].layout;
    objects[index].layout = l.copyWith(
      centerXFraction: (l.centerXFraction + dx / dispW).clamp(-0.5, 1.5),
      bottomFraction: (l.bottomFraction + dy / dispH).clamp(-0.5, 1.6),
    );
    dirty = true;
    notifyListeners();
  }

  /// 선택 오브젝트를 모서리 드래그로 크기 조절(중심 X·하단선 고정, 비율 유지).
  void resizeObject(int index, double dxScreen, bool rightSide, double dispW) {
    if (index < 0 || index >= objects.length) return;
    final l = objects[index].layout;
    final w = (l.widthFraction + (rightSide ? 2 : -2) * dxScreen / dispW)
        .clamp(0.03, 1.5);
    objects[index].layout = l.copyWith(widthFraction: w);
    dirty = true;
    notifyListeners();
  }

  /// [index] 오브젝트의 이미지를 교체(이미지 에디터 결과).
  Future<void> replaceObjectImage(int index, Uint8List bytes,
          {required StatusMsg note}) =>
      _withBusy(() async {
        if (index < 0 || index >= objects.length) return;
        try {
          final p = await StoreShotRenderer.decodeDownscaled(bytes, 1000);
          objects[index].bytes = bytes;
          objects[index].preview = p;
          dirty = true;
          setStatus(note.ko, note.en);
        } catch (e) {
          emitToast('반영 실패: $e', 'Failed to apply: $e');
        }
      });

  /// [index] 오브젝트의 레이아웃(너비/위치/레이어)을 갱신.
  void updateObjectLayout(int index, ObjectLayout layout) {
    if (index < 0 || index >= objects.length) return;
    objects[index].layout = layout;
    dirty = true;
    notifyListeners();
  }

  void removeObject(int index) {
    if (index < 0 || index >= objects.length) return;
    objects.removeAt(index);
    // 선택 인덱스 보정.
    if (selectedObject == index) {
      selectedObject = null;
    } else if (selectedObject != null && selectedObject! > index) {
      selectedObject = selectedObject! - 1;
    }
    dirty = true;
    setStatus('오브젝트 제거됨', 'Object removed');
  }

  // ── 레이아웃 변경(탭 슬라이더/스와치) ──

  /// 탭(스크린샷 슬라이더/스와치)에서 올라온 새 레이아웃 문서를 반영(프레임/bgFit/
  /// 오브젝트는 컨트롤러가 소유하므로 폰 프레임 비율 필드만 취한다).
  void applyDoc(StoreShotDoc d) {
    widthFraction = d.widthFraction;
    topFraction = d.topFraction;
    centerXFraction = d.centerXFraction;
    topRadiusFraction = d.topRadiusFraction;
    bezelFraction = d.bezelFraction;
    bezelIndex = d.bezelIndex;
    noBezel = d.noBezel;
    dirty = true;
    notifyListeners();
  }

  // ── 프레임/배경 채움 ──

  void onFrameFieldsChanged() {
    final w = int.tryParse(frameWCtrl.text.trim());
    final h = int.tryParse(frameHCtrl.text.trim());
    if (w != null && w > 0) _frameW = w;
    if (h != null && h > 0) _frameH = h;
    dirty = true;
    notifyListeners();
  }

  void applyFramePreset(int w, int h) {
    _frameW = w;
    _frameH = h;
    frameWCtrl.text = '$w';
    frameHCtrl.text = '$h';
    dirty = true;
    notifyListeners();
  }

  void setBgFit(BgFit fit) {
    bgFit = fit;
    dirty = true;
    notifyListeners();
  }

  void setExportJpg(bool v) {
    exportJpg = v;
    notifyListeners();
  }

  void setJpgQuality(int v) {
    jpgQuality = v;
    notifyListeners();
  }

  // ── 프레임 위치/크기(미리보기 드래그·모서리·정렬) ──

  /// 현재 너비/테두리 기준으로 프레임 하단이 캔버스 바닥을 살짝(≈6%) 넘기게
  /// [topFraction]을 다시 계산한다.
  void _alignToBottom() {
    final shot = shotPreview;
    if (shot == null) return;
    final canvasW = _frameW.toDouble();
    final canvasH = _frameH.toDouble();
    final contentW = widthFraction * canvasW;
    final bezel = bezelFraction * contentW;
    final contentH = contentW * shot.height / shot.width;
    final phoneH = contentH + bezel;
    final topPx = (canvasH - phoneH) + phoneH * 0.06;
    topFraction = (topPx / canvasH).clamp(0.0, 1.0);
  }

  void moveFrame(double dxScreen, double dyScreen, double dispW, double dispH) {
    centerXFraction = (centerXFraction + dxScreen / dispW).clamp(-0.5, 1.5);
    topFraction = (topFraction + dyScreen / dispH).clamp(-1.0, 1.5);
    dirty = true;
    notifyListeners();
  }

  void resizeFrame(double dxScreen, bool rightSide, double dispW) {
    final factor = 1 + 2 * (noBezel ? 0.0 : bezelFraction);
    final cyFrac = topFraction + (boxHFrac ?? 0) / 2; // 세로 중심 유지
    var boxWFrac = widthFraction * factor;
    boxWFrac += (rightSide ? 2 : -2) * dxScreen / dispW;
    boxWFrac = boxWFrac.clamp(0.1, 1.6);
    widthFraction = (boxWFrac / factor).clamp(0.05, 1.3);
    topFraction = cyFrac - (boxHFrac ?? 0) / 2;
    dirty = true;
    notifyListeners();
  }

  /// 수평 정렬: 0=왼쪽, 1=중앙, 2=오른쪽.
  void alignH(int which) {
    final bw = boxWFrac;
    centerXFraction = which == 0
        ? bw / 2
        : which == 2
            ? 1 - bw / 2
            : 0.5;
    dirty = true;
    notifyListeners();
  }

  /// 수직 정렬: 0=위, 1=중앙, 2=아래.
  void alignV(int which) {
    final bh = boxHFrac ?? 0.5;
    topFraction = which == 0
        ? 0.0
        : which == 2
            ? (1 - bh)
            : (0.5 - bh / 2);
    dirty = true;
    notifyListeners();
  }

  // ── 내보내기 / 저장 / 불러오기 ──

  /// 현재 프레임 크기로 합성한 바이트를 돌려준다(저장 위치 선택·파일 쓰기는 UI).
  Future<Uint8List> encode({bool? jpg, int? quality}) =>
      StoreShotRenderer.encode(
        canvasW: _frameW,
        canvasH: _frameH,
        backgroundBytes: bgBytes!,
        bgFit: bgFit,
        screenshotBytes: shotBytes,
        objects: [for (final o in objects) (bytes: o.bytes, layout: o.layout)],
        params: params,
        jpg: jpg ?? exportJpg,
        quality: quality ?? jpgQuality,
      );

  /// 내보내기용 바이트를 만든다(busy 표시 포함). 저장 위치 선택·파일 쓰기는
  /// UI가 한다. 배경이 없으면 null.
  Future<Uint8List?> buildExportBytes() async {
    if (bgBytes == null) return null;
    Uint8List? out;
    await _withBusy(() async {
      out = await encode();
    });
    return out;
  }

  /// 프로젝트 문서로 저장(소스 + 레이아웃 + 합성 미리보기).
  Future<void> saveToProject(Directory root) => _withBusy(() async {
        final bytes = bgBytes;
        if (bytes == null) return;
        try {
          final previewPng = await encode(jpg: false);
          sessionDoc = await StoreShotStore.save(
            root: root,
            sessionDoc: sessionDoc,
            backgroundBytes: bytes,
            screenshotBytes: shotBytes,
            objectBytes: [for (final o in objects) o.bytes],
            doc: currentDoc,
            previewPng: previewPng,
          );
          dirty = false;
          setStatus('프로젝트에 저장됨', 'Saved to project');
        } catch (e) {
          emitToast('저장 실패: $e', 'Save failed: $e');
        }
      });

  /// 기존 문서 폴더를 불러와 편집 상태로 복원. 프레임 정보가 없는 옛 문서는
  /// 출력이 그대로 보이도록 프레임을 배경 원본 크기로 마이그레이션한다.
  Future<void> loadDir(Directory dir) async {
    sessionDoc = dir;
    try {
      final load = await StoreShotStore.load(dir);
      final doc = load.doc;
      bgBytes = load.bgBytes;
      bgName = load.bgBytes != null ? 'bg.jpg' : null;
      bgPreview = load.bgPreview;
      shotBytes = load.shotBytes;
      shotName = load.shotBytes != null ? 'shot.jpg' : null;
      shotPreview = load.shotPreview;
      objects
        ..clear()
        ..addAll([
          for (var i = 0; i < load.objBytes.length; i++)
            ShotObject(
              bytes: load.objBytes[i],
              preview: load.objPreviews[i],
              name: 'obj_$i.png',
              layout: i < doc.objects.length
                  ? doc.objects[i]
                  : const ObjectLayout(),
            ),
        ]);
      bgFit = doc.bgFit;
      if (doc.frameW > 0 && doc.frameH > 0) {
        _frameW = doc.frameW;
        _frameH = doc.frameH;
        frameWCtrl.text = '${doc.frameW}';
        frameHCtrl.text = '${doc.frameH}';
      }
      widthFraction = doc.widthFraction;
      topFraction = doc.topFraction;
      centerXFraction = doc.centerXFraction;
      topRadiusFraction = doc.topRadiusFraction;
      bezelFraction = doc.bezelFraction;
      bezelIndex = doc.bezelIndex;
      noBezel = doc.noBezel;
      setStatus('문서를 불러왔습니다', 'Document loaded');
      // 옛 문서: 프레임 = 배경 원본 크기로.
      if ((doc.frameW <= 0 || doc.frameH <= 0) && load.bgBytes != null) {
        final (w, h) = await StoreShotRenderer.decodeSize(load.bgBytes!);
        _frameW = w;
        _frameH = h;
        frameWCtrl.text = '$w';
        frameHCtrl.text = '$h';
      }
      dirty = false; // 갓 불러온 문서는 변경 전까지 깨끗.
      notifyListeners();
    } catch (e) {
      emitToast('불러오기 실패: $e', 'Load failed: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    frameWCtrl.dispose();
    frameHCtrl.dispose();
    super.dispose();
  }
}
