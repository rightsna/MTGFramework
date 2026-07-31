import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 스틸컷(시작·끝 프레임, 인물 참고사진)의 **저장 형식**을 한 곳에서 정한다 — JPEG q95 4:4:4.
///
/// 왜 PNG가 아닌가: 실측(스틸 13장, 704×1280) PNG 대비 **23% 크기에 PSNR 44~46dB** 로
/// 이 화풍(실사·저조도)에선 육안 구분이 안 된다. 프로젝트의 PNG 644장이 815MB였다.
///
/// **4:4:4는 타협하지 않는다.** 기본 4:2:0은 색 해상도를 절반으로 깎는데, 스틸의 일부를 오려
/// 영상 위에 얹는 정지 오버레이(GENERATION.md 〈화면 속 글자·숫자〉)에서 이음매 색이 틀어진다.
///
/// 영상 생성에는 영향이 없다 — 프레임은 바이트로 업로드되고 서버(PIL)가 매직바이트로 형식을
/// 판별하므로 확장자·MIME 라벨과 무관하게 그대로 읽힌다.
const stillJpegQuality = 95;

/// 이미지 바이트를 저장 형식으로 맞춘다 — `(바이트, 확장자)`.
///
/// 디코딩에 실패하면 **원본 바이트를 그대로** 돌려준다(`png`). 형식을 모르는 걸 억지로 다시
/// 굽느니 손대지 않는 게 안전하고, 확장자를 같이 돌려주므로 호출부가 짝을 못 맞출 일은 없다.
///
/// 알파가 있으면 PNG로 남긴다 — JPEG는 투명도를 못 담는다(오브젝트 떼기 산출물 등).
(Uint8List, String) encodeStill(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return (bytes, 'png');
  if (decoded.hasAlpha && _usesAlpha(decoded)) return (bytes, 'png');
  return (
    img.encodeJpg(decoded,
        quality: stillJpegQuality, chroma: img.JpegChroma.yuv444),
    'jpg',
  );
}

/// 알파 채널이 **실제로 쓰이는지** — 채널만 있고 전부 불투명한 경우가 흔해서(생성 PNG 대부분)
/// 채널 유무만 보면 죄다 PNG로 남는다. 투명 픽셀이 하나라도 있으면 true.
bool _usesAlpha(img.Image im) {
  for (final p in im) {
    if (p.a < p.maxChannelValue) return true;
  }
  return false;
}
