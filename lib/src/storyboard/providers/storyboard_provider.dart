import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:framework/framework.dart';
import 'package:video_player/video_player.dart'; // 불러온 오디오 길이 실측용

import '../models/character.dart';
import '../models/shot.dart';
import '../models/dialogue.dart';
import '../models/dialogue_beat.dart';
import '../models/story_scene.dart';
import '../services/api_service.dart';
import '../services/elevenlabs_service.dart';
import '../services/movie_settings.dart';
import '../services/storyboard_store.dart';
import '../services/video_edit.dart';

/// 스토리보드 화면 전체가 공유하는 상태/로직 홀더.
/// 구조: 스토리보드 → 씬(StoryScene) → 대사(DialogueBeat: 대사 내용 0/1 + 샷 여러 개) → 샷(Shot).
/// 좌측 씬 목록·캔버스(선택 씬의 대사/샷)·인스펙터·플레이어·설정이 [StoryboardScope]로 구독한다.
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
  List<Character> _characters = []; // 프로젝트 등장인물(인물 참조 피커/생성용)

  // 컨트롤러: 씬 제목(씬 id) · 대사 제목/메모(대사 id) · 샷 프롬프트(샷 id).
  final Map<String, TextEditingController> _sceneTitles = {};
  final Map<String, TextEditingController> _dialogueTitles = {};
  final Map<String, TextEditingController> _notes = {};
  final Map<String, TextEditingController> _directions = {};
  final Map<String, TextEditingController> _startPrompts = {};
  final Map<String, TextEditingController> _startPromptKos = {};
  final Map<String, TextEditingController> _endPrompts = {};
  final Map<String, TextEditingController> _endPromptKos = {};
  final Map<String, TextEditingController> _vprompts = {};
  final Map<String, TextEditingController> _vpromptKos = {};
  final Map<String, TextEditingController> _vnegs = {};
  final Set<String> _busy = {}; // '<shotId>:<mode>' 또는 '<dialogueId>:voice' 등 진행 중
  final Map<String, int> _ver = {}; // 미리보기 캐시 버전

  List<StoryScene> _scenes = []; // 씬 리스트
  String? _selectedSceneId;
  String? _selectedDialogueId; // 선택된 샷(비트)
  String? _selectedShotId; // 선택된 샷(선택 대사 안에서)
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
  List<Character> get characters => _characters;
  String? get selectedSceneId => _selectedSceneId;
  String? get selectedDialogueId => _selectedDialogueId;
  String? get selectedShotId => _selectedShotId;
  String? get savePath => _savePath;
  bool get sceneListOpen => _sceneListOpen;
  bool get playerOpen => _playerOpen;
  ApiStatus get apiStatus => _apiStatus;

  // ───────── 백엔드별 생성 준비 상태(버튼 활성/비활성 판단) ─────────

  /// 이미지(시작/끝장면) 생성 가능 여부 — 자체 서버(service-api) 전용.
  bool get imageReady => _apiStatus.reachable;

  String? get imageBlockReason =>
      imageReady ? null : '서버에 연결되지 않았습니다 (상단·설정에서 확인)';

  /// 영상 생성 가능 여부 — **백엔드별로** 판단한다(생성 버튼이 백엔드를 직접 고르므로).
  /// [b] 생략 시 설정의 기본 백엔드 기준.
  bool videoReadyOf(VideoBackend b) => switch (b) {
    VideoBackend.serviceApi => _apiStatus.reachable && _apiStatus.videoReady,
    VideoBackend.veo => _settings.geminiKey.trim().isNotEmpty,
  };

  String? videoBlockReasonOf(VideoBackend b) => videoReadyOf(b)
      ? null
      : switch (b) {
          VideoBackend.serviceApi =>
            _apiStatus.reachable
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
  String? get voiceBlockReason => voiceReady ? null : '일레븐랩스 API 키가 없습니다 (설정)';

  StoryScene? get selectedScene {
    for (final s in _scenes) {
      if (s.id == _selectedSceneId) return s;
    }
    return null;
  }

  /// 현재 선택 씬의 대사들(캔버스가 타임라인으로 그리는 대상).
  List<DialogueBeat> get dialogues => selectedScene?.dialogues ?? const [];

  DialogueBeat? get selectedDialogue {
    for (final s in dialogues) {
      if (s.id == _selectedDialogueId) return s;
    }
    return null;
  }

  /// 선택 대사 안의 샷들.
  List<Shot> get shots => selectedDialogue?.shots ?? const [];

  /// 선택 씬의 모든 샷(대사 순서 → 샷 순서로 평탄화). 미리보기·연속 재생용.
  List<Shot> get sceneShots => [for (final sh in dialogues) ...sh.shots];

  Shot? get selectedShot {
    for (final c in shots) {
      if (c.id == _selectedShotId) return c;
    }
    return null;
  }

  TextEditingController sceneTitleCtrl(String sceneId) =>
      _sceneTitles[sceneId]!;
  TextEditingController titleCtrl(String dialogueId) => _dialogueTitles[dialogueId]!;
  TextEditingController noteCtrl(String dialogueId) => _notes[dialogueId]!;
  TextEditingController directionCtrl(String dialogueId) =>
      _directions[dialogueId]!;
  TextEditingController startCtrl(String shotId) => _startPrompts[shotId]!;
  TextEditingController startKoCtrl(String shotId) => _startPromptKos[shotId]!;
  TextEditingController endCtrl(String shotId) => _endPrompts[shotId]!;
  TextEditingController endKoCtrl(String shotId) => _endPromptKos[shotId]!;
  TextEditingController videoCtrl(String shotId) => _vprompts[shotId]!;
  TextEditingController videoKoCtrl(String shotId) => _vpromptKos[shotId]!;
  TextEditingController videoNegCtrl(String shotId) => _vnegs[shotId]!;

  bool isBusy(String key) => _busy.contains(key);
  int verOf(String key) => _ver[key] ?? 0;
  String busyKey(String id, GenMode m) => '$id:${m.name}';

  String? videoPathOf(Shot c) => c.videoPath;

  // ───────── 로드/저장 ─────────

  Future<void> _load() async {
    _settings = await _settingsStore.load();
    _settingsLoaded = true;
    final scenes = await _store.load();
    final path = _store.path();
    _scenes = scenes;
    _characters = await _store.loadCharacters();
    for (final scene in scenes) {
      _sceneTitles[scene.id] = TextEditingController(text: scene.title);
      for (final beat in scene.dialogues) {
        _addDialogueControllers(beat);
        for (final shot in beat.shots) {
          _addShotControllers(shot);
        }
      }
    }
    final firstScene = scenes.isNotEmpty ? scenes.first : null;
    final firstShot = (firstScene != null && firstScene.dialogues.isNotEmpty)
        ? firstScene.dialogues.first
        : null;
    _selectedSceneId = firstScene?.id;
    _selectedDialogueId = firstShot?.id;
    _selectedShotId = (firstShot != null && firstShot.shots.isNotEmpty)
        ? firstShot.shots.first.id
        : null;
    _savePath = path;
    notifyListeners();
    checkConnection();
    _statusTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => checkConnection(),
    );
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

  void _addDialogueControllers(DialogueBeat beat) {
    _dialogueTitles[beat.id] = TextEditingController(text: beat.title);
    _notes[beat.id] = TextEditingController(text: beat.note);
    _directions[beat.id] = TextEditingController(text: beat.direction);
  }

  void _disposeDialogueControllers(String dialogueId) {
    _dialogueTitles.remove(dialogueId)?.dispose();
    _notes.remove(dialogueId)?.dispose();
    _directions.remove(dialogueId)?.dispose();
  }

  void _addShotControllers(Shot shot) {
    _startPrompts[shot.id] = TextEditingController(text: shot.startPrompt);
    _startPromptKos[shot.id] = TextEditingController(text: shot.startPromptKo);
    _endPrompts[shot.id] = TextEditingController(text: shot.endPrompt);
    _endPromptKos[shot.id] = TextEditingController(text: shot.endPromptKo);
    _vprompts[shot.id] = TextEditingController(text: shot.videoPrompt);
    _vpromptKos[shot.id] = TextEditingController(text: shot.videoPromptKo);
    _vnegs[shot.id] = TextEditingController(text: shot.videoNegativePrompt);
  }

  void _disposeShotControllers(String shotId) {
    _startPrompts.remove(shotId)?.dispose();
    _startPromptKos.remove(shotId)?.dispose();
    _endPrompts.remove(shotId)?.dispose();
    _endPromptKos.remove(shotId)?.dispose();
    _vprompts.remove(shotId)?.dispose();
    _vpromptKos.remove(shotId)?.dispose();
    _vnegs.remove(shotId)?.dispose();
  }

  Future<void> save() async {
    for (final scene in _scenes) {
      scene.title = _sceneTitles[scene.id]?.text ?? scene.title;
      for (final beat in scene.dialogues) {
        beat.title = _dialogueTitles[beat.id]?.text ?? beat.title;
        beat.note = _notes[beat.id]?.text ?? beat.note;
        beat.direction = _directions[beat.id]?.text ?? beat.direction;
        for (final shot in beat.shots) {
          shot.startPrompt = _startPrompts[shot.id]?.text ?? shot.startPrompt;
          shot.startPromptKo =
              _startPromptKos[shot.id]?.text ?? shot.startPromptKo;
          shot.endPrompt = _endPrompts[shot.id]?.text ?? shot.endPrompt;
          shot.endPromptKo =
              _endPromptKos[shot.id]?.text ?? shot.endPromptKo;
          shot.videoPrompt = _vprompts[shot.id]?.text ?? shot.videoPrompt;
          shot.videoPromptKo =
              _vpromptKos[shot.id]?.text ?? shot.videoPromptKo;
          shot.videoNegativePrompt =
              _vnegs[shot.id]?.text ?? shot.videoNegativePrompt;
        }
      }
      _syncLinkedStartPrompts(scene);
    }
    await _store.save(_scenes);
  }

  /// 시작장면을 연동한 샷의 프롬프트를 앞 샷의 끝 프롬프트에 맞춘다.
  /// 이미지는 앞 샷의 끝이 만들어질 때 복사되지만 프롬프트는 그냥 타이핑이라 그 계기가 없다 —
  /// 저장(=글자 하나 칠 때마다)마다 맞춰야 연동이 실제로 살아 있다.
  void _syncLinkedStartPrompts(StoryScene scene) {
    final all = [for (final beat in scene.dialogues) ...beat.shots];
    for (var i = 1; i < all.length; i++) {
      final shot = all[i];
      if (!shot.linkStart) continue;
      final prompt = all[i - 1].endPrompt;
      if (shot.startPrompt == prompt) continue;
      shot.startPrompt = prompt;
      // 읽기 전용 칸이라 사용자가 타이핑 중일 리 없다 — 덮어써도 안전하다.
      _startPrompts[shot.id]?.text = prompt;
    }
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
    _selectedDialogueId = null;
    _selectedShotId = null;
    notifyListeners();
    save();
  }

  void removeScene(StoryScene scene) {
    final wasSelected = _selectedSceneId == scene.id;
    _scenes.remove(scene);
    _sceneTitles.remove(scene.id)?.dispose();
    for (final beat in scene.dialogues) {
      _disposeDialogueControllers(beat.id);
      for (final shot in beat.shots) {
        _disposeShotControllers(shot.id);
      }
    }
    if (wasSelected) {
      final next = _scenes.isNotEmpty ? _scenes.last : null;
      _selectSceneInternal(next?.id);
    }
    notifyListeners();
    save();
  }

  /// 선택된 씬을 **통째로 복제해 목록 맨 뒤에 추가**하고 그 복제본을 선택한다.
  /// 프롬프트·대사·샷은 물론 미디어(프레임·영상·음성·배경음)까지 새 파일로 복사해
  /// 원본과 완전히 분리한다 — 복제본을 지우거나 다시 뽑아도 원본은 그대로다.
  Future<void> duplicateScene() async {
    final src = selectedScene;
    if (src == null) return;
    // 왕복(toJson→fromJson)으로 독립 객체 트리를 얻는다. 이 시점 미디어 경로는
    // 아직 원본 파일을 가리키므로, 아래에서 새 id 이름으로 복사해 갈아끼운다.
    final copy = StoryScene.fromJson(src.toJson(), projectDirPath);
    copy.id = _newId('scene');
    copy.title = _dupTitle(src.title);
    copy.bgmPath = await _copyMedia(copy.bgmPath, '${copy.id}_bgm');

    for (final beat in copy.dialogues) {
      final newBeatId = _newId('shot');
      final voice = beat.dialogue?.voicePath;
      if (voice != null) {
        beat.dialogue!.voicePath =
            await _copyMedia(voice, '${newBeatId}_voice');
      }
      for (final shot in beat.shots) {
        final newShotId = _newId('clip');
        // 연동(linkStart) 중인 시작장면은 자기 파일이 없다(앞 샷 끝을 가리킴) — 복사할 것도 없다.
        shot.startImagePath =
            await _copyMedia(shot.startImagePath, '${newShotId}_start');
        shot.endImagePath =
            await _copyMedia(shot.endImagePath, '${newShotId}_end');
        shot.videoPath =
            await _copyMedia(shot.videoPath, '${newShotId}_vlow');
        shot.id = newShotId;
      }
      beat.id = newBeatId;
    }

    // 컨트롤러 등록(새 id 기준).
    _sceneTitles[copy.id] = TextEditingController(text: copy.title);
    for (final beat in copy.dialogues) {
      _addDialogueControllers(beat);
      for (final shot in beat.shots) {
        _addShotControllers(shot);
      }
    }

    _scenes.add(copy);
    _selectSceneInternal(copy.id);
    notifyListeners();
    await save();
    messenger?.call('씬을 복제했습니다');
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';

  /// 복제본 제목: 비어 있으면 그대로 두고(자동으로 '(제목 없음)' 표시), 있으면 ' 복사본'을 붙인다.
  String _dupTitle(String title) {
    final t = title.trim();
    return t.isEmpty ? '' : '$t 복사본';
  }

  /// [srcPath] 파일을 [newBase](확장자 제외 새 파일명)로 프로젝트 폴더에 복사하고 새 절대경로를 돌려준다.
  /// 경로가 없거나 파일이 실제로 없으면 null — 복제본이 깨진 참조를 물지 않게.
  Future<String?> _copyMedia(String? srcPath, String newBase) async {
    if (srcPath == null) return null;
    final src = File(srcPath);
    if (!await src.exists()) return null;
    final ext = srcPath.split('.').last;
    final dst = File('$projectDirPath/$newBase.$ext');
    await src.copy(dst.path);
    await FileImage(dst).evict();
    return dst.path;
  }

  /// 선택된 씬을 목록에서 [delta]칸 옮긴다(-1=위로, +1=아래로). 범위를 벗어나면 무시.
  /// 저장은 순서대로 scene1.json…을 다시 쓰므로 순서만 바뀐다(미디어는 id 기준이라 무관).
  Future<void> moveScene(int delta) async {
    final i = _scenes.indexWhere((s) => s.id == _selectedSceneId);
    if (i < 0) return;
    final j = i + delta;
    if (j < 0 || j >= _scenes.length) return; // 이미 끝
    final s = _scenes.removeAt(i);
    _scenes.insert(j, s);
    notifyListeners();
    await save();
  }

  bool get canMoveSceneUp {
    final i = _scenes.indexWhere((s) => s.id == _selectedSceneId);
    return i > 0;
  }

  bool get canMoveSceneDown {
    final i = _scenes.indexWhere((s) => s.id == _selectedSceneId);
    return i >= 0 && i < _scenes.length - 1;
  }

  void selectScene(String id) {
    if (_selectedSceneId == id) return;
    _selectSceneInternal(id);
    notifyListeners();
  }

  void _selectSceneInternal(String? id) {
    _selectedSceneId = id;
    final scene = selectedScene;
    final firstShot = (scene != null && scene.dialogues.isNotEmpty)
        ? scene.dialogues.first
        : null;
    _selectedDialogueId = firstShot?.id;
    _selectedShotId = (firstShot != null && firstShot.shots.isNotEmpty)
        ? firstShot.shots.first.id
        : null;
  }

  // ───────── 샷(비트) 추가/삭제/선택 ─────────

  /// 새 대사 추가 — 빈 대사(샷 0개). 샷은 캔버스의 ＋ 로 직접 추가한다.
  void addDialogue() {
    final scene = selectedScene;
    if (scene == null) return; // 씬 먼저 선택/추가
    final dialogueId = 'shot_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    final beat = DialogueBeat(id: dialogueId);
    _addDialogueControllers(beat);
    scene.dialogues.add(beat);
    _selectedDialogueId = dialogueId;
    _selectedShotId = null; // 샷 없음
    notifyListeners();
    save();
  }

  void removeDialogue(DialogueBeat beat) {
    final scene = selectedScene;
    if (scene == null) return;
    final wasSelected = _selectedDialogueId == beat.id;
    scene.dialogues.remove(beat);
    _disposeDialogueControllers(beat.id);
    for (final shot in beat.shots) {
      _disposeShotControllers(shot.id);
    }
    if (wasSelected) {
      final next = scene.dialogues.isNotEmpty ? scene.dialogues.last : null;
      _selectedDialogueId = next?.id;
      _selectedShotId = (next != null && next.shots.isNotEmpty)
          ? next.shots.first.id
          : null;
    }
    notifyListeners();
    save();
  }

  /// 대사 선택(몸통 탭). 샷은 선택하지 않는다 — 샷 편집은 캔버스에서 샷을 직접 클릭.
  /// 샷 선택을 비우면 오른쪽 패널이 '대사' 탭으로 전환되고, 장면/영상 탭은 "샷을 선택하세요"로 안내한다.
  void selectDialogue(String id) {
    if (_selectedDialogueId == id && _selectedShotId == null) return;
    _selectedDialogueId = id;
    _selectedShotId = null;
    notifyListeners();
  }



  // ───────── 샷 추가/삭제/선택 ─────────

  Future<void> addShot(DialogueBeat beat) async {
    final id = 'clip_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    final shot = Shot(id: id, videoSeconds: _settings.videoSeconds);
    _addShotControllers(shot);
    beat.shots.add(shot);
    _selectedDialogueId = beat.id;
    _selectedShotId = id;
    // FE2V 컷 연속성: 컷은 이어지는 게 기본이라 앞 샷이 있으면 시작장면을 연동해서 시작한다.
    // (씬의 첫 샷은 물려받을 앞이 없으니 꺼진 채로 둔다.) 연동은 앞 샷의 끝을 그대로
    // 가리키는 것이라 여기서 옮겨올 파일이 없다.
    shot.linkStart = prevShotOf(shot) != null;
    await save(); // 프롬프트 연동이 여기서 걸리므로 알리기 전에 저장한다
    notifyListeners();
  }

  void removeShot(DialogueBeat beat, Shot shot) {
    final wasSelected = _selectedShotId == shot.id;
    beat.shots.remove(shot);
    _disposeShotControllers(shot.id);
    if (wasSelected) {
      _selectedShotId = beat.shots.isNotEmpty ? beat.shots.last.id : null;
    }
    notifyListeners();
    save();
  }

  /// 샷 선택 — 소속 대사도 함께 선택된다.
  void selectShot(String dialogueId, String shotId) {
    _selectedDialogueId = dialogueId;
    _selectedShotId = shotId;
    notifyListeners();
  }

  /// 샷별 영상 길이(초, 1~15) 저장. 마지막 값은 새 샷 기본값으로도 기억한다.
  void setShotSeconds(Shot shot, int sec) {
    final v = sec.clamp(1, 15);
    shot.videoSeconds = v;
    _settings = _settings.copyWith(videoSeconds: v);
    _settingsStore.save(_settings);
    save();
  }

  // ───────── 대사(샷 소유, 0/1) ─────────
  // 대사는 샷이 소유한다(샷 하나 = 대사 1개 또는 없음). 편집은 모달에서 값만 반영.

  /// 이 샷의 대사 텍스트 저장(대사 없으면 새로 만든다).
  void setShotDialogueText(DialogueBeat beat, String text) {
    (beat.dialogue ??= Dialogue()).text = text;
    notifyListeners();
    save();
  }

  /// 이 샷의 대사 화자(Character.id, null=내레이션) 저장(대사 없으면 새로 만든다).
  void setShotDialogueSpeaker(DialogueBeat beat, String? speakerId) {
    (beat.dialogue ??= Dialogue()).speakerId = speakerId;
    notifyListeners();
    save();
  }

  /// 이 샷의 대사 제거(무음 샷으로).
  void removeShotDialogue(DialogueBeat beat) {
    beat.dialogue = null;
    notifyListeners();
    save();
  }

  /// 대사 음성 진행 상태 키(샷 단위).
  String voiceBusyKey(String dialogueId) => '$dialogueId:voice';

  /// 이 대사에 쓸 보이스: 화자에 보이스가 있으면 그것, 없으면 설정 기본(내레이션) 보이스.
  String? _voiceIdFor(Dialogue d) {
    final speaker = characterById(d.speakerId);
    if (speaker != null && speaker.hasVoice) return speaker.voiceId.trim();
    final def = _settings.elevenVoiceId.trim();
    return def.isEmpty ? null : def;
  }

  /// 오디오 파일 길이(초) 실측. 음성 길이가 대사(비트)의 타임라인 길이를 정하므로,
  /// 불러온 파일도 반드시 재어 둔다. (재생에 이미 쓰는 video_player로 잰다 — 오디오도 된다.)
  Future<double> _audioSeconds(File f) async {
    final c = VideoPlayerController.file(f);
    try {
      await c.initialize();
      return c.value.duration.inMilliseconds / 1000.0;
    } finally {
      await c.dispose();
    }
  }

  /// 대사 음성을 기존 오디오 파일에서 불러온다(기본 동선 — 생성은 부가).
  Future<void> loadVoice(DialogueBeat beat) async {
    const typeGroup = fs.XTypeGroup(
      label: 'audio',
      extensions: ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'],
    );
    final picked = await fs.openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    final key = voiceBusyKey(beat.id);
    _busy.add(key);
    notifyListeners();
    try {
      final ext = picked.name.split('.').last.toLowerCase();
      final f = File('$projectDirPath/${beat.id}_voice.$ext');
      await f.writeAsBytes(await picked.readAsBytes());
      // 확장자가 바뀌면 옛 파일이 남으므로 정리.
      for (final e in Directory(projectDirPath).listSync().whereType<File>()) {
        final n = e.uri.pathSegments.last;
        if (n.startsWith('${beat.id}_voice.') && e.path != f.path) {
          await e.delete();
        }
      }
      final d = beat.dialogue ??= Dialogue();
      d.voicePath = f.path;
      d.voiceSeconds = await _audioSeconds(f);
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
    } catch (e, st) {
      debugPrint('[loadVoice] $key 실패: $e\n$st');
      messenger?.call('음성 불러오기 실패: $e');
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  /// 이 샷의 대사 음성(일레븐랩스 TTS) 생성 → mp3 저장 + 길이(voiceSeconds) 실측.
  Future<void> genVoice(DialogueBeat beat) async {
    final d = beat.dialogue;
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
    final key = voiceBusyKey(beat.id);
    _busy.add(key);
    notifyListeners();
    try {
      final res = await ElevenLabsService(
        _settings.elevenKey,
      ).generateSpeech(voiceId: voiceId, text: d.text.trim());
      final f = File('$projectDirPath/${beat.id}_voice.mp3');
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
    for (final beat in List<DialogueBeat>.from(scene.dialogues)) {
      if ((beat.dialogue?.text.trim().isNotEmpty) ?? false) {
        await genVoice(beat);
      }
    }
  }

  // ───────── 씬 일괄 영상 생성 ─────────
  // (계획 타입 SceneVideoPlan / BlockedShot은 이 파일 맨 아래에 있다.)

  bool _batchRunning = false;
  bool _batchCancel = false;
  int _batchDone = 0;
  int _batchTotal = 0;

  bool get batchRunning => _batchRunning;
  int get batchDone => _batchDone;
  int get batchTotal => _batchTotal;

  /// 진행 중인 일괄 생성을 멈춘다 — 지금 돌고 있는 샷 하나는 끝까지 가고 그 다음부터 중단.
  /// (서버에 이미 올린 작업을 중간에 버리면 GPU 시간만 날린다.)
  void cancelBatch() {
    if (_batchRunning) _batchCancel = true;
    notifyListeners();
  }

  /// 선택 씬의 샷을 훑어 일괄 영상 생성 계획을 세운다 — **생성 전에 미리 보여주기 위한 것**이라
  /// 부수효과가 없다. [skipExisting]이면 이미 영상이 있는 샷은 건너뛸 목록으로 뺀다.
  ///
  /// FE2V는 시작·끝 프레임이 둘 다 있어야 하고 프롬프트도 필요하다 — 하나라도 없으면
  /// 그 샷은 blocked로 가고, 호출부는 경고로 띄운다.
  SceneVideoPlan sceneVideoPlan({required bool skipExisting}) {
    final scene = selectedScene;
    if (scene == null) return const SceneVideoPlan([], [], []);
    final ready = <Shot>[];
    final blocked = <BlockedShot>[];
    final skipped = <Shot>[];
    for (final beat in scene.dialogues) {
      for (final shot in beat.shots) {
        if (skipExisting && shot.videoPath != null) {
          skipped.add(shot);
          continue;
        }
        final missing = <String>[];
        if (!_hasFile(startPathOf(shot))) missing.add('시작장면');
        // I2V는 끝 프레임을 안 쓴다 — 없어도 뽑을 수 있다.
        if (!shot.i2v && !_hasFile(shot.endImagePath)) missing.add('끝장면');
        final raw = _promptCtrlFor(shot.id, GenMode.videoLow)?.text ??
            shot.videoPrompt;
        if (_composePrompt(shot, raw, GenMode.videoLow).isEmpty) {
          missing.add('영상 프롬프트');
        }
        if (missing.isEmpty) {
          ready.add(shot);
        } else {
          blocked.add(BlockedShot(shot, shotLabel(shot), missing));
        }
      }
    }
    return SceneVideoPlan(ready, blocked, skipped);
  }

  bool _hasFile(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  /// 사람이 알아볼 샷 이름 — 제목이 없으면 씬 안에서 몇 번째 샷인지로 부른다.
  String shotLabel(Shot shot) {
    if (shot.title.trim().isNotEmpty) return shot.title.trim();
    final scene = sceneOf(shot);
    if (scene == null) return '샷';
    var n = 0;
    for (final beat in scene.dialogues) {
      for (final s in beat.shots) {
        n++;
        if (identical(s, shot)) return '샷 $n';
      }
    }
    return '샷';
  }

  /// 선택 씬의 영상을 한 번에 만든다.
  Future<void> genSceneVideos({required bool skipExisting}) =>
      _runBatch(sceneVideoPlan(skipExisting: skipExisting));

  /// 계획의 ready 샷들을 순서대로 생성한다.
  ///
  /// 준비가 안 된 샷은 계획 단계에서 이미 걸러졌으므로 여기서는 생성 가능한 것만 돈다.
  /// **한 번에 하나씩** 돌린다 — 서버 GPU가 하나뿐이라 동시에 던져봐야 큐에서 밀린다.
  Future<void> _runBatch(SceneVideoPlan plan) async {
    if (_batchRunning) return;
    if (plan.ready.isEmpty) {
      messenger?.call('생성할 샷이 없습니다');
      return;
    }
    _batchRunning = true;
    _batchCancel = false;
    _batchDone = 0;
    _batchTotal = plan.ready.length;
    notifyListeners();
    try {
      for (final shot in plan.ready) {
        if (_batchCancel) break;
        messenger?.call(
          '[${_batchDone + 1}/$_batchTotal] ${shotLabel(shot)} 영상 생성 중…',
        );
        await gen(shot, GenMode.videoLow);
        _batchDone++;
        notifyListeners();
      }
      messenger?.call(
        _batchCancel
            ? '일괄 생성을 멈췄습니다 ($_batchDone/$_batchTotal 완료)'
            : '영상 $_batchDone개 생성 완료',
      );
    } finally {
      _batchRunning = false;
      _batchCancel = false;
      notifyListeners();
    }
  }

  // ───────── 생성(샷) ─────────

  TextEditingController? _promptCtrlFor(String shotId, GenMode mode) =>
      switch (mode) {
        GenMode.imageStart => _startPrompts[shotId],
        GenMode.imageEnd => _endPrompts[shotId],
        GenMode.videoLow => _vprompts[shotId],
      };

  /// [backend] 영상 생성에만 의미 있음 — 어느 백엔드로 뽑을지 호출 시점에 고른다.
  /// null이면 설정의 기본 백엔드. (결과 슬롯은 하나라 백엔드를 바꿔 다시 뽑으면 덮어쓴다.)
  Future<void> gen(
    Shot shot,
    GenMode mode, {
    VideoBackend? backend,
  }) async {
    final raw = _promptCtrlFor(shot.id, mode)?.text.trim() ?? '';
    final prompt = _composePrompt(shot, raw, mode);
    if (prompt.isEmpty) {
      messenger?.call('${mode.label} 프롬프트를 입력하세요 (공통 프롬프트도 비어 있음)');
      return;
    }
    final key = busyKey(shot.id, mode);
    _busy.add(key);
    notifyListeners();
    try {
      final bytes = await _generateBytes(shot, mode, prompt, backend);
      final ext = _extFor(bytes, mode);
      final name = switch (mode) {
        GenMode.imageStart => '${shot.id}_start',
        GenMode.imageEnd => '${shot.id}_end',
        GenMode.videoLow => '${shot.id}_vlow',
      };
      final f = File('$projectDirPath/$name.$ext');
      await f.writeAsBytes(bytes);
      await FileImage(f).evict();
      switch (mode) {
        case GenMode.imageStart:
          shot.startImagePath = f.path;
        case GenMode.imageEnd:
          shot.endImagePath = f.path;
        case GenMode.videoLow:
          shot.videoPath = f.path;
      }
      if (mode == GenMode.imageEnd) _refreshLinkedNext(shot);
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
  Future<void> loadFrame(Shot shot, GenMode mode) async {
    if (mode.isVideo) return;
    const typeGroup = fs.XTypeGroup(
      label: 'images',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    final picked = await fs.openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    final key = busyKey(shot.id, mode);
    _busy.add(key);
    notifyListeners();
    try {
      final bytes = await picked.readAsBytes();
      final ext = _extFor(bytes, mode);
      final name = mode == GenMode.imageStart
          ? '${shot.id}_start'
          : '${shot.id}_end';
      final f = File('$projectDirPath/$name.$ext');
      await f.writeAsBytes(bytes);
      await FileImage(f).evict();
      if (mode == GenMode.imageStart) {
        shot.startImagePath = f.path;
      } else {
        shot.endImagePath = f.path;
        _refreshLinkedNext(shot);
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

  /// 백엔드로 라우팅해 바이트를 받는다. (여기 도달하는 영상 모드는 videoLow=생성뿐)
  /// 이미지(시작/끝 프레임)는 자체 서버 전용 — 참조 인물이 있으면 FireRed(/edit), 없으면 /image.
  /// [backend]는 영상에만 의미 있음. 없으면 설정의 기본 영상 백엔드.
  Future<Uint8List> _generateBytes(
    Shot shot,
    GenMode mode,
    String prompt, [
    VideoBackend? backend,
  ]) async {
    if (!mode.isVideo) {
      final refs = await _refPhotoBytesList(shot);
      if (refs.isNotEmpty) {
        final who = shot.refCharacterIds
            .map((id) => characterById(id)?.name)
            .whereType<String>()
            .where((n) => n.isNotEmpty)
            .join(', ');
        final instruction =
            '아래 참조 인물${who.isEmpty ? '' : '($who)'}을(를) 다음 장면에 자연스럽게 배치하라. '
            '각 인물의 얼굴·헤어스타일·의상 등 정체성은 그대로 유지할 것. 장면: $prompt';
        // ⚠️ /edit(FireRed)은 출력 크기를 못 정한다 — 결과가 참조 사진 크기를 따라간다.
        //    (엔드포인트의 w/h는 '편집할 영역' 크롭용이지 출력 해상도가 아니다.)
        //    imageRes 비율을 맞추려면 서버 /edit에 출력 w/h 지원이 필요하다.
        return ApiService(
          _settings.effectiveServiceUrl,
        ).generateImageWithRefs(references: refs, prompt: instruction);
      }
      final res = _settings.imageRes;
      return ApiService(
        _settings.effectiveServiceUrl,
      ).generateImage(prompt, width: res.width, height: res.height);
    }
    // 영상 생성(저) = FE2V: 시작·끝 두 프레임이 입력(둘 다 필수).
    switch (backend ?? _settings.videoBackend) {
      case VideoBackend.veo:
        final start = await _startFrame(shot);
        final end = await _endFrame(shot);
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
        final img = await _startFrameBytes(shot);
        // I2V면 끝 프레임을 아예 안 쓴다(있어도 무시) — 끝은 모델이 자유롭게 만든다.
        final endImg = shot.i2v ? null : await _endFrameBytes(shot);
        if (img == null) {
          throw Exception('시작장면을 먼저 만들어 주세요 (첫 프레임)');
        }
        if (!shot.i2v && endImg == null) {
          throw Exception('끝장면을 먼저 만들어 주세요 (FE2V 마지막 프레임) — '
              '끝 없이 뽑으려면 장면 탭에서 I2V로 바꾸세요');
        }
        final res = _settings.videoRes;
        final sc = sceneOf(shot); // LoRA는 씬 단위
        // 네거티브는 샷 칸이 먼저고, 비어 있으면 설정의 전역 값으로 떨어진다.
        // 둘 다 비면 서버 워크플로에 박힌 기본 네거티브가 쓰인다.
        final neg = (_vnegs[shot.id]?.text ?? shot.videoNegativePrompt).trim();
        return ApiService(_settings.effectiveServiceUrl).generateVideo(
          image: img,
          endImage: endImg,
          prompt: prompt,
          negativePrompt:
              neg.isNotEmpty ? neg : _settings.videoNegativePrompt.trim(),
          width: res.width,
          height: res.height,
          seconds: shot.videoSeconds,
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

  /// 스크린샷(시작·끝 프레임) 생성 해상도(비율 포함) 선택 저장.
  void setImageRes(ImageRes r) {
    _settings = _settings.copyWith(imageRes: r);
    notifyListeners();
    _settingsStore.save(_settings);
  }

  /// 선택 씬의 LoRA URL 저장(같은 씬 샷들끼리 공유, 씬끼리 별개).
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
  // 실제 생성 프롬프트 = [프로젝트 공통] + [씬 공통] + [샷 프롬프트].

  void setSceneCommonPrompt(String v) {
    final sc = selectedScene;
    if (sc == null) return;
    sc.commonPrompt = v;
    save();
  }

  /// 생성에 쓸 최종 프롬프트.
  /// **장면(시작/끝 이미지)에만 씬 공통을 앞에 붙인다.** 영상은 붙이지 않는다 —
  /// 세계관·복장·룩은 이미 두 장의 프레임이 들고 있고, 거기에 공통 블록까지 얹으면
  /// 짧게 쓴 모션 지시가 묻혀 동작이 엉킨다(실측).
  String _composePrompt(Shot shot, String shotPrompt, GenMode mode) {
    if (mode == GenMode.videoLow) return shotPrompt.trim();
    final sc = sceneOf(shot);
    // 씬 공통과 샷 프롬프트는 빈 줄로 확실히 구분한다 — 쉼표로 이으면 문장 경계가
    // 뭉개져 어디까지가 공통 블록인지 모델도 사람도 못 가른다.
    return [
      (sc?.commonPrompt ?? '').trim(),
      shotPrompt.trim(),
    ].where((e) => e.isNotEmpty).join('\n\n');
  }

  /// 복사 버튼용 — 이 프레임이 생성에 실제로 쓰는 최종 프롬프트(씬 공통 포함).
  /// 조립 규칙이 바뀌면 [_composePrompt] 한 곳만 고치면 되도록 그대로 태운다.
  String composedFramePrompt(Shot shot, String shotPrompt, GenMode mode) =>
      _composePrompt(shot, shotPrompt, mode);

  // ───────── 인물 참조(샷 화면의 캐릭터 레퍼런스) ─────────

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

  /// 이 샷의 참조 인물 토글(있으면 제거, 없으면 추가 · 최대 3).
  void toggleShotRefCharacter(Shot shot, String id) {
    if (shot.refCharacterIds.contains(id)) {
      shot.refCharacterIds.remove(id);
    } else if (shot.refCharacterIds.length < 3) {
      shot.refCharacterIds.add(id);
    }
    notifyListeners();
    save();
  }

  /// 참조 인물들의 대표사진 바이트(최대 3, 존재하는 것만). 없으면 빈 리스트 → 일반 t2i.
  Future<List<Uint8List>> _refPhotoBytesList(Shot shot) async {
    final out = <Uint8List>[];
    for (final id in shot.refCharacterIds.take(3)) {
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

  /// 배경음을 기존 오디오 파일에서 불러온다(기본 동선 — 생성은 부가).
  /// 고른 파일을 프로젝트 폴더로 복사해 씬 BGM으로 삼는다.
  Future<void> loadBgm() async {
    final sc = selectedScene;
    if (sc == null) return;
    const typeGroup = fs.XTypeGroup(
      label: 'audio',
      extensions: ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'],
    );
    final picked = await fs.openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    final key = bgmBusyKey(sc.id);
    _busy.add(key);
    notifyListeners();
    try {
      final ext = picked.name.split('.').last.toLowerCase();
      final f = File('$projectDirPath/${sc.id}_bgm.$ext');
      await f.writeAsBytes(await picked.readAsBytes());
      // 확장자가 바뀌면 옛 파일이 남으므로 정리(같은 씬의 다른 확장자 bgm).
      for (final e in Directory(projectDirPath).listSync().whereType<File>()) {
        final n = e.uri.pathSegments.last;
        if (n.startsWith('${sc.id}_bgm.') && e.path != f.path) {
          await e.delete();
        }
      }
      sc.bgmPath = f.path;
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
    } catch (e, st) {
      debugPrint('[loadBgm] $key 실패: $e\n$st');
      messenger?.call('배경음 불러오기 실패: $e');
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
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
      final bytes = await ApiService(
        _settings.effectiveServiceUrl,
      ).generateBgm(prompt: prompt, seconds: sc.bgmSeconds);
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

  /// 샷이 속한 씬 찾기(씬 → 대사 → 샷 탐색).
  StoryScene? sceneOf(Shot shot) {
    for (final sc in _scenes) {
      for (final beat in sc.dialogues) {
        if (beat.shots.contains(shot)) return sc;
      }
    }
    return null;
  }

  Future<({List<int> bytes, String mimeType})?> _startFrame(
    Shot shot,
  ) async {
    final path = startPathOf(shot); // 연동 중이면 앞 샷의 끝장면
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return (bytes: await f.readAsBytes(), mimeType: 'image/png');
  }

  Future<({List<int> bytes, String mimeType})?> _endFrame(
    Shot shot,
  ) async {
    final path = shot.endImagePath;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return (bytes: await f.readAsBytes(), mimeType: 'image/png');
  }

  /// 샷의 생성물 하나(시작 프레임 · 끝 프레임 · 영상)를 지운다 — 파일까지 삭제.
  /// 다른 샷이 같은 파일을 참조할 수 있으므로(FE 체이닝은 **복사**본을 쓴다) 여기선
  /// 이 샷 소유 파일만 지운다.
  Future<void> removeMedia(Shot shot, GenMode mode) async {
    final path = switch (mode) {
      GenMode.imageStart => shot.startImagePath,
      GenMode.imageEnd => shot.endImagePath,
      GenMode.videoLow => shot.videoPath,
    };
    if (path == null) return;
    switch (mode) {
      case GenMode.imageStart:
        shot.startImagePath = null;
      case GenMode.imageEnd:
        shot.endImagePath = null;
      case GenMode.videoLow:
        shot.videoPath = null;
    }
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
      await FileImage(f).evict();
    } catch (e) {
      debugPrint('[removeMedia] 파일 삭제 실패(참조는 이미 끊음): $e');
    }
    final k = busyKey(shot.id, mode);
    _ver[k] = (_ver[k] ?? 0) + 1;
    notifyListeners();
    await save();
  }

  /// 트림 결과를 반영한다 — 파일은 이미 [VideoEdit.trim]이 덮어썼고, 여기서는 상태만 맞춘다.
  /// 잘린 만큼 샷 길이도 줄어드니 [Shot.videoSeconds]를 실제 길이로 맞춘다(1~15 정수 모델이라
  /// 반올림된다). 미리보기는 경로가 같으므로 _ver을 올려 캐시를 무효화해야 갱신된다.
  Future<void> applyTrim(Shot shot, double seconds) async {
    shot.videoSeconds = seconds.round().clamp(1, 15);
    final k = busyKey(shot.id, GenMode.videoLow);
    _ver[k] = (_ver[k] ?? 0) + 1;
    notifyListeners();
    await save();
  }

  /// 선택 씬의 **생성물 전부**(모든 샷의 시작·끝 프레임 + 영상, 씬 배경음, 대사 음성)를 지운다.
  /// 프롬프트·제목·구조는 그대로 두고 미디어만 비운다 — 다시 뽑기 전 초기화용.
  /// 지운 개수를 돌려준다.
  Future<int> removeSceneMedia() async {
    final scene = selectedScene;
    if (scene == null) return 0;
    var n = 0;
    Future<void> kill(String? path) async {
      if (path == null) return;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
        await FileImage(f).evict();
      } catch (e) {
        debugPrint('[removeSceneMedia] 삭제 실패(참조는 끊음): $e');
      }
      n++;
    }

    for (final beat in scene.dialogues) {
      for (final shot in beat.shots) {
        await kill(shot.startImagePath);
        await kill(shot.endImagePath);
        await kill(shot.videoPath);
        shot.startImagePath = null;
        shot.endImagePath = null;
        shot.videoPath = null;
        for (final m in GenMode.values) {
          final k = busyKey(shot.id, m);
          _ver[k] = (_ver[k] ?? 0) + 1;
        }
      }
      final d = beat.dialogue;
      if (d != null) {
        await kill(d.voicePath);
        d.voicePath = null;
        d.voiceSeconds = 0;
        final k = voiceBusyKey(beat.id);
        _ver[k] = (_ver[k] ?? 0) + 1;
      }
    }
    await kill(scene.bgmPath);
    scene.bgmPath = null;
    final bk = bgmBusyKey(scene.id);
    _ver[bk] = (_ver[bk] ?? 0) + 1;

    notifyListeners();
    await save();
    return n;
  }

  /// [srcPath]의 이미지를 [target]의 **시작 프레임**으로 복사해 같은 프레임으로 맞춘다.
  /// 성공하면 true. (FE2V 컷 연속성 양방향의 공통 부분.)
  /// [shot]이 속한 씬의 샷 전체를 순서대로(대사 경계 무시). [sceneShots]와 달리
  /// **선택된 씬이 아니라 그 샷의 씬**을 본다 — 일괄 생성은 안 열어 본 씬도 훑는다.
  List<Shot> _shotsAround(Shot shot) {
    final scene = sceneOf(shot);
    if (scene == null) return const [];
    return [for (final beat in scene.dialogues) ...beat.shots];
  }

  /// 씬 나열 기준 [shot]의 바로 앞 샷 — 없으면(첫 샷) null. 대사 경계는 건너뛴다.
  /// 시작장면 연동이 무엇을 물려받는지 UI가 보여줘야 해서 공개돼 있다.
  Shot? prevShotOf(Shot shot) {
    final all = _shotsAround(shot);
    final i = all.indexOf(shot);
    return i <= 0 ? null : all[i - 1];
  }

  /// 이 샷의 시작장면 이미지 경로 — **연동 중이면 앞 샷의 끝장면 그 자체**다.
  /// 복사본을 두지 않으므로 앞 샷의 끝이 바뀌면 즉시 따라오고, 지워지면 같이 없어진다
  /// (그게 사실이다 — 이어받을 게 없어진 것이니 '준비 안 됨'으로 잡히는 게 맞다).
  ///
  /// 시작장면을 읽는 쪽은 [Shot.startImagePath] 대신 **전부 이걸** 써야 한다.
  String? startPathOf(Shot shot) => shot.linkStart
      ? prevShotOf(shot)?.endImagePath
      : shot.startImagePath;

  /// 시작장면 연동 켜기/끄기.
  ///
  /// 켤 때: 플래그만 세우면 된다 — 이미지는 [startPathOf]가 앞 샷에서 바로 읽는다.
  /// 직접 만들어 둔 시작 이미지는 지우지 않고 남겨둔다(끄면 그대로 돌아온다).
  ///
  /// 끌 때: 직접 만들어 둔 게 없으면 지금 보고 있던 앞 샷의 끝을 자기 파일로 굳혀준다 —
  /// 끄자마자 프레임이 사라지면 당황스럽다.
  Future<void> setLinkStart(Shot shot, bool on) async {
    if (on && prevShotOf(shot) == null) return; // 첫 샷은 물려받을 앞이 없다
    if (!on && shot.linkStart && shot.startImagePath == null) {
      await _materializeStart(shot);
    }
    shot.linkStart = on;
    _ver[busyKey(shot.id, GenMode.imageStart)] =
        (_ver[busyKey(shot.id, GenMode.imageStart)] ?? 0) + 1;
    await save(); // 프롬프트 연동이 여기서 걸리므로 알리기 전에 저장한다
    notifyListeners();
  }

  /// 영상 생성 방식 전환 — I2V(시작 한 장) ↔ FE2V(시작+끝).
  /// 끝장면 파일은 지우지 않는다: I2V로 뽑아보고 되돌릴 수 있어야 한다.
  Future<void> setI2v(Shot shot, bool on) async {
    if (shot.i2v == on) return;
    shot.i2v = on;
    await save();
    notifyListeners();
  }

  /// 연동을 끊을 때: 앞 샷의 끝장면을 이 샷의 시작 파일로 복사해 남긴다.
  Future<void> _materializeStart(Shot shot) async {
    final srcPath = prevShotOf(shot)?.endImagePath;
    if (srcPath == null) return;
    final src = File(srcPath);
    if (!await src.exists()) return;
    final dst = File('$projectDirPath/${shot.id}_start.${srcPath.split('.').last}');
    await src.copy(dst.path);
    await FileImage(dst).evict();
    shot.startImagePath = dst.path;
  }

  /// FE2V 컷 연속성: [shot]의 끝 프레임이 바뀌면 **다음 샷의 시작**도 바뀐 셈이다
  /// (연동 중이라면 그 시작이 곧 이 끝 파일이므로 — [startPathOf] 참고).
  /// 경로가 그대로라 미리보기 캐시가 옛 그림을 붙들고 있으니 버전만 올려 깨워준다.
  void _refreshLinkedNext(Shot shot) {
    final all = _shotsAround(shot);
    final i = all.indexOf(shot);
    if (i < 0 || i + 1 >= all.length) return; // 마지막 샷 → 이어질 대상 없음
    final next = all[i + 1];
    if (!next.linkStart) return;
    final k = busyKey(next.id, GenMode.imageStart);
    _ver[k] = (_ver[k] ?? 0) + 1;
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

  Future<Uint8List?> _startFrameBytes(Shot shot) async {
    final path = startPathOf(shot); // 연동 중이면 앞 샷의 끝장면
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  Future<Uint8List?> _endFrameBytes(Shot shot) async {
    final path = shot.endImagePath;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  String _extFor(Uint8List b, GenMode mode) {
    if (!mode.isVideo) return 'png';
    final isWebp =
        b.length > 12 &&
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

  /// 파일이 저장된 폴더를 Finder에서 연다(해당 파일이 선택된 채로).
  /// 프로젝트 폴더가 샌드박스 컨테이너 깊숙이 있어 손으로 찾기 어려우므로 필요하다.
  Future<void> revealInFinder(String path) async {
    try {
      await Process.run('open', ['-R', path]);
    } catch (e) {
      messenger?.call('폴더 열기 실패: $e');
    }
  }

  /// 프로젝트 폴더 자체를 Finder에서 연다(생성물이 하나도 없어도 열린다).
  Future<void> openProjectFolder() async {
    try {
      await Process.run('open', [projectDirPath]);
    } catch (e) {
      messenger?.call('폴더 열기 실패: $e');
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

  /// 선택 씬의 클립을 샷 순서대로 하나의 mp4로 이어붙여 내보낸다(씬 무비).
  /// 영상이 없는 샷은 건너뛰고, 몇 개를 건너뛰었는지 알려준다.
  Future<void> exportSceneMovie() async {
    final sc = selectedScene;
    if (sc == null) return;
    if (!VideoEdit.available) {
      messenger?.call(VideoEdit.missingHint);
      return;
    }
    final all = sceneShots;
    final clips = <String>[
      for (final s in all)
        if (s.videoPath != null && File(s.videoPath!).existsSync()) s.videoPath!,
    ];
    if (clips.isEmpty) {
      messenger?.call('이 씬에는 생성된 영상이 없습니다');
      return;
    }
    // 파일명에 못 쓰는 문자만 걸러낸 씬 제목을 기본 이름으로.
    final title = sc.title.trim().isEmpty ? sc.id : sc.title.trim();
    final safe = title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    final loc = await fs.getSaveLocation(suggestedName: '$safe.mp4');
    if (loc == null) return;
    messenger?.call('씬 무비 합치는 중… (${clips.length}클립)');
    try {
      await VideoEdit.concat(clips, loc.path);
      final skipped = all.length - clips.length;
      messenger?.call('씬 무비 저장: ${loc.path}'
          '${skipped > 0 ? ' (영상 없는 $skipped샷 제외)' : ''}');
    } catch (e, st) {
      debugPrint('[sceneMovie] 실패: $e\n$st');
      messenger?.call('씬 무비 실패: $e');
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
    for (final c in _dialogueTitles.values) {
      c.dispose();
    }
    for (final c in _notes.values) {
      c.dispose();
    }
    for (final c in _directions.values) {
      c.dispose();
    }
    for (final c in _startPrompts.values) {
      c.dispose();
    }
    for (final c in _startPromptKos.values) {
      c.dispose();
    }
    for (final c in _endPrompts.values) {
      c.dispose();
    }
    for (final c in _endPromptKos.values) {
      c.dispose();
    }
    for (final c in _vprompts.values) {
      c.dispose();
    }
    for (final c in _vpromptKos.values) {
      c.dispose();
    }
    for (final c in _vnegs.values) {
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

/// 씬 일괄 영상 생성 계획 — [StoryboardProvider.sceneVideoPlan]이 돌려준다.
/// 생성을 누르기 **전에** 무엇이 돌고 무엇이 빠지는지 보여주기 위한 스냅샷이다.
class SceneVideoPlan {
  const SceneVideoPlan(this.ready, this.blocked, this.skipped);

  /// 지금 바로 생성 가능한 샷들.
  final List<Shot> ready;

  /// 재료가 모자라 못 도는 샷들 — 경고로 띄운다.
  final List<BlockedShot> blocked;

  /// 이미 영상이 있어 건너뛸 샷들(건너뛰기 토글이 켜졌을 때만 채워진다).
  final List<Shot> skipped;

  bool get isEmpty => ready.isEmpty && blocked.isEmpty && skipped.isEmpty;
}

/// 재료가 빠져 생성할 수 없는 샷 하나와 그 이유.
class BlockedShot {
  const BlockedShot(this.shot, this.label, this.missing);

  final Shot shot;
  final String label; // '샷 3' 처럼 사람이 알아볼 이름
  final List<String> missing; // 예: ['끝장면', '영상 프롬프트']
}
