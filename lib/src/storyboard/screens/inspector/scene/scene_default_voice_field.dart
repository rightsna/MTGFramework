part of '../inspector_panel.dart';

/// 씬 기본 성우 선택 — 일레븐랩스 보이스 목록에서 하나 고른다(내레이션·화자 미지정용).
/// 인물 관리의 보이스 드롭다운과 같은 방식(설정의 키로 목록을 받아온다).
class _SceneDefaultVoiceField extends StatefulWidget {
  const _SceneDefaultVoiceField({required super.key});

  @override
  State<_SceneDefaultVoiceField> createState() =>
      _SceneDefaultVoiceFieldState();
}

class _SceneDefaultVoiceFieldState extends State<_SceneDefaultVoiceField> {
  List<ElevenVoice> _voices = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    final key = StoryboardScope.read(context).settings.elevenKey.trim();
    if (key.isEmpty) return;
    setState(() => _loading = true);
    try {
      final voices = await ElevenLabsService(key).listVoices();
      if (!mounted) return;
      setState(() {
        _voices = voices;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = StoryboardScope.of(context);
    final sc = p.selectedScene;
    final currentId = sc?.defaultVoiceId.trim() ?? '';

    if (p.settings.elevenKey.trim().isEmpty) {
      return const Text('설정에서 일레븐랩스 키를 넣어야 성우를 고를 수 있어요',
          style: TextStyle(fontSize: 12, color: Colors.orangeAccent));
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Row(
        children: [
          Expanded(
            child: Text('보이스 목록 실패: $_error',
                style:
                    const TextStyle(fontSize: 12, color: Colors.redAccent)),
          ),
          TextButton(onPressed: _loadVoices, child: const Text('다시 시도')),
        ],
      );
    }

    final ids = _voices.map((v) => v.id).toSet();
    // 저장된 성우가 목록에 없으면(다른 계정 등) 항목을 하나 끼워 값이 유지되게.
    final missingCurrent = currentId.isNotEmpty && !ids.contains(currentId);

    return DropdownButtonFormField<String?>(
      initialValue: currentId.isEmpty ? null : currentId,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('없음 (내레이션 음성 생성 안 함)'),
        ),
        if (missingCurrent)
          DropdownMenuItem<String?>(
            value: currentId,
            child: Text(
              '${sc!.defaultVoiceName.isEmpty ? currentId : sc.defaultVoiceName} (목록에 없음)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        for (final v in _voices)
          DropdownMenuItem<String?>(
            value: v.id,
            child: Text(
              '${v.name}${v.category == null ? '' : '  · ${v.category}'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (id) {
        if (id == null) {
          p.setSceneDefaultVoice('', '');
        } else {
          final match = _voices.where((v) => v.id == id);
          p.setSceneDefaultVoice(id, match.isEmpty ? '' : match.first.name);
        }
      },
    );
  }
}
