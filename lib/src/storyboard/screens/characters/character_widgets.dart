part of 'character_manager_screen.dart';

/// 캐릭터 관리 화면의 정적 위젯 — 목록 타일·대표사진·참고사진 썸네일·사진 추가·라벨.

/// 좌측 목록의 인물 한 줄(대표사진 썸네일 + 이름).
class _CharTile extends StatelessWidget {
  const _CharTile({
    required this.character,
    required this.selected,
    required this.onTap,
  });

  final Character character;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = character.cover;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? const Color(0x223B82F6) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: previewBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: selected ? accent2 : const Color(0x22FFFFFF)),
              ),
              clipBehavior: Clip.antiAlias,
              child: cover != null
                  ? Image.file(File(cover),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.person, size: 20, color: Colors.white24))
                  : const Icon(Icons.person, size: 20, color: Colors.white24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                character.name.isEmpty ? '(이름 없음)' : character.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 상세 상단의 대표사진(큰 이미지).
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: previewBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: path != null ? const Color(0x335BD1C0) : const Color(0x22FFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: path != null
          ? Image.file(File(path!),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const _CoverPlaceholder())
          : const _CoverPlaceholder(),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();
  @override
  Widget build(BuildContext context) => const Center(
      child: Icon(Icons.image_outlined, color: Colors.white24, size: 40));
}

/// 갤러리 사진 한 장(탭=대표 지정, x=삭제, 대표엔 배지).
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.path,
    required this.isCover,
    required this.onSetCover,
    required this.onDelete,
  });

  final String path;
  final bool isCover;
  final VoidCallback onSetCover;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: onSetCover,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isCover ? accent2 : const Color(0x22FFFFFF),
                    width: isCover ? 2 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(File(path),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined)),
            ),
          ),
          if (isCover)
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: accent2, borderRadius: BorderRadius.circular(4)),
                child: const Text('대표',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87)),
              ),
            ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: Color(0xCC000000), shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 사진 추가 타일.
class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, color: Colors.white54),
            SizedBox(height: 4),
            Text('사진 추가', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: accent2));
}
