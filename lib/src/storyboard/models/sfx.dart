import 'shot.dart'; // mediaName / mediaPath (미디어 절대경로 ↔ 파일명)

/// 한 비트(DialogueBeat)의 효과음(SFX). 대사처럼 비트에 0개 또는 1개 붙는다(값 객체 — 자체 id 없음).
///
/// 대사와 달리 **화자가 없다** — 일레븐랩스 sound-generation으로 소리 묘사([prompt])를 그대로
/// 음향으로 만든다. [durationSeconds]로 길이를, [promptInfluence]로 프롬프트 충실도를 정한다.
/// 효과음은 백엔드와 무관하므로 **트랙끼리 공유**한다(기준 비트 하나에만 둔다).
/// 소리(mp3)는 프로젝트 폴더 안 파일명(상대)만 저장하고, 런타임엔 절대경로로 다룬다.
class Sfx {
  String prompt; // 소리 묘사(text) — 예: "deep cinematic impact boom, sub-bass"
  double durationSeconds; // 길이(초, 0.5~22). 일레븐랩스에 그대로 넘긴다
  double promptInfluence; // 0~1 — 높을수록 프롬프트에 충실(기본 0.3)
  String? path; // 생성된 효과음(mp3) 파일 경로(런타임 절대경로). null = 미생성
  double soundSeconds; // 실측 길이(초). 0 = 미생성

  Sfx({
    this.prompt = '',
    this.durationSeconds = 2.0,
    this.promptInfluence = 0.3,
    this.path,
    this.soundSeconds = 0,
  });

  /// 효과음이 만들어졌는지.
  bool get hasSound => path != null && soundSeconds > 0;

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'durationSeconds': durationSeconds,
        'promptInfluence': promptInfluence,
        'sound': {
          'file': mediaName(path),
          'seconds': soundSeconds,
        },
      };

  /// [dir] = 프로젝트 폴더(파일명 → 절대경로 복원 기준).
  factory Sfx.fromJson(Map<String, dynamic> j, String dir) {
    final sound = (j['sound'] as Map?)?.cast<String, dynamic>();
    return Sfx(
      prompt: (j['prompt'] as String?) ?? '',
      durationSeconds: (j['durationSeconds'] as num?)?.toDouble() ?? 2.0,
      promptInfluence: (j['promptInfluence'] as num?)?.toDouble() ?? 0.3,
      path: mediaPath(dir, sound?['file']),
      soundSeconds: (sound?['seconds'] as num?)?.toDouble() ?? 0,
    );
  }
}
