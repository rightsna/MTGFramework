import 'package:flutter/material.dart';
import 'package:framework/framework.dart';

import '../../services/api_service.dart';
import '../../services/elevenlabs_service.dart';
import '../../services/movie_settings.dart';
import 'lora_manager.dart';

/// 설정 팝업(전역): Veo 키·옵션 / 자체 서버 / 대사 음성.
/// [MovieSettingsStore]로 직접 로드/저장하므로 어디서든(프로젝트 목록 등) 열 수 있다.
Future<void> showSettingsDialog(BuildContext context) async {
  final store = MovieSettingsStore();
  final initial = await store.load();
  if (!context.mounted) return;
  return showDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(store: store, initial: initial),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.store, required this.initial});
  final MovieSettingsStore store;
  final MovieSettings initial;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late MovieSettings _s = widget.initial;
  late final TextEditingController _geminiCtrl = TextEditingController(
    text: _s.geminiKey,
  );
  late final TextEditingController _civitaiCtrl = TextEditingController(
    text: _s.civitaiToken,
  );
  late final TextEditingController _elevenCtrl = TextEditingController(
    text: _s.elevenKey,
  );
  late final TextEditingController _urlCtrl = TextEditingController(
    text: _s.serviceApiUrl,
  );

  ApiStatus _status = ApiStatus.offline();
  bool _checking = false;

  // 일레븐랩스 보이스(기본/내레이션 보이스 선택용).
  List<ElevenVoice> _voices = [];
  bool _loadingVoices = false;
  String? _voicesError;

  @override
  void initState() {
    super.initState();
    _check();
    if (_elevenCtrl.text.trim().isNotEmpty) _loadVoices();
  }

  /// 현재 입력된 일레븐랩스 키로 보이스 목록을 받아온다.
  Future<void> _loadVoices() async {
    final key = _elevenCtrl.text.trim();
    if (key.isEmpty) {
      setState(() {
        _voices = [];
        _voicesError = '키를 먼저 입력하세요';
      });
      return;
    }
    setState(() {
      _loadingVoices = true;
      _voicesError = null;
    });
    try {
      final voices = await ElevenLabsService(key).listVoices();
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

  /// 입력칸이 비면 고정 도메인, 아니면 입력값. (실제 연결 대상)
  String get _effectiveUrl {
    final t = _urlCtrl.text.trim();
    return t.isEmpty ? kServerDomain : t;
  }

  /// 현재 URL 입력값으로 접속 상태 확인.
  Future<void> _check() async {
    setState(() => _checking = true);
    final s = await ApiService(_effectiveUrl).checkStatus();
    if (!mounted) return;
    setState(() {
      _status = s;
      _checking = false;
    });
  }

  @override
  void dispose() {
    _geminiCtrl.dispose();
    _civitaiCtrl.dispose();
    _elevenCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _save() {
    widget.store.save(
      _s.copyWith(
        geminiKey: _geminiCtrl.text.trim(),
        civitaiToken: _civitaiCtrl.text.trim(),
        elevenKey: _elevenCtrl.text.trim(),
        serviceApiUrl: _urlCtrl.text.trim(),
      ),
    );
    Navigator.of(context).pop();
  }

  /// 일레븐랩스 기본(내레이션) 보이스 선택 — 키로 목록을 받은 뒤 드롭다운.
  Widget _elevenVoicePicker() {
    if (_loadingVoices) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            '보이스 목록 불러오는 중…',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      );
    }
    if (_voicesError != null) {
      return Row(
        children: [
          const Icon(Icons.error_outline, size: 15, color: Colors.orangeAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '보이스 목록 실패: $_voicesError',
              style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
            ),
          ),
          TextButton(onPressed: _loadVoices, child: const Text('다시')),
        ],
      );
    }
    if (_voices.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _elevenCtrl.text.trim().isEmpty ? null : _loadVoices,
          icon: const Icon(Icons.download_outlined, size: 16),
          label: const Text('보이스 목록 불러오기'),
        ),
      );
    }
    final has = _voices.any((v) => v.id == _s.elevenVoiceId);
    return DropdownButtonFormField<String?>(
      initialValue: has ? _s.elevenVoiceId : null,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '기본(내레이션) 보이스',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('없음')),
        for (final v in _voices)
          DropdownMenuItem<String?>(
            value: v.id,
            child: Text(v.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() {
        final match = _voices.where((e) => e.id == v);
        _s = _s.copyWith(
          elevenVoiceId: v ?? '',
          elevenVoiceName: v == null || match.isEmpty ? '' : match.first.name,
        );
      }),
    );
  }

  /// 접속 상태 카드(초록=연결, 빨강=끊김) + 영상 워크플로 설치 여부.
  Widget _statusCard() {
    final s = _status;
    final Color c = s.reachable ? Colors.green : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          if (_checking)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              s.reachable ? Icons.check_circle : Icons.cancel,
              color: c,
              size: 18,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _checking
                  ? '확인 중…'
                  : s.reachable
                  ? (s.videoReady
                        ? '연결됨 · 영상 워크플로 준비됨'
                        : '연결됨 · 영상 워크플로 미설치(video-ltx)')
                  : '연결 안 됨 — URL·서버 상태 확인',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// 좌측 그룹 목록 — 순서 = [_detail]의 인덱스.
  static const _groups = <({IconData icon, String label, String desc})>[
    (
      icon: Icons.auto_awesome_outlined,
      label: '영상 · Veo',
      desc: 'Veo로 생성할 때 쓰는 키와 옵션',
    ),
    (icon: Icons.dns_outlined, label: '자체 서버', desc: '스크린샷·영상 생성 서버 · LoRA'),
    (
      icon: Icons.record_voice_over_outlined,
      label: '대사 음성',
      desc: '일레븐랩스 TTS 키와 기본 보이스',
    ),
  ];

  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final g = _groups[_tab];
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings_outlined, size: 20),
          SizedBox(width: 8),
          Text('설정'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 760,
        height: 480,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 좌: 그룹 목록 ──
            SizedBox(
              width: 190,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _groups.length,
                itemBuilder: (context, i) {
                  final it = _groups[i];
                  final sel = i == _tab;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: sel
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _tab = i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                it.icon,
                                size: 18,
                                color: sel
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white60,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  it.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: sel
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: sel ? null : Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const VerticalDivider(width: 1),
            // ── 우: 선택 그룹 상세 ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      g.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      g.desc,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _detail(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('저장'),
        ),
      ],
    );
  }

  /// 선택된 그룹의 내용. (저장은 그룹과 무관하게 전체 [_s]를 한 번에 저장한다.)
  /// 선택된 그룹의 내용. (저장은 그룹과 무관하게 전체 [_s]를 한 번에 저장한다.)
  Widget _detail() => switch (_tab) {
    0 => _veoSection(),
    1 => _serverSection(),
    _ => _voiceSection(),
  };

  /// 영상 백엔드 자체는 인스펙터의 생성 버튼에서 고른다(Veo로 생성 / 자체 서버로 생성).
  /// 여기엔 Veo 전용 키·옵션만 — 자체 서버 해상도는 인스펙터 영상 탭에 있다.
  Widget _veoSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('Gemini API 키'),
        const SizedBox(height: 2),
        const Text(
          'Veo 영상 생성에 사용',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _geminiCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'AIza...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const _Label('생성 옵션'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: kVeoVideoModels.any((m) => m.id == _s.veoModel)
              ? _s.veoModel
              : kVeoVideoModels.first.id,
          decoration: const InputDecoration(
            labelText: 'Veo 모델',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final m in kVeoVideoModels)
              DropdownMenuItem(value: m.id, child: Text(m.label)),
          ],
          onChanged: (v) => setState(() => _s = _s.copyWith(veoModel: v)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<VideoAspect>(
                initialValue: _s.videoAspect,
                decoration: const InputDecoration(
                  labelText: '비율',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final a in VideoAspect.values)
                    DropdownMenuItem(value: a, child: Text(a.label)),
                ],
                onChanged: (v) =>
                    setState(() => _s = _s.copyWith(videoAspect: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<VideoResolution>(
                initialValue: _s.videoResolution,
                decoration: const InputDecoration(
                  labelText: '해상도',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final r in VideoResolution.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) =>
                    setState(() => _s = _s.copyWith(videoResolution: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _s.videoDurationSeconds,
                decoration: const InputDecoration(
                  labelText: '길이',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 4, child: Text('4초')),
                  DropdownMenuItem(value: 6, child: Text('6초')),
                  DropdownMenuItem(value: 8, child: Text('8초')),
                ],
                onChanged: (v) =>
                    setState(() => _s = _s.copyWith(videoDurationSeconds: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: _s.videoNegativePrompt,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '네거티브 프롬프트 (선택)',
            hintText: '영상에서 피하고 싶은 요소',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _s = _s.copyWith(videoNegativePrompt: v),
        ),
      ],
    );
  }

  Widget _serverSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusCard(),
        const SizedBox(height: 10),
        const _Label('service-api URL'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _urlCtrl,
                onSubmitted: (_) => _check(),
                // 비워두면 실제로 붙는 주소(기본 도메인)를 힌트로 그대로 보여준다 —
                // 빈 칸이 "설정 안 됨"처럼 보이던 오해를 없앤다.
                decoration: InputDecoration(
                  isDense: true,
                  hintText: kServerDomain,
                  helperText: '비우면 이 기본 도메인으로 연결',
                  helperStyle: const TextStyle(
                    fontSize: 11,
                    color: Colors.white38,
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _checking ? null : _check,
              child: const Text('연결 테스트'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '직접 넣으면 그 주소로 연결 — 예: up.sh가 출력한 http://<ip>:8000 '
          '(ngrok을 우회하고 싶을 때).',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 20),
        const _Label('LoRA'),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('LoRA 관리 (서버 용량/삭제)'),
            onPressed: () => showLoraManager(context, _effectiveUrl),
          ),
        ),
        const SizedBox(height: 12),
        // civitai 토큰은 서버가 LoRA를 받을 때 쓴다 — LoRA 옆이 제자리.
        TextField(
          controller: _civitaiCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'civitai 토큰 (선택)',
            helperText: 'civitai LoRA 다운로드용 — civitai URL에 자동 부착',
            helperStyle: TextStyle(fontSize: 11, color: Colors.white38),
            isDense: true,
            hintText: 'civitai API key',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _voiceSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('일레븐랩스 API 키'),
        const SizedBox(height: 2),
        const Text(
          '대사 음성 생성에 사용 · 인물별 보이스는 인물 관리에서 지정',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _elevenCtrl,
          obscureText: true,
          onSubmitted: (_) => _loadVoices(),
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'sk_... (일레븐랩스 API 키)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        const _Label('기본 보이스 (내레이션 · 보이스 없는 화자)'),
        const SizedBox(height: 6),
        _elevenVoicePicker(),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}
