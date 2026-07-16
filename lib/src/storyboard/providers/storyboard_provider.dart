import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:framework/framework.dart';

import '../models/character.dart';
import '../models/clip.dart';
import '../models/dialogue.dart';
import '../models/shot.dart';
import '../models/story_scene.dart';
import '../services/api_service.dart';
import '../services/elevenlabs_service.dart';
import '../services/movie_settings.dart';
import '../services/storyboard_store.dart';

/// 스토리보드 화면 전체가 공유하는 상태/로직 홀더.
/// 구조: 스토리보드 → 씬(StoryScene) → 샷(Shot: 대사 1개? + 클립 여러 개) → 클립(VideoClip).
/// 좌측 씬 목록·캔버스(선택 씬의 샷/클립)·인스펙터·플레이어·설정이 [StoryboardScope]로 구독한다.
class StoryboardProvider extends ChangeNotifier {
  StoryboardProvider({required this.projectDirPath}) {
    _store = StoryboardStore(projectDirPath);
    _load();
  }

  /// 이 프로젝트의 폴더(scene*.json + 미디어가 여기 저장된다).
  final String projectDirPath;

  late final StoryboardStore _store;
  final _settingsStore = MovieSettingsStore();

  MovieSettings _settings = const MovieSettings();
  String _projectCommonPrompt = ''; // 프로젝트 공통 프롬프트(모든 생성에 붙음)
  List<Character> _characters = []; // 프로젝트 등장인물(인물 참조 피커/생성용)

  // 컨트롤러: 씬 제목(씬 id) · 샷 제목/메모(샷 id) · 클립 프롬프트(클립 id).
  final Map<String, TextEditingController> _sceneTitles = {};
  final Map<String, TextEditingController> _shotTitles = {};
  final Map<String, TextEditingController> _notes = {};
  final Map<String, TextEditingController> _startPrompts = {};
  final Map<String, TextEditingController> _endPrompts = {};
  final Map<String, TextEditingController> _vprompts = {};
  final Set<String> _busy = {}; // '<clipId>:<mode>' 또는 '<shotId>:voice' 등 진행 중
  final Map<String, int> _ver = {}; // 미리보기 캐시 버전

  List<StoryScene> _scenes = []; // 씬 리스트
  String? _selectedSceneId;
  String? _selectedShotId; // 선택된 샷(비트)
  String? _selectedClipId; // 선택된 클립(선택 샷 안에서)
  int _seq = 0;
  String? _savePath;

  // 사이드/플레이어 토글. 씬목록은 기본으로 펼쳐둔다(씬 이동이 주 동선).
  bool _sceneListOpen = true;
  bool _playerOpen = false;

  // service-api 접속 상태(주기적으로 갱신).
  ApiStatus _apiStatus = ApiStatus.offline();
  Timer? _statusTimer;

  // 디스크 설정 로드 완료 여부(인스펙터 탭 복원 타이밍용).
  bool _settingsLoaded = false;
  bool get settingsLoaded => _settingsLoaded;

  /// 토스트/스낵바 출력 통로(화면이 주입).
  void Function(String message)? messenger;

  // ───────── 읽기 접근자 ─────────

  List<StoryScene> get scenes => _scenes;
  MovieSettings get settings => _settings;
  String get projectCommonPrompt => _projectCommonPrompt;
  List<Character> get characters => _characters;
  String? get selectedSceneId => _selectedSceneId;
  String? get selectedShotId => _selectedShotId;
  String? get selectedClipId => _selectedClipId;
  String? get savePath => _savePath;
  bool get sceneListOpen => _sceneListOpen;
  bool get playerOpen => _playerOpen;
  ApiStatus get apiStatus => _apiStatus;

  // ───────── 백엔드별 생성 준비 상태(버튼 활성/비활성 판단) ─────────

  /// 이미지(시작/끝장면) 생성 가능 여부 — 선택된 이미지 백엔드 기준.
  bool get imageReady => switch (_settings.imageBackend) {
        ImageBackend.serviceApi => _apiStatus.reachable,
        ImageBackend.gemini => _settings.geminiKey.trim().isNotEmpty,
        ImageBackend.openai => _settings.openaiKey.trim().isNotEmpty,
      };

  String? get imageBlockReason => imageReady
      ? null
      : switch (_settings.imageBackend) {
          ImageBackend.serviceApi => '서버에 연결되지 않았습니다 (상단·설정에서 확인)',
          ImageBackend.gemini => 'Gemini API 키가 없습니다 (설정)',
          ImageBackend.openai => 'OpenAI API 키가 없습니다 (설정)',
        };

