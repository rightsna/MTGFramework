import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:framework/framework.dart';

/// 탭들이 공유하는 소스-이미지 액션(파일 선택 / 이미지 에디터). 컨트롤러는
/// context가 없어 못 하는 BuildContext 의존 단계를 여기 모아 두고, 각 탭이 결과
/// 바이트를 컨트롤러로 넘긴다.
const XTypeGroup kImageTypes = XTypeGroup(
  label: 'images',
  extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'tif', 'tiff'],
);

/// 파일 선택 → (바이트, 이름). 취소 시 null.
Future<({Uint8List bytes, String name})?> pickImageFile() async {
  final xf = await openFile(acceptedTypeGroups: const [kImageTypes]);
  if (xf == null) return null;
  return (bytes: await xf.readAsBytes(), name: xf.name);
}

/// 이미지 에디터 다이얼로그로 [bytes]를 편집. 취소 시 null.
Future<Uint8List?> editImage(
        BuildContext context, Uint8List bytes, String title) =>
    showImageEditDialog(context, pngBytes: bytes, title: title);

/// 확장자를 뗀 파일명(내보내기 기본 이름용).
String baseName(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot > 0 ? filename.substring(0, dot) : filename;
}
