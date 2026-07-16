import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/store_shot_doc.dart';
import 'store_shot_renderer.dart';

/// 디스크에서 읽은 스샷 문서: 소스 바이트(원본) + 미리보기용 축소본 + 레이아웃.
class StoreShotLoad {
  const StoreShotLoad({
    required this.doc,
    this.bgBytes,
    this.shotBytes,
    this.bgPreview,
    this.shotPreview,
    this.objBytes = const [],
    this.objPreviews = const [],
  });

  final StoreShotDoc doc;
  final Uint8List? bgBytes;
  final Uint8List? shotBytes;
  final img.Image? bgPreview;
  final img.Image? shotPreview;

  /// 오브젝트 이미지(원본 바이트 + 미리보기 축소본), [StoreShotDoc.objects]와 같은 순서.
  final List<Uint8List> objBytes;
  final List<img.Image> objPreviews;
}

/// 스샷 문서의 파일 저장/불러오기 담당. 한 문서 = `screenshots/<id>/` 폴더로,
/// 소스(bg/shot.jpg + obj_0.png…) + 레이아웃(doc.json) + 합성 미리보기(preview.jpg).
///
/// 배경·스샷·미리보기는 용량을 위해 **JPG**로 저장한다(불투명 레이어라 알파 불필요).
/// 오브젝트(obj_N.png)는 알파를 보존해야 하므로 PNG 유지. 이전에 PNG로 저장된
/// 문서도 읽을 수 있도록 로드는 `.jpg` → `.png` 순으로 찾는다.
class StoreShotStore {
  const StoreShotStore._();

  static const _bgMaxSide = 1000;
  static const _shotMaxSide = 1400;
  static const _objMaxSide = 1000;
  static const _jpgQuality = 88;

  /// 기존 문서 폴더를 읽어 소스/축소본/레이아웃을 복원한다. 축소본 디코드는
  /// [StoreShotRenderer.decodeDownscaled]로 오프스레드에서 처리.
  static Future<StoreShotLoad> load(Directory dir) async {
    var doc = const StoreShotDoc();
    final docFile = File('${dir.path}/doc.json');
    if (await docFile.exists()) {
      doc = StoreShotDoc.fromJson(
          (jsonDecode(await docFile.readAsString()) as Map)
              .cast<String, dynamic>());
    }

    final (bg, bgP) = await _readSource(_srcPath(dir, 'bg'), _bgMaxSide);
    final (shot, shotP) = await _readSource(_srcPath(dir, 'shot'), _shotMaxSide);

    // 오브젝트 이미지(obj_0.png …)를 doc.objects 순서대로 읽는다.
    final objBytes = <Uint8List>[];
    final objPreviews = <img.Image>[];
    for (var i = 0; i < doc.objects.length; i++) {
      final (b, p) = await _readSource('${dir.path}/obj_$i.png', _objMaxSide);
      if (b != null && p != null) {
        objBytes.add(b);
        objPreviews.add(p);
      }
    }

    return StoreShotLoad(
      doc: doc,
      bgBytes: bg,
      shotBytes: shot,
      bgPreview: bgP,
      shotPreview: shotP,
      objBytes: objBytes,
      objPreviews: objPreviews,
    );
  }

  /// 문서를 저장하고 사용한 문서 폴더를 돌려준다. [sessionDoc]이 있으면 그 폴더를
  /// 갱신하고, 없으면 [root] 아래에 새 `shot_N` 폴더를 만든다(같은 세션 재저장이
  /// 같은 문서를 갱신하도록 호출부가 반환값을 보관한다). [previewPng]는 호출부가
  /// [StoreShotRenderer.encode]로 미리 합성해 넘긴다.
  static Future<Directory> save({
    required Directory root,
    Directory? sessionDoc,
    required Uint8List backgroundBytes,
    Uint8List? screenshotBytes,
    List<Uint8List> objectBytes = const [],
    required StoreShotDoc doc,
    required Uint8List previewPng,
  }) async {
    final dir = sessionDoc ?? Directory('${root.path}/${await _uniqueId(root)}');
    if (!await dir.exists()) await dir.create(recursive: true);

    // 배경/스샷/미리보기는 JPG로 저장(용량↓). 옛 .png 소스가 있으면 지운다.
    await File('${dir.path}/bg.jpg').writeAsBytes(await _toJpg(backgroundBytes));
    await _deleteIfExists('${dir.path}/bg.png');
    await _writeJpgOrDelete('${dir.path}/shot.jpg', screenshotBytes);
    if (screenshotBytes != null) await _deleteIfExists('${dir.path}/shot.png');
    // 오브젝트 이미지: 알파 보존을 위해 obj_0.png … 로 (PNG 그대로) 쓰고, 줄어든
    // 만큼 남은 옛 파일은 지운다.
    for (var i = 0; i < objectBytes.length; i++) {
      await File('${dir.path}/obj_$i.png').writeAsBytes(objectBytes[i]);
    }
    for (var i = objectBytes.length;; i++) {
      final f = File('${dir.path}/obj_$i.png');
      if (!await f.exists()) break;
      await f.delete();
    }
    await File('${dir.path}/doc.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(doc.toJson()));
    await File('${dir.path}/preview.jpg').writeAsBytes(await _toJpg(previewPng));
    await _deleteIfExists('${dir.path}/preview.png');
    return dir;
  }

  /// Existing source path for [base] ("bg"/"shot"), preferring `.jpg` over a
  /// legacy `.png`. Returns the `.jpg` path even if neither exists (load treats
  /// a missing file as absent).
  static String _srcPath(Directory dir, String base) {
    final png = File('${dir.path}/$base.png');
    if (png.existsSync() && !File('${dir.path}/$base.jpg').existsSync()) {
      return png.path;
    }
    return '${dir.path}/$base.jpg';
  }

  /// Decode [bytes] (any format) and re-encode as JPG. Falls back to the raw
  /// bytes if decode fails (shouldn't for a valid picked image).
  static Future<Uint8List> _toJpg(Uint8List bytes) => Future(() {
        final im = img.decodeImage(bytes);
        if (im == null) return bytes;
        return Uint8List.fromList(img.encodeJpg(im, quality: _jpgQuality));
      });

  static Future<(Uint8List?, img.Image?)> _readSource(
      String path, int maxSide) async {
    final f = File(path);
    if (!await f.exists()) return (null, null);
    final bytes = await f.readAsBytes();
    final preview = await StoreShotRenderer.decodeDownscaled(bytes, maxSide);
    return (bytes, preview);
  }

  static Future<void> _writeJpgOrDelete(String path, Uint8List? bytes) async {
    final f = File(path);
    if (bytes != null) {
      await f.writeAsBytes(await _toJpg(bytes));
    } else if (await f.exists()) {
      await f.delete();
    }
  }

  static Future<void> _deleteIfExists(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  static Future<String> _uniqueId(Directory root) async {
    for (var i = 1;; i++) {
      final id = 'shot_$i';
      if (!await Directory('${root.path}/$id').exists()) return id;
    }
  }
}