  /// 영상 생성 가능 여부 — 선택된 영상 백엔드 기준.
  bool get videoReady => switch (_settings.videoBackend) {
        VideoBackend.serviceApi =>
          _apiStatus.reachable && _apiStatus.videoReady,
        VideoBackend.veo => _settings.geminiKey.trim().isNotEmpty,
      };

  String? get videoBlockReason => videoReady
      ? null
      : switch (_settings.videoBackend) {
          VideoBackend.serviceApi => _apiStatus.reachable
              ? '영상 워크플로(video-ltx)가 서버에 없습니다'
              : '서버에 연결되지 않았습니다 (상단·설정에서 확인)',
          VideoBackend.veo => 'Veo용 Gemini API 키가 없습니다 (설정)',
        };

  /// 배경음(ACE-Step)도 자체 서버 전용.
  bool get bgmReady => _apiStatus.reachable && _apiStatus.audioReady;
  String? get bgmBlockReason => bgmReady
      ? null
      : _apiStatus.reachable
          ? '배경음 워크플로(bgm)가 서버에 없습니다'
          : '서버에 연결되지 않았습니다 (상단·설정에서 확인)';

  /// 대사 음성(일레븐랩스 TTS)은 외부 API — 키만 있으면 가능(서버 연결과 무관).
  bool get voiceReady => _settings.elevenKey.trim().isNotEmpty;
  String? get voiceBlockReason =>
      voiceReady ? null : '일레븐랩스 API 키가 없습니다 (설정)';

  StoryScene? get selectedScene {
    for (final s in _scenes) {
      if (s.id == _selectedSceneId) return s;
    }
    return null;
  }

  /// 현재 선택 씬의 샷들(캔버스가 타임라인으로 그리는 대상).
  List<Shot> get shots => selectedScene?.shots ?? const [];

  Shot? get selectedShot {
    for (final s in shots) {
      if (s.id == _selectedShotId) return s;
    }
    return null;
  }

  /// 선택 샷 안의 클립들.
  List<VideoClip> get clips => selectedShot?.clips ?? const [];

  /// 선택 씬의 모든 클립(샷 순서 → 클립 순서로 평탄화). 미리보기·연속 재생용.
  List<VideoClip> get sceneClips => [for (final sh in shots) ...sh.clips];

  VideoClip? get selectedClip {
    for (final c in clips) {
      if (c.id == _selectedClipId) return c;
    }
    return null;
  }

  TextEditingController sceneTitleCtrl(String sceneId) => _sceneTitles[sceneId]!;
  TextEditingController titleCtrl(String shotId) => _shotTitles[shotId]!;
  TextEditingController noteCtrl(String shotId) => _notes[shotId]!;
  TextEditingController startCtrl(String clipId) => _startPrompts[clipId]!;
  TextEditingController endCtrl(String clipId) => _endPrompts[clipId]!;
  TextEditingController videoCtrl(String clipId) => _vprompts[clipId]!;

  bool isBusy(String key) => _busy.contains(key);
  int verOf(String key) => _ver[key] ?? 0;
  String busyKey(String id, GenMode m) => '$id:${m.name}';

  String? videoPathOf(VideoClip c) => c.videoPath;

  // ───────── 로드/저장 ─────────

  Future<void> _load() async {
    _settings = await _settingsStore.load();
    _settingsLoaded = true;
    final scenes = await _store.load();
    final path = _store.path();
    _scenes = scenes;
    _projectCommonPrompt = await _store.loadCommonPrompt();
    _characters = await _store.loadCharacters();
    for (final scene in scenes) {
      _sceneTitles[scene.id] = TextEditingController(text: scene.title);
      for (final shot in scene.shots) {
        _addShotControllers(shot);
        for (final clip in shot.clips) {
          _addClipControllers(clip);
        }
      }
    }
    final firstScene = scenes.isNotEmpty ? scenes.first : null;
    final firstShot =
        (firstScene != null && firstScene.shots.isNotEmpty) ? firstScene.shots.first : null;
    _selectedSceneId = firstScene?.id;
    _selectedShotId = firstShot?.id;
    _selectedClipId =
        (firstShot != null && firstShot.clips.isNotEmpty) ? firstShot.clips.first.id : null;
    _savePath = path;
    notifyListeners();
    checkConnection();
    _statusTimer ??= Timer.periodic(
        const Duration(seconds: 15), (_) => checkConnection());
  }

