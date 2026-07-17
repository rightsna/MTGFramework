import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../services/elevenlabs_service.dart';
import '../../services/movie_settings.dart';
import '../../services/storyboard_store.dart';
import '../ui.dart';

/// 인물 관리 전체 화면(푸시 라우트). 왼쪽 인물 목록 + 오른쪽 상세(대표사진·이름·설명·사진 갤러리).
/// 자체 완결형 — 프로젝트 폴더의 characters.json 을 직접 로드/저장한다(스토리보드 provider와 분리).
class CharacterManagerScreen extends StatefulWidget {
  const CharacterManagerScreen({
    super.key,
    required this.projectDirPath,
    required this.projectName,
  });

  final String projectDirPath;
  final String projectName;

  @override
  State<CharacterManagerScreen> createState() => _CharacterManagerScreenState();
}

class _CharacterManagerScreenState extends State<CharacterManagerScreen> {
  late final StoryboardStore _store = StoryboardStore(widget.projectDirPath);
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  List<Character> _chars = [];
  String? _selectedId;
  bool _loading = true;
  int _seq = 0;

  // 일레븐랩스 보이스(인물 목소리 지정용) — 설정의 키로 목록을 받아온다.
  String _elevenKey = '';
  List<ElevenVoice> _voices = [];
  bool _loadingVoices = false;
  String? _voicesError;

  @override
  void initState() {
    super.initState();
    _load();
    _loadVoices();
  }

  /// 설정에서 일레븐랩스 키를 읽어 보이스 목록을 받아온다(키 없으면 건너뜀).
  Future<void> _loadVoices() async {
    final settings = await MovieSettingsStore().load();
    if (!mounted) return;
    _elevenKey = settings.elevenKey.trim();
    if (_elevenKey.isEmpty) return;
    setState(() => _loadingVoices = true);
    try {
      final voices = await ElevenLabsService(_elevenKey).listVoices();
      if (!mounted) return;
      setState(() {
        _voices = voices;
        _loadingVoices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voicesError = '$e';
        _loadingVoices = false;
      });
    }
  }

  void _setVoice(Character c, String? voiceId) {
    setState(() {
      if (voiceId == null) {
        c.voiceId = '';
        c.voiceName = '';
      } else {
        c.voiceId = voiceId;
        final match = _voices.where((v) => v.id == voiceId);
        c.voiceName = match.isEmpty ? c.voiceName : match.first.name;
      }
    });
    _save();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final chars = await _store.loadCharacters();
    if (!mounted) return;
    setState(() {
      _chars = chars;
      _selectedId = chars.isNotEmpty ? chars.first.id : null;
      _loading = false;
    });
    _syncCtrls();
  }

  Character? get _selected {
    for (final c in _chars) {
      if (c.id == _selectedId) return c;
    }
    return null;
  }

  void _syncCtrls() {
    _nameCtrl.text = _selected?.name ?? '';
    _descCtrl.text = _selected?.description ?? '';
  }

  Future<void> _save() => _store.saveCharacters(_chars);

  void _select(String id) {
    if (_selectedId == id) return;
    setState(() => _selectedId = id);
    _syncCtrls();
  }

