import 'clip.dart'; // mediaName / mediaPath (미디어 절대경로 ↔ 파일명)

/// 한 샷(Shot)의 대사. 샷이 0개 또는 1개 소유한다(값 객체 — 자체 id 없음).
///
/// 드라마 제작의 기준은 대본(대사)이다 — 대사를 음성(TTS, 일레븐랩스)으로 만들면
/// 그 길이(voiceSeconds)가 이 샷의 시간을 정하고, 샷의 클립들이 그 시간을 나눠 덮는다.
/// 화자(speakerId)는 Character.id — null이면 내레이션/지문(화자 없는 대사)이다.
/// 음성(mp3)은 프로젝트 폴더 안 파일명(상대)만 저장하고, 런타임엔 절대경로로 다룬다.
class Dialogue {
  String? speakerId; // 화자(Character.id). null = 내레이션/지문
  String text; // 대사(또는 내레이션) 텍스트
  String? voicePath; // 생성된 음성(mp3) 파일 경로(런타임 절대경로). null = 미생성
  double voiceSeconds; // 음성 길이(초) — 이 샷의 길이 기준. 0 = 미생성

  Dialogue({
    this.speakerId,
    this.text = '',
    this.voicePath,
    this.voiceSeconds = 0,
  });

  /// 음성이 만들어졌는지.
  bool get hasVoice => voicePath != null && voiceSeconds > 0;

  Map<String, dynamic> toJson() => {
        'speaker': speakerId, // null 허용(화자 없는 대사)
        'text': text,
        'voice': {
          'file': mediaName(voicePath),
          'seconds': voiceSeconds,
        },
      };

  /// [dir] = 프로젝트 폴더(파일명 → 절대경로 복원 기준).
  factory Dialogue.fromJson(Map<String, dynamic> j, String dir) {
    final voice = (j['voice'] as Map?)?.cast<String, dynamic>();
    return Dialogue(
      speakerId: j['speaker'] as String?,
      text: (j['text'] as String?) ?? '',
      voicePath: mediaPath(dir, voice?['file']),
      voiceSeconds: (voice?['seconds'] as num?)?.toDouble() ?? 0,
    );
  }
}