  Future<void> checkConnection() async {
    final s = await ApiService(_settings.effectiveServiceUrl).checkStatus();
    _apiStatus = s;
    notifyListeners();
  }

  Future<void> reloadSettings() async {
    _settings = await _settingsStore.load();
    notifyListeners();
    await checkConnection();
  }

  void _addShotControllers(Shot shot) {
    _shotTitles[shot.id] = TextEditingController(text: shot.title);
    _notes[shot.id] = TextEditingController(text: shot.note);
  }

  void _disposeShotControllers(String shotId) {
    _shotTitles.remove(shotId)?.dispose();
    _notes.remove(shotId)?.dispose();
  }

  void _addClipControllers(VideoClip clip) {
    _startPrompts[clip.id] = TextEditingController(text: clip.startPrompt);
    _endPrompts[clip.id] = TextEditingController(text: clip.endPrompt);
    _vprompts[clip.id] = TextEditingController(text: clip.videoPrompt);
  }

  void _disposeClipControllers(String clipId) {
    _startPrompts.remove(clipId)?.dispose();
    _endPrompts.remove(clipId)?.dispose();
    _vprompts.remove(clipId)?.dispose();
  }

  Future<void> save() async {
    for (final scene in _scenes) {
      scene.title = _sceneTitles[scene.id]?.text ?? scene.title;
      for (final shot in scene.shots) {
        shot.title = _shotTitles[shot.id]?.text ?? shot.title;
        shot.note = _notes[shot.id]?.text ?? shot.note;
        for (final clip in shot.clips) {
          clip.startPrompt = _startPrompts[clip.id]?.text ?? clip.startPrompt;
          clip.endPrompt = _endPrompts[clip.id]?.text ?? clip.endPrompt;
          clip.videoPrompt = _vprompts[clip.id]?.text ?? clip.videoPrompt;
        }
      }
    }
    await _store.save(_scenes);
  }

  /// 텍스트 편집 중 호출: 라벨 즉시 갱신 + 저장.
  void noteEdited() {
    notifyListeners();
    save();
  }

  Future<void> saveSettings(MovieSettings s) async {
    _settings = s;
    notifyListeners();
    await _settingsStore.save(s);
  }

  // ───────── 씬 추가/삭제/선택 ─────────

  void addScene() {
    final id = 'scene_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    _sceneTitles[id] = TextEditingController();
    _scenes.add(StoryScene(id: id));
    _selectedSceneId = id;
    _selectedShotId = null;
    _selectedClipId = null;
    notifyListeners();
    save();
  }

  void removeScene(StoryScene scene) {
    final wasSelected = _selectedSceneId == scene.id;
    _scenes.remove(scene);
    _sceneTitles.remove(scene.id)?.dispose();
    for (final shot in scene.shots) {
      _disposeShotControllers(shot.id);
      for (final clip in shot.clips) {
        _disposeClipControllers(clip.id);
      }
    }
    if (wasSelected) {
      final next = _scenes.isNotEmpty ? _scenes.last : null;
      _selectSceneInternal(next?.id);
    }
    notifyListeners();
    save();
  }

  void selectScene(String id) {
    if (_selectedSceneId == id) return;
    _selectSceneInternal(id);
    notifyListeners();
  }

  void _selectSceneInternal(String? id) {
    _selectedSceneId = id;
    final scene = selectedScene;
    final firstShot =
        (scene != null && scene.shots.isNotEmpty) ? scene.shots.first : null;
    _selectedShotId = firstShot?.id;
    _selectedClipId =
        (firstShot != null && firstShot.clips.isNotEmpty) ? firstShot.clips.first.id : null;
  }

  // ───────── 샷(비트) 추가/삭제/선택 ─────────

  /// 새 샷 추가 — 빈 샷(클립 0개). 클립은 캔버스의 ＋ 로 직접 추가한다.
  void addShot() {
    final scene = selectedScene;
    if (scene == null) return; // 씬 먼저 선택/추가
    final shotId = 'shot_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    final shot = Shot(id: shotId);
    _addShotControllers(shot);
    scene.shots.add(shot);
    _selectedShotId = shotId;
    _selectedClipId = null; // 클립 없음
    notifyListeners();
    save();
  }