  void _addCharacter() {
    final id = 'char_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    setState(() {
      _chars.add(Character(id: id, name: '새 인물'));
      _selectedId = id;
    });
    _syncCtrls();
    _save();
  }

  Future<void> _removeCharacter(Character c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("'${c.name.isEmpty ? '이 인물' : c.name}' 삭제"),
        content: const Text('사진과 정보가 삭제됩니다. 되돌릴 수 없어요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    for (final p in [c.coverImagePath, ...c.photoPaths]) {
      if (p != null) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    }
    setState(() {
      _chars.remove(c);
      if (_selectedId == c.id) {
        _selectedId = _chars.isNotEmpty ? _chars.first.id : null;
      }
    });
    _syncCtrls();
    _save();
  }

  void _onNameChanged(String v) {
    final c = _selected;
    if (c == null) return;
    c.name = v;
    setState(() {}); // 좌측 목록 라벨 즉시 반영
    _save();
  }

  void _onDescChanged(String v) {
    final c = _selected;
    if (c == null) return;
    c.description = v;
    _save();
  }

  Future<void> _addPhotos() async {
    final c = _selected;
    if (c == null) return;
    const group = fs.XTypeGroup(
        label: 'images', extensions: ['png', 'jpg', 'jpeg', 'webp']);
    final files = await fs.openFiles(acceptedTypeGroups: [group]);
    if (files.isEmpty) return;
    for (final xf in files) {
      final ext = xf.name.contains('.')
          ? xf.name.split('.').last.toLowerCase()
          : 'png';
      final dest = File(
          '${widget.projectDirPath}/${c.id}_${DateTime.now().millisecondsSinceEpoch}_${_seq++}.$ext');
      await dest.writeAsBytes(await xf.readAsBytes());
      await FileImage(dest).evict();
      c.photoPaths.add(dest.path);
      c.coverImagePath ??= dest.path; // 첫 사진을 대표로
    }
    setState(() {});
    _save();
  }

  Future<void> _removePhoto(Character c, String path) async {
    setState(() {
      c.photoPaths.remove(path);
      if (c.coverImagePath == path) {
        c.coverImagePath =
            c.photoPaths.isNotEmpty ? c.photoPaths.first : null;
      }
    });
    try {
      await File(path).delete();
    } catch (_) {}
    _save();
  }

  void _setCover(Character c, String path) {
    setState(() => c.coverImagePath = path);
    _save();
  }

  /// 목소리(대사 TTS) 지정 섹션 — 키 상태에 따라 목록/안내/에러를 보여준다.
  Widget _buildVoiceSection(Character c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.record_voice_over_outlined,
                size: 16, color: accent2),
            const SizedBox(width: 6),
            const _Label('목소리 · 대사 TTS'),
            const SizedBox(width: 8),
            if (c.hasVoice)
              Text(c.voiceName.isEmpty ? '지정됨' : c.voiceName,
                  style: const TextStyle(fontSize: 12, color: accent2)),
          ],
        ),
        const SizedBox(height: 8),
        if (_elevenKey.isEmpty)
          const Text('설정에서 일레븐랩스 API 키를 넣으면 목소리를 고를 수 있어요',
              style: TextStyle(fontSize: 12, color: Colors.white38))
        else if (_loadingVoices)
          const Row(
            children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('보이스 목록 불러오는 중…',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          )
        else if (_voicesError != null)
          Row(
            children: [
              const Icon(Icons.error_outline, size: 15, color: Colors.orangeAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text('보이스 목록 실패: $_voicesError',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.orangeAccent)),
              ),
              TextButton(onPressed: _loadVoices, child: const Text('다시')),
            ],
          )
        else
          _voiceDropdown(c),
        const SizedBox(height: 4),
        const Text('이 인물의 대사는 여기서 고른 목소리로 생성됩니다 · 미지정 시 설정의 기본 보이스',
            style: TextStyle(fontSize: 11, color: Colors.white38)),
      ],
    );
  }

  Widget _voiceDropdown(Character c) {
    final ids = _voices.map((v) => v.id).toSet();
    // 현재 보이스가 목록에 없으면(다른 계정 등) 임시 항목으로 보존한다.
    final missingCurrent = c.voiceId.isNotEmpty && !ids.contains(c.voiceId);
    return DropdownButtonFormField<String?>(
      initialValue: c.voiceId.isEmpty ? null : c.voiceId,
      isExpanded: true,
      decoration: const InputDecoration(
          isDense: true, border: OutlineInputBorder()),
      items: [
        const DropdownMenuItem<String?>(
            value: null, child: Text('목소리 없음 (기본 보이스 사용)')),
        if (missingCurrent)
          DropdownMenuItem<String?>(
            value: c.voiceId,
            child: Text(
                '${c.voiceName.isEmpty ? c.voiceId : c.voiceName} (목록에 없음)',
                overflow: TextOverflow.ellipsis),
          ),
        for (final v in _voices)
          DropdownMenuItem<String?>(
            value: v.id,
            child: Text(
                '${v.name}${v.category != null ? '  · ${v.category}' : ''}',
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => _setVoice(c, v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_alt_outlined, size: 20),
            const SizedBox(width: 8),
            Text('인물 관리 · ${widget.projectName}'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 260, child: _buildList()),
                Container(width: 1, color: const Color(0x22FFFFFF)),
                Expanded(child: _buildDetail()),
              ],
            ),
    );
  }

  Widget _buildList() {
    return Container(
      color: panelBg,
      child: Column(
        children: [
          Expanded(
            child: _chars.isEmpty
                ? const Center(
                    child: Text('아직 인물이 없습니다',
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _chars.length,
                    itemBuilder: (_, i) => _CharTile(
                      character: _chars[i],
                      selected: _chars[i].id == _selectedId,
                      onTap: () => _select(_chars[i].id),
                    ),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _addCharacter,
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('인물 추가'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetail() {
    final c = _selected;
    if (c == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, color: Colors.white24, size: 44),
            SizedBox(height: 10),
            Text('왼쪽에서 인물을 선택하거나 추가하세요',
                style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 대표사진 + 이름/설명.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverImage(path: c.cover),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Label('이름'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                      onChanged: _onNameChanged,
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: previewBg,
                        border: OutlineInputBorder(),
                        hintText: '인물 이름',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _Label('설명'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _descCtrl,
                      minLines: 4,
                      maxLines: 10,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                      onChanged: _onDescChanged,
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: previewBg,
                        border: OutlineInputBorder(),
                        hintText: '외형·성격·역할 등 (샷 생성 레퍼런스로 활용)',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 목소리(대사 TTS) — 인물의 정체성: 얼굴 + 목소리.
          _buildVoiceSection(c),
          const SizedBox(height: 28),
          // 사진 갤러리.
          Row(
            children: [
              const _Label('사진'),
              const SizedBox(width: 8),
              Text('${c.photoPaths.length}장 · 탭하면 대표로 지정',
                  style: const TextStyle(fontSize: 12, color: Colors.white38)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _removeCharacter(c),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('인물 삭제'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in c.photoPaths)
                _PhotoThumb(
                  path: p,
                  isCover: p == c.cover,
                  onSetCover: () => _setCover(c, p),
                  onDelete: () => _removePhoto(c, p),
                ),
              _AddPhotoTile(onTap: _addPhotos),
            ],
          ),
        ],
      ),
    );
  }
}

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
