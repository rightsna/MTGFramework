import 'package:flutter/material.dart';
import 'package:framework/framework.dart';

import '../../services/api_service.dart';
import '../../services/elevenlabs_service.dart';
import '../../services/movie_settings.dart';
import 'lora_manager.dart';

/// 설정 팝업(전역): 스크린샷/영상 생성 백엔드 선택 + 키/URL.
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
  late final TextEditingController _geminiCtrl =
      TextEditingController(text: _s.geminiKey);
  late final TextEditingController _openaiCtrl =
      TextEditingController(text: _s.openaiKey);
  late final TextEditingController _civitaiCtrl =
      TextEditingController(text: _s.civitaiToken);
  late final TextEditingController _elevenCtrl =
      TextEditingController(text: _s.elevenKey);
  late final TextEditingController _urlCtrl =
      TextEditingController(text: _s.serviceApiUrl);

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
    _openaiCtrl.dispose();
    _civitaiCtrl.dispose();
    _elevenCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _save() {
    widget.store.save(_s.copyWith(
      geminiKey: _geminiCtrl.text.trim(),
      openaiKey: _openaiCtrl.text.trim(),
      civitaiToken: _civitaiCtrl.text.trim(),
      elevenKey: _elevenCtrl.text.trim(),
      serviceApiUrl: _urlCtrl.text.trim(),
    ));
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
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('보이스 목록 불러오는 중…',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      );
    }
    if (_voicesError != null) {
      return Row(
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
          border: OutlineInputBorder()),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('없음')),
        for (final v in _voices)
          DropdownMenuItem<String?>(
              value: v.id,
              child: Text(v.name, overflow: TextOverflow.ellipsis)),
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
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(s.reachable ? Icons.check_circle : Icons.cancel, color: c, size: 18),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings_outlined, size: 20),
          SizedBox(width: 8),
          Text('설정'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Label('스크린샷(이미지) 생성'),
              const SizedBox(height: 6),
              DropdownButtonFormField<ImageBackend>(
                initialValue: _s.imageBackend,
                decoration: const InputDecoration(
                    isDense: true, border: OutlineInputBorder()),
                items: [
                  for (final b in ImageBackend.values)
                    DropdownMenuItem(value: b, child: Text(b.label)),
                ],
                onChanged: (v) =>
                    setState(() => _s = _s.copyWith(imageBackend: v)),
              ),
              // 비율 — Gemini/OpenAI 이미지 생성에만 적용(자체 서버는 무시).
              if (_s.imageBackend != ImageBackend.serviceApi) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<AiAspectRatio>(
                  initialValue: _s.imageAspect,
                  decoration: const InputDecoration(
                      labelText: '비율',
                      isDense: true,
                      border: OutlineInputBorder()),
                  items: [
                    for (final a in AiAspectRatio.values)
                      DropdownMenuItem(value: a, child: Text(a.label)),
                  ],
                  onChanged: (v) =>
                      setState(() => _s = _s.copyWith(imageAspect: v)),
                ),
              ],
              const SizedBox(height: 16),
              const _Label('영상 생성'),
              const SizedBox(height: 6),
              DropdownButtonFormField<VideoBackend>(
                initialValue: _s.videoBackend,
                decoration: const InputDecoration(
                    isDense: true, border: OutlineInputBorder()),
                items: [
                  for (final b in VideoBackend.values)
                    DropdownMenuItem(value: b, child: Text(b.label)),
                ],
                onChanged: (v) =>
                    setState(() => _s = _s.copyWith(videoBackend: v)),
              ),
              // Veo 전용 옵션: 모델 / 비율 / 해상도.
              if (_s.videoBackend == VideoBackend.veo) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: kVeoVideoModels.any((m) => m.id == _s.veoModel)
                      ? _s.veoModel
                      : kVeoVideoModels.first.id,
                  decoration: const InputDecoration(
                      labelText: 'Veo 모델',
                      isDense: true,
                      border: OutlineInputBorder()),
                  items: [
                    for (final m in kVeoVideoModels)
                      DropdownMenuItem(value: m.id, child: Text(m.label)),
                  ],
                  onChanged: (v) =>
                      setState(() => _s = _s.copyWith(veoModel: v)),
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
                            border: OutlineInputBorder()),
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
                            border: OutlineInputBorder()),
                        items: [
                          for (final r in VideoResolution.values)
                            DropdownMenuItem(value: r, child: Text(r.label)),
                        ],
                        onChanged: (v) => setState(
                            () => _s = _s.copyWith(videoResolution: v)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _s.videoDurationSeconds,
                        decoration: const InputDecoration(
                            labelText: '길이',
                            isDense: true,
                            border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 4, child: Text('4초')),
                          DropdownMenuItem(value: 6, child: Text('6초')),
                          DropdownMenuItem(value: 8, child: Text('8초')),
                        ],
                        onChanged: (v) => setState(
                            () => _s = _s.copyWith(videoDurationSeconds: v)),
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
                      border: OutlineInputBorder()),
                  onChanged: (v) =>
                      _s = _s.copyWith(videoNegativePrompt: v),
                ),
              ],
              const Divider(height: 28),
              const _Label('Gemini API 키'),
              const SizedBox(height: 2),
              const Text('Gemini 이미지 생성 · Veo 영상 생성에 사용',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 6),
              TextField(
                controller: _geminiCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    isDense: true, hintText: 'AIza...', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const _Label('OpenAI API 키'),
              const SizedBox(height: 6),
              TextField(
                controller: _openaiCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    isDense: true, hintText: 'sk-...', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const _Label('civitai 토큰'),
              const SizedBox(height: 2),
              const Text('civitai LoRA 다운로드용 — civitai URL에 자동 부착',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 6),
              TextField(
                controller: _civitaiCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'civitai API key',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const _Label('일레븐랩스 · 대사 음성(TTS)'),
              const SizedBox(height: 2),
              const Text('대사 음성 생성에 사용 · 인물별 보이스는 인물 관리에서 지정',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 6),
              TextField(
                controller: _elevenCtrl,
                obscureText: true,
                onSubmitted: (_) => _loadVoices(),
                decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'sk_... (일레븐랩스 API 키)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              _elevenVoicePicker(),
              const SizedBox(height: 16),
              const _Label('service-api URL'),
              const SizedBox(height: 6),
              _statusCard(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      onSubmitted: (_) => _check(),
                      decoration: const InputDecoration(
                          isDense: true,
                          hintText: '비우면 기본 도메인 · 직접 넣으면 http://<ip>:8000',
                          border: OutlineInputBorder()),
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
              Text(
                '비우면 기본 도메인($kServerDomain)으로 연결. '
                '직접 넣으면 그 주소(예: up.sh가 출력한 http://<ip>:8000).',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('LoRA 관리 (서버 용량/삭제)'),
                  onPressed: () => showLoraManager(context, _effectiveUrl),
                ),
              ),
            ],
          ),
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
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6));
  }
}