  void removeShot(Shot shot) {
    final scene = selectedScene;
    if (scene == null) return;
    final wasSelected = _selectedShotId == shot.id;
    scene.shots.remove(shot);
    _disposeShotControllers(shot.id);
    for (final clip in shot.clips) {
      _disposeClipControllers(clip.id);
    }
    if (wasSelected) {
      final next = scene.shots.isNotEmpty ? scene.shots.last : null;
      _selectedShotId = next?.id;
      _selectedClipId =
          (next != null && next.clips.isNotEmpty) ? next.clips.first.id : null;
    }
    notifyListeners();
    save();
  }

  /// 샷 선택(몸통 탭). 클립은 선택하지 않는다 — 클립 편집은 캔버스에서 클립을 직접 클릭.
  /// 클립 선택을 비우면 오른쪽 패널이 '샷' 탭으로 전환되고, 장면/영상 탭은 "클립을 선택하세요"로 안내한다.
  void selectShot(String id) {
    if (_selectedShotId == id && _selectedClipId == null) return;
    _selectedShotId = id;
    _selectedClipId = null;
    notifyListeners();
  }

  /// 샷 제작 상태 지정(사용자 수동).
  void setShotStatus(Shot shot, ShotStatus status) {
    if (shot.status == status) return;
    shot.status = status;
    notifyListeners();
    save();
  }

  /// 캔버스 아이콘 탭 시 다음 상태로 순환(준비→진행→검토→반려→완료→준비).
  void cycleShotStatus(Shot shot) {
    final vals = ShotStatus.values;
    setShotStatus(shot, vals[(shot.status.index + 1) % vals.length]);
  }

  // ───────── 클립 추가/삭제/선택 ─────────

  void addClip(Shot shot) {
    final id = 'clip_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    final clip = VideoClip(id: id, videoSeconds: _settings.videoSeconds);
    _addClipControllers(clip);
    shot.clips.add(clip);
    _selectedShotId = shot.id;
    _selectedClipId = id;
    notifyListeners();
    save();
  }

  void removeClip(Shot shot, VideoClip clip) {
    final wasSelected = _selectedClipId == clip.id;
    shot.clips.remove(clip);
    _disposeClipControllers(clip.id);
    if (wasSelected) {
      _selectedClipId = shot.clips.isNotEmpty ? shot.clips.last.id : null;
    }
    notifyListeners();
    save();
  }

  /// 클립 선택 — 소속 샷도 함께 선택된다.
  void selectClip(String shotId, String clipId) {
    _selectedShotId = shotId;
    _selectedClipId = clipId;
    notifyListeners();
  }

  /// 클립별 영상 길이(초, 1~15) 저장. 마지막 값은 새 클립 기본값으로도 기억한다.
  void setClipSeconds(VideoClip clip, int sec) {
    final v = sec.clamp(1, 15);
    clip.videoSeconds = v;
    _settings = _settings.copyWith(videoSeconds: v);
    _settingsStore.save(_settings);
    save();
  }

  // ───────── 대사(샷 소유, 0/1) ─────────
  // 대사는 샷이 소유한다(샷 하나 = 대사 1개 또는 없음). 편집은 모달에서 값만 반영.

  /// 이 샷의 대사 텍스트 저장(대사 없으면 새로 만든다).
  void setShotDialogueText(Shot shot, String text) {
    (shot.dialogue ??= Dialogue()).text = text;
    notifyListeners();
    save();
  }

  /// 이 샷의 대사 화자(Character.id, null=내레이션) 저장(대사 없으면 새로 만든다).
  void setShotDialogueSpeaker(Shot shot, String? speakerId) {
    (shot.dialogue ??= Dialogue()).speakerId = speakerId;
    notifyListeners();
    save();
  }

  /// 이 샷의 대사 제거(무음 샷으로).
  void removeShotDialogue(Shot shot) {
    shot.dialogue = null;
    notifyListeners();
    save();
  }

  /// 대사 음성 진행 상태 키(샷 단위).
  String voiceBusyKey(String shotId) => '$shotId:voice';

  /// 이 대사에 쓸 보이스: 화자에 보이스가 있으면 그것, 없으면 설정 기본(내레이션) 보이스.
  String? _voiceIdFor(Dialogue d) {
    final speaker = characterById(d.speakerId);
    if (speaker != null && speaker.hasVoice) return speaker.voiceId.trim();
    final def = _settings.elevenVoiceId.trim();
    return def.isEmpty ? null : def;
  }

