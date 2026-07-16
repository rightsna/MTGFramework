// 스샷 문서 폴더의 preview.jpg를 (재)생성한다.
//
// 스토어 툴 카드는 각 문서 폴더의 preview.jpg를 찾아 목록을 만들기 때문에
// (ProjectAssets.docPreview), bg.jpg + doc.json만 손으로 넣은 폴더는 카드에
// 보이지 않는다. 이 스크립트는 에디터가 저장할 때 쓰는 것과 같은 합성기
// (composeStoreShot)로 preview를 만들어 그 폴더를 정상 문서로 만든다.
//
// 사용법: dart run tool/make_previews.dart <문서폴더> [<문서폴더> …]
//   예)  dart run tool/make_previews.dart ../editor/dist/store/miles2/screenshots/mobile/ko/shot_*

import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:framework/src/store/store_shot/models/store_shot_doc.dart';
import 'package:framework/src/store/store_shot/services/store_shot_composer.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('사용법: dart run tool/make_previews.dart <문서폴더> …');
    exit(64);
  }
  for (final path in args) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      stderr.writeln('건너뜀 (폴더 없음): $path');
      continue;
    }
    final bgFile = File('${dir.path}/bg.jpg');
    if (!bgFile.existsSync()) {
      stderr.writeln('건너뜀 (bg.jpg 없음): $path');
      continue;
    }
    final docFile = File('${dir.path}/doc.json');
    final doc = docFile.existsSync()
        ? StoreShotDoc.fromJson(
            (jsonDecode(docFile.readAsStringSync()) as Map)
                .cast<String, dynamic>())
        : const StoreShotDoc();

    final bg = img.decodeImage(bgFile.readAsBytesSync());
    if (bg == null) {
      stderr.writeln('건너뜀 (bg 디코드 실패): $path');
      continue;
    }
    // 프레임 정보가 없는 옛 문서는 배경 원본 크기로 (로더와 같은 규칙).
    final w = doc.frameW > 0 ? doc.frameW : bg.width;
    final h = doc.frameH > 0 ? doc.frameH : bg.height;

    // shot.jpg가 있으면 폰 프레임까지, 없으면 배경만 합성한다.
    final shotFile = File('${dir.path}/shot.jpg');
    final shot = shotFile.existsSync()
        ? img.decodeImage(shotFile.readAsBytesSync())
        : null;

    final composed = composeStoreShot(
      canvasW: w,
      canvasH: h,
      background: bg,
      bgFit: doc.bgFit,
      screenshot: shot,
      p: doc.toParams(),
    );
    File('${dir.path}/preview.jpg')
        .writeAsBytesSync(img.encodeJpg(composed, quality: 88));
    stdout.writeln(
        'preview.jpg 생성: $path (${w}x$h${shot == null ? ', 배경만' : ', 폰 포함'})');
  }
}
