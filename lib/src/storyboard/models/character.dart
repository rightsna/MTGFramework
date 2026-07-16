import 'clip.dart'; // mediaName / mediaPath (미디어 절대경로 ↔ 파일명)

/// 프로젝트의 등장인물 한 명. 인물은 **얼굴 + 목소리**의 정체성이다.
///  - 얼굴: 대표사진 + 여러 사진(갤러리) — 장면 생성 시 이미지 레퍼런스(FireRed)로 외형 유지
///  - 목소리: [voiceId] — 대사(TTS) 생성 시 이 인물의 음성을 항상 같게 (일레븐랩스 voice id)
/// 이름/설명 + 미디어는 프로젝트 폴더 안 파일명(상대)만 저장.
class Character {
  String id;
  String name;
  String description;
  String? coverImagePath; // 대표사진(런타임 절대경로). 없으면 첫 사진을 대표로.
  List<String> photoPaths; // 여러 사진(런타임 절대경로)
  String voiceId; // 대사 음성용 보이스 id(일레븐랩스 등). 비면 미지정.
  String voiceName; // 사람이 읽는 보이스 이름(라벨)

  Character({
    required this.id,
    this.name = '',
    this.description = '',
    this.coverImagePath,
    List<String>? photoPaths,
    this.voiceId = '',
    this.voiceName = '',
  }) : photoPaths = photoPaths ?? [];

  /// 실제 표시할 대표사진: 지정 대표 → 없으면 첫 사진 → 없으면 null.
  String? get cover =>
      coverImagePath ?? (photoPaths.isNotEmpty ? photoPaths.first : null);

  /// 대사 음성을 만들 수 있는지(보이스가 지정됐는지).
  bool get hasVoice => voiceId.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'cover': mediaName(coverImagePath),
        'photos': photoPaths.map(mediaName).whereType<String>().toList(),
        'voiceId': voiceId,
        'voiceName': voiceName,
      };

  /// [dir] = 프로젝트 폴더(파일명 → 절대경로 복원 기준).
  factory Character.fromJson(Map<String, dynamic> j, String dir) => Character(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        coverImagePath: mediaPath(dir, j['cover']),
        photoPaths: ((j['photos'] as List?) ?? const [])
            .map((e) => mediaPath(dir, e))
            .whereType<String>()
            .toList(),
        voiceId: (j['voiceId'] as String?) ?? '',
        voiceName: (j['voiceName'] as String?) ?? '',
      );
}