  /// 이 샷의 대사 음성(일레븐랩스 TTS) 생성 → mp3 저장 + 길이(voiceSeconds) 실측.
  Future<void> genVoice(Shot shot) async {
    final d = shot.dialogue;
    if (d == null || d.text.trim().isEmpty) {
      messenger?.call('대사를 먼저 입력하세요');
      return;
    }
    if (!voiceReady) {
      messenger?.call(voiceBlockReason!);
      return;
    }
    final voiceId = _voiceIdFor(d);
    if (voiceId == null) {
      messenger?.call('보이스가 없습니다 — 화자에 보이스를 지정하거나 설정에서 기본 보이스를 정하세요');
      return;
    }
    final key = voiceBusyKey(shot.id);
    _busy.add(key);
    notifyListeners();
    try {
      final res = await ElevenLabsService(_settings.elevenKey)
          .generateSpeech(voiceId: voiceId, text: d.text.trim());
      final f = File('$projectDirPath/${shot.id}_voice.mp3');
      await f.writeAsBytes(res.bytes);
      d.voicePath = f.path;
      d.voiceSeconds = res.seconds;
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
    } catch (e, st) {
      debugPrint('[voice] $key 실패: $e\n$st');
      messenger?.call('음성 생성 실패: $e');
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  /// 선택 씬의 모든 샷 대사 음성 생성(대사가 있는 샷만, 순서대로).
  Future<void> genSceneVoices() async {
    final scene = selectedScene;
    if (scene == null) return;
    if (!voiceReady) {
      messenger?.call(voiceBlockReason!);
      return;
    }
    for (final shot in List<Shot>.from(scene.shots)) {
      if ((shot.dialogue?.text.trim().isNotEmpty) ?? false) {
        await genVoice(shot);
      }
    }
  }

  // ───────── 생성(클립) ─────────

  TextEditingController? _promptCtrlFor(String clipId, GenMode mode) =>
      switch (mode) {
        GenMode.imageStart => _startPrompts[clipId],
        GenMode.imageEnd => _endPrompts[clipId],
        GenMode.videoLow => _vprompts[clipId],
      };

  Future<void> gen(VideoClip clip, GenMode mode) async {
    final raw = _promptCtrlFor(clip.id, mode)?.text.trim() ?? '';
    final prompt = _composePrompt(clip, raw);
    if (prompt.isEmpty) {
      messenger?.call('${mode.label} 프롬프트를 입력하세요 (공통 프롬프트도 비어 있음)');
      return;
    }
    final key = busyKey(clip.id, mode);
    _busy.add(key);
    notifyListeners();
    try {
      final bytes = await _generateBytes(clip, mode, prompt);
      final ext = _extFor(bytes, mode);
      final name = switch (mode) {
        GenMode.imageStart => '${clip.id}_start',
        GenMode.imageEnd => '${clip.id}_end',
        GenMode.videoLow => '${clip.id}_vlow',
      };
      final f = File('$projectDirPath/$name.$ext');
      await f.writeAsBytes(bytes);
      await FileImage(f).evict();
      switch (mode) {
        case GenMode.imageStart:
          clip.startImagePath = f.path;
        case GenMode.imageEnd:
          clip.endImagePath = f.path;
        case GenMode.videoLow:
          clip.videoPath = f.path;
      }
      if (mode == GenMode.imageEnd) await _chainEndToNextStart(clip);
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
    } catch (e, st) {
      debugPrint('[generate] $key 실패: $e\n$st');
      messenger?.call('생성 실패: $e');
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  /// 시작/끝장면을 기존 이미지 파일에서 불러온다(생성 대신).
  Future<void> loadFrame(VideoClip clip, GenMode mode) async {
    if (mode.isVideo) return;
    const typeGroup = fs.XTypeGroup(
      label: 'images',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    final picked = await fs.openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    final key = busyKey(clip.id, mode);
    _busy.add(key);
    notifyListeners();
    try {
      final bytes = await picked.readAsBytes();
      final ext = _extFor(bytes, mode);
      final name =
          mode == GenMode.imageStart ? '${clip.id}_start' : '${clip.id}_end';
      final f = File('$projectDirPath/$name.$ext');
      await f.writeAsBytes(bytes);
      await FileImage(f).evict();
      if (mode == GenMode.imageStart) {
        clip.startImagePath = f.path;
      } else {
        clip.endImagePath = f.path;
        await _chainEndToNextStart(clip);
      }
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
    } catch (e, st) {
      debugPrint('[loadFrame] $key 실패: $e\n$st');
      messenger?.call('불러오기 실패: $e');
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  /// 설정된 백엔드로 라우팅해 바이트를 받는다. (여기 도달하는 영상 모드는 videoLow=생성뿐)
  Future<Uint8List> _generateBytes(
      VideoClip clip, GenMode mode, String prompt) async {
    if (!mode.isVideo) {
      switch (_settings.imageBackend) {
        case ImageBackend.gemini:
          return GeminiImageService().generate(
            apiKey: _settings.geminiKey,
            model: AiProvider.gemini.defaultModel,
            prompt: prompt,
            aspectRatio: _settings.imageAspect.ratio,
          );
        case ImageBackend.openai:
          return OpenAiImageService().generate(
            apiKey: _settings.openaiKey,
            model: AiProvider.openai.defaultModel,
            prompt: prompt,
            aspectRatio: _settings.imageAspect.ratio,
          );
        case ImageBackend.serviceApi:
          final refs = await _refPhotoBytesList(clip);
          if (refs.isNotEmpty) {
            final who = clip.refCharacterIds
                .map((id) => characterById(id)?.name)
                .whereType<String>()
                .where((n) => n.isNotEmpty)
                .join(', ');
            final instruction =
                '아래 참조 인물${who.isEmpty ? '' : '($who)'}을(를) 다음 장면에 자연스럽게 배치하라. '
                '각 인물의 얼굴·헤어스타일·의상 등 정체성은 그대로 유지할 것. 장면: $prompt';
            return ApiService(_settings.effectiveServiceUrl)
                .generateImageWithRefs(references: refs, prompt: instruction);
          }
          return ApiService(_settings.effectiveServiceUrl).generateImage(prompt);
      }
    }
    // 영상 생성(저) = FE2V: 시작·끝 두 프레임이 입력(둘 다 필수).
    switch (_settings.videoBackend) {
      case VideoBackend.veo:
        final start = await _startFrame(clip);
        final end = await _endFrame(clip);
        if (start == null) {
          throw Exception('시작장면을 먼저 만들어 주세요 (FE2V 첫 프레임)');
        }
        if (end == null) {
          throw Exception('끝장면을 먼저 만들어 주세요 (FE2V 마지막 프레임)');
        }
        return VeoVideoService().generate(
          apiKey: _settings.geminiKey,
          model: _settings.veoModel,
          prompt: prompt,
          image: start,
          lastFrame: end,
          aspectRatio: _settings.videoAspect.value,
          resolution: _settings.videoResolution.value,
          durationSeconds: _settings.videoDurationSeconds,
          negativePrompt: _settings.videoNegativePrompt,
          onProgress: (st) => messenger?.call(st),
        );
      case VideoBackend.serviceApi:
        final img = await _startFrameBytes(clip);
        final endImg = await _endFrameBytes(clip);
        if (img == null) {
          throw Exception('시작장면을 먼저 만들어 주세요 (FE2V 첫 프레임)');
        }
        if (endImg == null) {
          throw Exception('끝장면을 먼저 만들어 주세요 (FE2V 마지막 프레임)');
        }
        final res = _settings.videoRes;
        final sc = sceneOf(clip); // LoRA는 씬 단위
        return ApiService(_settings.effectiveServiceUrl).generateVideo(
          image: img,
          endImage: endImg,
          prompt: prompt,
          width: res.width,
          height: res.height,
          seconds: clip.videoSeconds,
          loraUrl: _effectiveLoraUrl(sc),
          loraStrength: sc?.loraStrength ?? 0.8,
          onProgress: (st) => messenger?.call(st),
        );
    }
  }

  /// 영상 생성 해상도(비율 포함) 선택 저장.
  void setVideoRes(VideoRes r) {
    _settings = _settings.copyWith(videoRes: r);
    notifyListeners();
    _settingsStore.save(_settings);
  }

  /// 선택 씬의 LoRA URL 저장(같은 씬 클립들끼리 공유, 씬끼리 별개).
  void setSceneLoraUrl(String url) {
    final sc = selectedScene;
    if (sc == null) return;
    sc.loraUrl = url.trim();
    notifyListeners();
    save();
  }

  /// 선택 씬의 LoRA 강도(0~1.5) 저장.
  void setSceneLoraStrength(double v) {
    final sc = selectedScene;
    if (sc == null) return;
    sc.loraStrength = v.clamp(0.0, 1.5);
    notifyListeners();
    save();
  }

  // ───────── 공통 프롬프트(프로젝트/씬) ─────────
  // 실제 생성 프롬프트 = [프로젝트 공통] + [씬 공통] + [클립 프롬프트].

  Future<void> setProjectCommonPrompt(String v) async {
    _projectCommonPrompt = v;
    await _store.saveCommonPrompt(v);
  }

  void setSceneCommonPrompt(String v) {
    final sc = selectedScene;
    if (sc == null) return;
    sc.commonPrompt = v;
    save();
  }

  /// 생성에 쓸 최종 프롬프트: 프로젝트·씬 공통을 앞에 붙인다(빈 칸은 제외).
  String _composePrompt(VideoClip clip, String clipPrompt) {
    final sc = sceneOf(clip);
    return [
      _projectCommonPrompt.trim(),
      (sc?.commonPrompt ?? '').trim(),
      clipPrompt.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
  }

  // ───────── 인물 참조(클립 화면의 캐릭터 레퍼런스) ─────────

  Future<void> reloadCharacters() async {
    _characters = await _store.loadCharacters();
    notifyListeners();
  }

  Character? characterById(String? id) {
    if (id == null) return null;
    for (final c in _characters) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 이 클립의 참조 인물 토글(있으면 제거, 없으면 추가 · 최대 3).
  void toggleClipRefCharacter(VideoClip clip, String id) {
    if (clip.refCharacterIds.contains(id)) {
      clip.refCharacterIds.remove(id);
    } else if (clip.refCharacterIds.length < 3) {
      clip.refCharacterIds.add(id);
    }
    notifyListeners();
    save();
  }

  /// 참조 인물들의 대표사진 바이트(최대 3, 존재하는 것만). 없으면 빈 리스트 → 일반 t2i.
  Future<List<Uint8List>> _refPhotoBytesList(VideoClip clip) async {
    final out = <Uint8List>[];
    for (final id in clip.refCharacterIds.take(3)) {
      final cover = characterById(id)?.cover;
      if (cover == null) continue;
      final f = File(cover);
      if (await f.exists()) out.add(await f.readAsBytes());
    }
    return out;
  }

  // ───────── 배경음(씬 단위 BGM · ACE-Step) ─────────

  String bgmBusyKey(String sceneId) => '$sceneId:bgm';

  void setSceneBgmPrompt(String prompt) {
    final sc = selectedScene;
    if (sc == null) return;
    sc.bgmPrompt = prompt.trim();
    notifyListeners();
    save();
  }

  void setSceneBgmSeconds(int sec) {
    final sc = selectedScene;
    if (sc == null) return;
    sc.bgmSeconds = sec.clamp(5, 240);
    notifyListeners();
    save();
  }

  Future<void> genBgm() async {
    final sc = selectedScene;
    if (sc == null) return;
    final prompt = sc.bgmPrompt.trim();
    if (prompt.isEmpty) {
      messenger?.call('배경음 스타일(프롬프트)을 입력하세요');
      return;
    }
    final key = bgmBusyKey(sc.id);
    _busy.add(key);
    notifyListeners();
    try {
      final bytes = await ApiService(_settings.effectiveServiceUrl)
          .generateBgm(prompt: prompt, seconds: sc.bgmSeconds);
      final f = File('$projectDirPath/${sc.id}_bgm.mp3');
      await f.writeAsBytes(bytes);
      sc.bgmPath = f.path;
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
    } catch (e, st) {
      debugPrint('[bgm] $key 실패: $e\n$st');
      messenger?.call('배경음 생성 실패: $e');
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  /// 인스펙터 마지막 선택 탭(0=장면, 1=영상, 2=공통) 저장.
  void setInspectorTab(int i) {
    if (_settings.inspectorTab == i) return;
    _settings = _settings.copyWith(inspectorTab: i);
    _settingsStore.save(_settings);
  }

  /// 클립이 속한 씬 찾기(씬 → 샷 → 클립 탐색).
  StoryScene? sceneOf(VideoClip clip) {
    for (final sc in _scenes) {
      for (final shot in sc.shots) {
        if (shot.clips.contains(clip)) return sc;
      }
    }
    return null;
  }

  Future<({List<int> bytes, String mimeType})?> _startFrame(VideoClip clip) async {
    final path = clip.startImagePath;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return (bytes: await f.readAsBytes(), mimeType: 'image/png');
  }

  Future<({List<int> bytes, String mimeType})?> _endFrame(VideoClip clip) async {
    final path = clip.endImagePath;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return (bytes: await f.readAsBytes(), mimeType: 'image/png');
  }

  /// FE2V 컷 연속성: [clip]의 끝 프레임을 타임라인상 **다음 클립의 시작 프레임**으로
  /// 자동으로 이어붙인다(끝 이미지 파일을 다음 클립의 시작 파일명으로 복사해 같은 프레임으로 맞춤).
  /// 씬 전체 클립 나열(sceneClips) 기준이라 샷 경계도 건너뛴다. 다음 클립이 없으면 아무것도 안 한다.
  Future<void> _chainEndToNextStart(VideoClip clip) async {
    final endPath = clip.endImagePath;
    if (endPath == null) return;
    final all = sceneClips;
    final i = all.indexOf(clip);
    if (i < 0 || i + 1 >= all.length) return; // 마지막 클립 → 이어붙일 대상 없음
    final next = all[i + 1];
    final src = File(endPath);
    if (!await src.exists()) return;
    final ext = endPath.split('.').last;
    final dst = File('$projectDirPath/${next.id}_start.$ext');
    await src.copy(dst.path);
    await FileImage(dst).evict();
    next.startImagePath = dst.path;
    final k = busyKey(next.id, GenMode.imageStart);
    _ver[k] = (_ver[k] ?? 0) + 1;
    messenger?.call('다음 클립 시작 프레임으로 이어붙였습니다');
  }

  /// LoRA URL 정규화: civitai 페이지 URL → api/download 링크로 변환 + 토큰 자동 부착.
  String _effectiveLoraUrl(StoryScene? sc) {
    var url = (sc?.loraUrl ?? '').trim();
    if (url.isEmpty) return '';
    if (url.contains('civitai.com')) {
      if (!url.contains('/api/download/')) {
        final vid = RegExp(r'modelVersionId=(\d+)').firstMatch(url)?.group(1);
        if (vid != null) {
          url = 'https://civitai.com/api/download/models/$vid';
        }
      }
      final token = _settings.civitaiToken.trim();
      if (token.isNotEmpty && !url.contains('token=')) {
        url += '${url.contains('?') ? '&' : '?'}token=$token';
      }
    }
    return url;
  }

  Future<Uint8List?> _startFrameBytes(VideoClip clip) async {
    final path = clip.startImagePath;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  Future<Uint8List?> _endFrameBytes(VideoClip clip) async {
    final path = clip.endImagePath;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  String _extFor(Uint8List b, GenMode mode) {
    if (!mode.isVideo) return 'png';
    final isWebp = b.length > 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50;
    return isWebp ? 'webp' : 'mp4';
  }

  Future<void> openFile(String path) async {
    try {
      await Process.run('open', [path]);
    } catch (e) {
      messenger?.call('열기 실패: $e');
    }
  }

  /// 생성물(영상/이미지)을 사용자가 고른 위치로 내보낸다(저장 다이얼로그 → 복사).
  Future<void> exportFile(String srcPath) async {
    final src = File(srcPath);
    if (!await src.exists()) {
      messenger?.call('내보낼 파일이 없습니다');
      return;
    }
    final suggested = srcPath.split('/').last;
    final loc = await fs.getSaveLocation(suggestedName: suggested);
    if (loc == null) return;
    try {
      await src.copy(loc.path);
      messenger?.call('내보냈습니다: ${loc.path}');
    } catch (e, st) {
      debugPrint('[export] 실패: $e\n$st');
      messenger?.call('내보내기 실패: $e');
    }
  }

  // ───────── 사이드/플레이어 토글 ─────────

  void toggleSceneList() {
    _sceneListOpen = !_sceneListOpen;
    notifyListeners();
  }

  void togglePlayer() {
    _playerOpen = !_playerOpen;
    notifyListeners();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    for (final c in _sceneTitles.values) {
      c.dispose();
    }
    for (final c in _shotTitles.values) {
      c.dispose();
    }
    for (final c in _notes.values) {
      c.dispose();
    }
    for (final c in _startPrompts.values) {
      c.dispose();
    }
    for (final c in _endPrompts.values) {
      c.dispose();
    }
    for (final c in _vprompts.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// 서브트리에 [StoryboardProvider]를 내려보내고, 변경 시 구독 위젯을 리빌드한다.
class StoryboardScope extends InheritedNotifier<StoryboardProvider> {
  const StoryboardScope({
    super.key,
    required StoryboardProvider super.notifier,
    required super.child,
  });

  static StoryboardProvider of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoryboardScope>();
    assert(scope != null, 'StoryboardScope를 찾을 수 없습니다');
    return scope!.notifier!;
  }

  static StoryboardProvider read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<StoryboardScope>();
    assert(scope != null, 'StoryboardScope를 찾을 수 없습니다');
    return scope!.notifier!;
  }
}
