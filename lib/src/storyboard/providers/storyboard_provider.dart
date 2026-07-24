import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:framework/framework.dart';
// 불러온 오디오 길이 실측용. Caption은 우리 모델과 이름이 겹쳐 숨긴다.
import 'package:video_player/video_player.dart' hide Caption;

import '../models/character.dart';
import '../models/shot.dart';
import '../models/dialogue.dart';
import '../models/dialogue_beat.dart';
import '../models/sfx.dart';
import '../models/caption.dart';
import '../models/story_scene.dart';
import '../models/video_track.dart';
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
  final Map<String, TextEditingController> _shotNotes = {};
  final Map<String, TextEditingController> _videoNotes = {};
  final Map<String, TextEditingController> _sceneNotes = {};
  final Set<String> _busy = {}; // '<shotId>:<mode>' 또는 '<dialogueId>:voice' 등 진행 중
  final Map<String, String> _progress = {}; // 진행 중 상태 문구(busyKey별) — 영상칸에 고정 표시
  final Map<String, int> _ver = {}; // 미리보기 캐시 버전

  List<StoryScene> _scenes = []; // 씬 리스트
  String? _selectedSceneId;
  int _trackIndex = 0; // 보고 있는 트랙(씬이 바뀌어도 유지 — 트랙끼리 구조가 같으므로)
  String? _selectedDialogueId; // 선택된 샷(비트)
  String? _selectedShotId; // 선택된 샷(선택 대사 안에서)
  int _seq = 0;
  String? _savePath;

  // 사이드/플레이어 토글. 씬목록은 기본으로 펼쳐둔다(씬 이동이 주 동선).
  bool _sceneListOpen = true;

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

  /// 스틸컷은 서버·키가 필요 없다 — 로컬 ffmpeg만 있으면 된다.
  bool get stillReady => VideoEdit.available;
  String? get stillBlockReason => stillReady ? null : VideoEdit.missingHint;

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

  // ───────── 트랙(같은 콘티를 백엔드별로 뽑아 비교) ─────────

  /// 선택 씬의 트랙들(첫 번째가 기준 트랙).
  List<VideoTrack> get tracks => selectedScene?.tracks ?? const [];

  /// 보고 있는 트랙의 번호(0=기준). 씬마다 트랙 수가 다를 수 있어 범위를 잘라 읽는다.
  int get trackIndex {
    final n = tracks.length;
    if (n == 0) return 0;
    return _trackIndex.clamp(0, n - 1);
  }

  /// 보고 있는 트랙 — 캔버스·인스펙터·플레이어가 전부 이 트랙을 그린다.
  VideoTrack? get selectedTrack {
    final sc = selectedScene;
    if (sc == null) return null;
    return sc.tracks[trackIndex];
  }

  /// 기준 트랙을 보고 있는지 — 비트·샷 추가/삭제는 여기서만 된다(구조는 트랙끼리 같아야 하므로).
  bool get onBaseTrack => trackIndex == 0;

  /// 씬의 구조(기준 트랙의 비트들) — 캔버스가 카드 한 장씩 그리는 단위.
  /// 카드 안에서는 트랙마다 같은 자리의 비트를 찾아 샷 줄을 쌓는다([beatAt]).
  List<DialogueBeat> get baseBeats => selectedScene?.beats ?? const [];

  /// [track]에서 [index]번째 비트(없으면 null). 트랙끼리 구조가 같으므로 자리로 짝을 짓는다.
  DialogueBeat? beatAt(VideoTrack track, int index) =>
      index < track.beats.length ? track.beats[index] : null;

  /// 선택된 비트가 몇 번째 자리인지 — 카드 강조에 쓴다(어느 트랙의 비트든 같은 자리).
  int? get selectedBeatIndex {
    final sc = selectedScene;
    return sc == null ? null : _indexOfSelectedBeat(sc);
  }

  void selectTrack(int i) {
    if (i < 0 || i >= tracks.length || i == trackIndex) return;
    _trackIndex = i;
    // 선택은 트랙마다 다른 객체다 — 같은 자리(기준 id)의 비트·샷으로 옮겨 준다.
    _carrySelectionToTrack();
    notifyListeners();
  }


  /// 트랙을 바꿔도 **보고 있던 자리를 유지**한다 — 트랙끼리 구조가 같으니 같은 순서의
  /// 비트·샷을 다시 고르면 된다(비교하려고 왔다 갔다 하는 게 주 동선이라 자리가 튀면 곤란).
  void _carrySelectionToTrack() {
    final sc = selectedScene;
    if (sc == null) return;
    final beatIdx = _indexOfSelectedBeat(sc);
    final beats = sc.tracks[trackIndex].beats;
    if (beatIdx == null || beatIdx >= beats.length) {
      _selectedDialogueId = beats.isNotEmpty ? beats.first.id : null;
      _selectedShotId = null;
      return;
    }
    final beat = beats[beatIdx];
    final shotIdx = _selectedShotIndexIn(sc, beatIdx);
    _selectedDialogueId = beat.id;
    _selectedShotId = (shotIdx != null && shotIdx < beat.shots.length)
        ? beat.shots[shotIdx].id
        : null;
  }

  /// 선택된 비트가 (어느 트랙에서든) 몇 번째인지.
  int? _indexOfSelectedBeat(StoryScene sc) {
    for (final t in sc.tracks) {
      final i = t.beats.indexWhere((b) => b.id == _selectedDialogueId);
      if (i >= 0) return i;
    }
    return null;
  }

  int? _selectedShotIndexIn(StoryScene sc, int beatIdx) {
    for (final t in sc.tracks) {
      if (beatIdx >= t.beats.length) continue;
      final i = t.beats[beatIdx].shots.indexWhere((s) => s.id == _selectedShotId);
      if (i >= 0) return i;
    }
    return null;
  }

  /// 트랙 추가 — 기준 트랙 구조를 그대로 비추는 빈 트랙. **아무것도 안 건드리면 트랙 1과 똑같이
  /// 보이고**, 영상만 비어 있다. 백엔드는 아직 안 쓴 것 하나를 골라 준다(비교가 목적이므로).
  Future<void> addTrack() async {
    final sc = selectedScene;
    if (sc == null) return;
    // 백엔드는 **기준 트랙과 같은 것으로** 시작한다 — 무엇으로 뽑을지는 사람이 정할 일이고,
    // 말없이 다른 백엔드를 물려 두면 자기도 모르게 그쪽으로 생성이 나간다.
    final track = VideoTrack(
      id: _newId('track'),
      name: '트랙 ${sc.tracks.length + 1}',
      backend: sc.baseTrack.backend,
    );
    sc.tracks.add(track);
    _syncTracks(sc); // 기준 구조를 비추는 비트·샷을 여기서 만들어 붙인다
    _trackIndex = sc.tracks.length - 1;
    _carrySelectionToTrack();
    notifyListeners();
    await save();
  }

  /// 트랙 삭제 — 기준 트랙(트랙 1)은 지울 수 없다(구조의 정본이라서).
  Future<void> removeTrack(VideoTrack track) async {
    final sc = selectedScene;
    if (sc == null || sc.tracks.length <= 1) return;
    if (identical(track, sc.baseTrack)) return;
    sc.tracks.remove(track);
    for (final beat in track.beats) {
      _disposeDialogueControllers(beat.id);
      for (final shot in beat.shots) {
        _disposeShotControllers(shot.id);
      }
    }
    _trackIndex = _trackIndex.clamp(0, sc.tracks.length - 1);
    _carrySelectionToTrack();
    notifyListeners();
    await save();
    _sweepAfterDelete(); // 지운 트랙에서 뽑은 영상 정리(기준 트랙 공유 프레임은 참조가 남아 보존)
  }

  void setTrackName(VideoTrack track, String name) {
    track.name = name.trim();
    notifyListeners();
    save();
  }

  void setTrackBackend(VideoTrack track, VideoBackend b) {
    track.backend = b;
    notifyListeners();
    save();
  }

  /// 트랙 표시 이름 — 비어 있으면 순서로 부른다.
  String trackLabel(VideoTrack t) {
    if (t.name.trim().isNotEmpty) return t.name.trim();
    final i = tracks.indexOf(t);
    return '트랙 ${i < 0 ? '?' : i + 1}';
  }

  /// 이 샷이 속한 트랙(어느 씬이든).
  VideoTrack? trackOf(Shot shot) {
    for (final sc in _scenes) {
      for (final t in sc.tracks) {
        for (final beat in t.beats) {
          if (beat.shots.contains(shot)) return t;
        }
      }
    }
    return null;
  }

  /// 파생 트랙 샷이 따라가고 있는 **기준 트랙의 짝**. 기준 트랙 샷이면 null.
  Shot? baseShotOf(Shot shot) {
    final baseId = shot.baseId;
    if (baseId == null) return null;
    final sc = sceneOf(shot);
    if (sc == null) return null;
    for (final beat in sc.baseTrack.beats) {
      for (final s in beat.shots) {
        if (s.id == baseId) return s;
      }
    }
    return null;
  }

  /// 파생 트랙의 비트가 따라가고 있는 기준 비트.
  DialogueBeat? baseBeatOf(DialogueBeat beat) {
    final baseId = beat.baseId;
    if (baseId == null) return null;
    final sc = sceneOf2(beat);
    if (sc == null) return null;
    for (final b in sc.baseTrack.beats) {
      if (b.id == baseId) return b;
    }
    return null;
  }

  // ───────── 파생 트랙 상속(borrow) ─────────
  // 파생 트랙은 track1을 **전 필드 상속**한다: 자기 것이 있으면 그것, 없으면 기준 트랙 것을
  // 그대로 해석해 보여 준다. 손대(생성/편집)면 그 필드만 자기 것으로 채워진다.

  /// 이 샷 자리에 **보여 줄** 영상 — 자기 트랙에서 뽑았으면 그것, 없으면 기준 트랙 것 상속.
  String? videoPathOf(Shot c) =>
      c.videoPath ?? (c.isDerived ? baseShotOf(c)?.videoPath : null);

  /// 이 샷이 **자기 트랙에서 실제로 뽑은** 영상을 가졌는지(상속만 하는 중이 아닌지).
  bool hasOwnVideo(Shot c) => c.videoPath != null;

  /// 보여 줄 영상의 실제 길이 — 자기 것이면 자기 실측, 상속 중이면 기준 것.
  double? videoActualSecondsOf(Shot c) => c.videoPath != null
      ? c.videoActualSeconds
      : (c.isDerived ? baseShotOf(c)?.videoActualSeconds : null);

  /// 캔버스·타임라인에 **보여 줄 길이(초)** — 화면에 실제로 걸린 영상(자기 것이든 상속이든)의
  /// 실측 길이. 실측이 없거나 0이면(아직 못 쟀거나 측정 실패) 주문한 길이로 떨어진다 — 0초로
  /// 표시되지 않게. (0초로 뜨던 버그: 상속 영상은 실측이 자기 필드에 없어 0/주문값이 섞였다.)
  double shotDisplaySeconds(Shot c) {
    final actual = videoActualSecondsOf(c);
    if (actual != null && actual > 0) return actual;
    return shotVideoSeconds(c); // 주문 길이(파생은 상속/오버라이드 해석)
  }

  /// 이 비트 자리에 **들려 줄** 대사 음성 — 자기 것이 있으면 그것, 없으면 기준 트랙 것 상속.
  String? voicePathOf(DialogueBeat b) =>
      b.dialogue?.voicePath ??
      (b.isDerived ? baseBeatOf(b)?.dialogue?.voicePath : null);

  /// 들려 줄 음성의 길이(초) — 자기 것 우선, 없으면 기준 것.
  double voiceSecondsOf(DialogueBeat b) {
    final own = b.dialogue?.voiceSeconds ?? 0;
    if (own > 0) return own;
    return b.isDerived ? (baseBeatOf(b)?.dialogue?.voiceSeconds ?? 0) : 0;
  }

  /// 이 비트가 **자기 트랙에서 만든** 음성을 가졌는지(상속만 하는 중이 아닌지).
  bool hasOwnVoice(DialogueBeat b) => b.dialogue?.hasVoice ?? false;

  /// 이 비트가 자리에 들려 줄 음성이 있는지(자기 것이든 상속이든).
  bool hasAnyVoice(DialogueBeat b) => voicePathOf(b) != null;

  // ───────── 대본·연출 리졸버(비트) — 파생 비트는 overrides에 있으면 그 값, 없으면 기준 비트 ─────────

  String beatTitle(DialogueBeat b) => b.resolvedTitle(baseBeatOf(b));
  String beatNote(DialogueBeat b) => b.resolvedNote(baseBeatOf(b));
  String beatDirection(DialogueBeat b) => b.resolvedDirection(baseBeatOf(b));

  /// 이 비트 자리에 **보여 줄 대본**(화자·텍스트). null = 무음 대사.
  ({String? speakerId, String text})? beatScript(DialogueBeat b) =>
      b.resolvedScript(baseBeatOf(b));

  // ───────── 효과음(SFX) — 트랙별 오버라이드(파생은 자기 것, 없으면 기준 비트 상속) ─────────

  /// 이 비트 자리에 들려 줄 효과음. 없으면 null.
  Sfx? sfxOf(DialogueBeat b) => b.resolvedSfx(baseBeatOf(b));
  String? sfxPathOf(DialogueBeat b) => sfxOf(b)?.path;
  bool hasSfx(DialogueBeat b) => sfxOf(b)?.hasSound ?? false;

  /// 효과음 진행/캐시 키 — 효과음이 트랙별 소유이므로 **그 비트 id** 기준.
  String sfxBusyKey(String beatId) => '$beatId:sfx';

  // ───────── 자막(캡션) — 효과음처럼 트랙별 오버라이드 ─────────

  Caption? captionOf(DialogueBeat b) => b.resolvedCaption(baseBeatOf(b));

  // ───────── 샷 필드 리졸버 — 파생 샷은 overrides에 있으면 그 값, 없으면 기준 샷 ─────────

  String shotTitle(Shot s) => s.resolvedTitle(baseShotOf(s));
  List<String> shotRefCharacterIds(Shot s) =>
      s.resolvedRefCharacterIds(baseShotOf(s));
  String shotStartPrompt(Shot s) => s.resolvedStartPrompt(baseShotOf(s));
  String shotStartPromptKo(Shot s) => s.resolvedStartPromptKo(baseShotOf(s));
  String shotEndPrompt(Shot s) => s.resolvedEndPrompt(baseShotOf(s));
  String shotEndPromptKo(Shot s) => s.resolvedEndPromptKo(baseShotOf(s));
  String shotVideoPrompt(Shot s) => s.resolvedVideoPrompt(baseShotOf(s));
  String shotVideoPromptKo(Shot s) => s.resolvedVideoPromptKo(baseShotOf(s));
  String shotVideoNeg(Shot s) => s.resolvedVideoNeg(baseShotOf(s));
  double shotVideoSeconds(Shot s) => s.resolvedVideoSeconds(baseShotOf(s));
  String? shotStartImage(Shot s) => s.resolvedStartImage(baseShotOf(s));
  String? shotEndImage(Shot s) => s.resolvedEndImage(baseShotOf(s));
  bool shotLinkStart(Shot s) => s.resolvedLinkStart(baseShotOf(s));
  VideoMode shotVideoMode(Shot s) => s.resolvedVideoMode(baseShotOf(s));
  StillEffect shotStillEffect(Shot s) => s.resolvedStillEffect(baseShotOf(s));
  String shotNote(Shot s) => s.resolvedNote(baseShotOf(s));
  String shotVideoNote(Shot s) => s.resolvedVideoNote(baseShotOf(s));

  /// 끝 프레임이 필요한 방식(FE2V)인지 — 상속/오버라이드 해석.
  bool shotNeedsEndFrame(Shot s) => shotVideoMode(s) == VideoMode.fe2v;

  /// 비트의 실제 길이(초) = 샷 재생 길이 합. (파생 비트도 자기 샷 목록으로 계산)
  double beatSeconds(DialogueBeat b) =>
      b.shots.fold(0.0, (a, s) => a + shotDisplaySeconds(s));

  /// 음성(목표) 대비 남는/모자란 시간(초). 양수=영상 김, 음수=영상 짧음. 음성 없으면 null.
  double? beatCoverageGap(DialogueBeat b) {
    final target = voiceSecondsOf(b);
    return target > 0 ? beatSeconds(b) - target : null;
  }

  /// 이 비트가 속한 씬.
  StoryScene? sceneOf2(DialogueBeat beat) {
    for (final sc in _scenes) {
      for (final t in sc.tracks) {
        if (t.beats.contains(beat)) return sc;
      }
    }
    return null;
  }

  // ── 오버라이드 쓰기 헬퍼: 파생이면 overrides에, 기준이면 타입 필드에 쓴다 ──

  /// 파생 비트의 문자열 필드를 플러시 — 기준과 같으면 상속(키 제거), 다르면 오버라이드.
  void _flushBeatStr(
      DialogueBeat beat, String key, String? text, String baseVal) {
    if (text == null) return;
    if (text == baseVal) {
      beat.overrides.remove(key);
    } else {
      beat.overrides[key] = text;
    }
  }

  /// 파생 샷의 문자열 필드를 플러시 — 기준과 같으면 상속(키 제거), 다르면 오버라이드.
  void _flushShotStr(Shot shot, String key, String? text, String baseVal) {
    if (text == null) return;
    if (text == baseVal) {
      shot.overrides.remove(key);
    } else {
      shot.overrides[key] = text;
    }
  }

  /// 샷의 비-텍스트 필드를 설정 — 파생이면 overrides에, 기준이면 setBase()로 타입 필드에.
  void _setShotField(
      Shot shot, String key, Object? value, void Function() setBase) {
    if (shot.isDerived) {
      shot.overrides[key] = value;
    } else {
      setBase();
    }
  }

  /// 시작/끝 프레임 경로 설정 — 파생이면 그 프레임만 이 트랙 것으로 오버라이드된다.
  void _setShotStartImage(Shot shot, String? path) =>
      _setShotField(shot, Shot.kStartImage, path, () => shot.startImagePath = path);
  void _setShotEndImage(Shot shot, String? path) =>
      _setShotField(shot, Shot.kEndImage, path, () => shot.endImagePath = path);

  // ───────── 트랙 구조 미러링(값 복사 없음) ─────────

  /// 파생 트랙들을 기준 트랙 **구조(비트·샷 개수·순서)에만** 맞춘다 — 값은 복사하지 않는다.
  /// 기준에 있는 비트/샷을 파생에도 같은 자리에 두고(없으면 빈 파생을 끼운다), 기준에서
  /// 사라진 것은 파생에서도 걷어낸다. 파생의 overrides·자기 음성·자기 영상은 손대지 않는다.
  /// 불러온 직후·구조가 바뀐 뒤·저장 직전에 부른다.
  void _syncTracks(StoryScene scene) {
    final base = scene.baseTrack;
    for (var i = 1; i < scene.tracks.length; i++) {
      _syncTrack(base, scene.tracks[i]);
    }
  }

  void _syncTrack(VideoTrack base, VideoTrack track) {
    // 기준 id로 짝을 찾는다 — 순서가 바뀌어도 뽑아 둔 영상·오버라이드가 엉뚱한 자리에 안 붙게.
    final oldBeats = {for (final b in track.beats) b.baseId ?? b.id: b};
    final beats = <DialogueBeat>[];
    for (final baseBeat in base.beats) {
      final beat = oldBeats.remove(baseBeat.id) ?? _mirrorBeat(baseBeat);
      final oldShots = {for (final s in beat.shots) s.baseId ?? s.id: s};
      final shots = <Shot>[];
      for (final baseShot in baseBeat.shots) {
        shots.add(oldShots.remove(baseShot.id) ?? _mirrorShot(baseShot));
      }
      for (final gone in oldShots.values) {
        _disposeShotControllers(gone.id); // 기준에서 사라진 샷
      }
      beat.shots = shots;
      beats.add(beat);
    }
    for (final gone in oldBeats.values) {
      _disposeDialogueControllers(gone.id);
      for (final s in gone.shots) {
        _disposeShotControllers(s.id);
      }
    }
    track.beats = beats;
  }

  /// 새 파생 비트 — 진짜로 비어 있다(overrides={}). 편집칸은 기준 값을 시드로 갖고, 편집하면
  /// 그때 overrides가 생긴다.
  DialogueBeat _mirrorBeat(DialogueBeat base) {
    final beat = DialogueBeat(id: _newId('beat'), baseId: base.id);
    _addDialogueControllers(beat, base);
    return beat;
  }

  /// 새 파생 샷 — 진짜로 비어 있다(overrides={}). 편집칸은 기준 값을 시드로 갖는다.
  Shot _mirrorShot(Shot base) {
    final shot = Shot(id: _newId('clip'), baseId: base.id);
    _addShotControllers(shot, base);
    return shot;
  }

  /// 현재 선택 씬의 대사들(캔버스가 타임라인으로 그리는 대상 = 보고 있는 트랙의 비트들).
  List<DialogueBeat> get dialogues => selectedTrack?.beats ?? const [];

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

  /// 선택 씬의 재생 목록 — 영상이 있는 샷만 순서대로 (경로 + 라벨). 영상 팝업 연속 재생용.
  /// 각 항목에 그 샷이 속한 **비트의 음성 경로·비트 id**도 실어, 팝업이 영상과 음성을 함께
  /// 재생하게 한다. 비트가 바뀔 때만 음성을 새로 트도록(1 대사 = 여러 샷) beatId로 구분한다.
  List<
      ({
        String path,
        String title,
        String beatId,
        String? voicePath,
        String? sfxPath,
        List<({double seconds, String text})> captionCues,
        String captionPos,
      })> scenePlaylist() {
    final out = <({
      String path,
      String title,
      String beatId,
      String? voicePath,
      String? sfxPath,
      List<({double seconds, String text})> captionCues,
      String captionPos,
    })>[];
    var n = 0;
    for (final beat in dialogues) {
      final voice = voicePathOf(beat); // 상속 포함(자기 것 없으면 기준 트랙 음성)
      final sfx = sfxPathOf(beat); // 효과음(트랙 공유)
      final cap = captionOf(beat); // 자막(트랙 공유)
      final cues = <({double seconds, String text})>[
        for (final c in cap?.cues ?? const [])
          (seconds: c.seconds, text: c.text),
      ];
      final capPos = (cap?.position ?? CaptionPosition.bottom).name;
      for (final shot in beat.shots) {
        n++;
        final path = videoPathOf(shot); // 상속 포함(자기 것 없으면 기준 트랙 영상)
        if (path == null) continue;
        final t = shotTitle(shot).trim();
        out.add((
          path: path,
          title: t.isEmpty ? '샷 $n' : '샷 $n · $t',
          beatId: beat.id,
          voicePath: voice,
          sfxPath: sfx,
          captionCues: cues,
          captionPos: capPos,
        ));
      }
    }
    return out;
  }

  /// 지금 보고 있는 씬의 배경음(mp3) 경로 — 팝업 재생에 함께 깔 용도. 없으면 null.
  String? get scenePlayBgmPath => selectedScene?.bgmPath;

  /// 미리보기 재생 배속 — **보고 있는 트랙**의 배속(내보내기와 같은 값).
  double get scenePlaySpeed => selectedTrack?.speed ?? 1.0;

  Shot? get selectedShot {
    for (final c in shots) {
      if (c.id == _selectedShotId) return c;
    }
    return null;
  }

  TextEditingController sceneTitleCtrl(String sceneId) =>
      _sceneTitles[sceneId]!;
  // 비트의 글(제목·메모·연출)은 **비트마다 자기 편집칸**을 갖는다 — 파생 비트도 자기 것.
  // 편집칸은 상속 값을 시드로 보여 주다가, 사용자가 고치면 저장 때 그 필드만 overrides로 간다.
  TextEditingController titleCtrl(String dialogueId) =>
      _dialogueTitles[dialogueId]!;
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
  TextEditingController shotNoteCtrl(String shotId) => _shotNotes[shotId]!;
  TextEditingController videoNoteCtrl(String shotId) => _videoNotes[shotId]!;
  TextEditingController sceneNoteCtrl(String sceneId) => _sceneNotes[sceneId]!;

  bool isBusy(String key) => _busy.contains(key);
  int verOf(String key) => _ver[key] ?? 0;

  /// 진행 중 상태 문구(예: '생성 중… 0.4분 경과'). 없으면 null. 영상칸에 고정 표시용.
  String? progressOf(String key) => _progress[key];

  /// 이 씬에서 **뭐든 생성 중**인지 — 씬 목록 아이템 깜빡임용. 어느 트랙·샷이든 프레임/영상/음성이
  /// 도는 중이면 true. busy 키가 곧 진행 중이므로, 이 씬의 id로 시작하는 키가 있는지 본다.
  bool sceneBusy(StoryScene scene) {
    for (final t in scene.tracks) {
      for (final beat in t.beats) {
        if (_busy.contains(voiceBusyKey(beat.id))) return true;
        for (final shot in beat.shots) {
          for (final m in GenMode.values) {
            if (_busy.contains(busyKey(shot.id, m))) return true;
          }
        }
      }
    }
    return _busy.contains(bgmBusyKey(scene.id));
  }

  /// 프로젝트 폴더에서 **아무 데서도 참조하지 않는 미디어 파일**을 지운다(고아 정리).
  /// 삭제(샷·비트·트랙·씬)는 참조만 끊고 파일은 남기므로, 그 뒤 이걸 돌려 실제 파일을 정리한다.
  /// 지금 씬·인물이 실제로 가리키는 파일명만 살리고 나머지 미디어를 지운다 — 지운 개수 반환.
  /// (characters.json 등 json과, 인물 대표·사진은 건드리지 않는다.)
  Future<int> sweepOrphanMedia() async {
    final live = <String>{};
    void keep(String? path) {
      final n = mediaName(path);
      if (n != null) live.add(n);
    }

    for (final sc in _scenes) {
      keep(sc.bgmPath);
      for (final t in sc.tracks) {
        for (final b in t.beats) {
          keep(b.dialogue?.voicePath); // 음성(트랙별 소유)
          // 효과음 — 기준 비트는 타입 필드, 파생 비트는 overrides에 있다.
          keep((b.isDerived ? b.overrides[DialogueBeat.kSfx] as Sfx? : b.sfx)
              ?.path);
          for (final s in b.shots) {
            // 프레임 — 파생 샷은 오버라이드한 것만 자기 파일(상속 중이면 기준 트랙 것을 이미 살림).
            if (s.isDerived) {
              keep(s.overrides[Shot.kStartImage] as String?);
              keep(s.overrides[Shot.kEndImage] as String?);
            } else {
              keep(s.startImagePath);
              keep(s.endImagePath);
            }
            keep(s.videoPath); // 영상은 트랙별 소유
          }
        }
      }
    }
    // 인물 미디어도 살린다 — 씬과 무관하게 같은 폴더에 있다.
    for (final c in _characters) {
      keep(c.cover);
      for (final ph in c.photoPaths) {
        keep(ph);
      }
    }

    const mediaExt = {
      '.png', '.jpg', '.jpeg', '.webp', //
      '.mp4', '.mov', '.m4v', '.webm', //
      '.mp3', '.wav', '.m4a', '.aac', '.flac', '.ogg',
    };
    final dir = Directory(projectDirPath);
    if (!await dir.exists()) return 0;
    var n = 0;
    try {
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        final dot = name.lastIndexOf('.');
        final ext = dot < 0 ? '' : name.substring(dot).toLowerCase();
        if (!mediaExt.contains(ext)) continue; // json 등은 손대지 않는다
        if (live.contains(name)) continue;
        try {
          await e.delete();
          await FileImage(File(e.path)).evict();
          n++;
        } catch (err) {
          debugPrint('[sweepOrphan] 삭제 실패: $err');
        }
      }
    } catch (err) {
      // 폴더가 사라졌거나 나열 중 바뀌었으면 조용히 끝낸다.
      debugPrint('[sweepOrphan] 나열 중단: $err');
    }
    return n;
  }

  /// 삭제(샷·비트·트랙·씬) 뒤 고아가 된 미디어를 조용히 정리한다 — 화면은 안 막는다.
  void _sweepAfterDelete() => unawaited(sweepOrphanMedia());

  /// 리프레시 시 모든 미리보기(프레임·영상·음성·배경음)의 캐시 버전을 올린다 —
  /// 위젯 키(`path:version`)가 바뀌어 같은 파일명이라도 새로 그린다.
  void _bumpAllPreviewVersions(List<StoryScene> scenes) {
    void bump(String key) => _ver[key] = (_ver[key] ?? 0) + 1;
    for (final sc in scenes) {
      bump(bgmBusyKey(sc.id));
      for (final t in sc.tracks) {
        for (final b in t.beats) {
          bump(voiceBusyKey(b.id));
          for (final s in b.shots) {
            for (final m in GenMode.values) {
              bump(busyKey(s.id, m));
            }
          }
        }
      }
    }
  }

  /// 진행 상태를 갱신한다(영상칸 위 고정 표시) — 반복 스낵바 대신 이 값을 쓴다.
  void _setProgress(String key, String? text) {
    if (text == null) {
      _progress.remove(key);
    } else {
      _progress[key] = text;
    }
    notifyListeners();
  }
  String busyKey(String id, GenMode m) => '$id:${m.name}';

  /// 이 샷을 뽑을 때의 **기본** 백엔드 = 놓여 있는 트랙의 백엔드(트랙 밖이면 설정값).
  /// 생성 버튼은 다른 백엔드도 고를 수 있다 — 트랙은 결과가 들어가는 자리일 뿐이다.
  VideoBackend backendOf(Shot shot) =>
      trackOf(shot)?.backend ?? _settings.videoBackend;

  // ───────── 로드/저장 ─────────

  Future<void> _load() async {
    _settings = await _settingsStore.load();
    _settingsLoaded = true;
    await _readFromDisk(keepSelection: false);
    checkConnection();
    _statusTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => checkConnection(),
    );
  }

  /// 디스크에서 씬·인물을 다시 읽어 화면을 갈아끼운다 — **다른 곳(에디터·다른 세션)에서 파일이
  /// 바뀐 뒤 새로 불러오는 용도**. 편집 컨트롤러를 전부 새로 만들므로 옛것은 버린다.
  /// [keepSelection]이면 같은 id가 아직 있으면 그 선택을 유지한다(리프레시가 자리를 튀게 하지 않게).
  Future<void> _readFromDisk({required bool keepSelection}) async {
    final prevScene = _selectedSceneId;
    final prevBeat = _selectedDialogueId;
    final prevShot = _selectedShotId;

    _disposeAllItemControllers();

    final scenes = await _store.load();
    // 다른 세션·에디터가 씬을 복사하며 같은 id를 남기면(중복 id) 목록에 같은 씬이 두 번 뜨고
    // 클릭도 함께 먹는다(선택이 id 기준). 나중에 본 쪽을 새 id로 갈라 준다.
    final remapped = _ensureUniqueIds(scenes);
    _scenes = scenes;
    _characters = await _store.loadCharacters();
    for (final scene in scenes) {
      _sceneTitles[scene.id] = TextEditingController(text: scene.title);
      _sceneNotes[scene.id] = TextEditingController(text: scene.note);
      for (final track in scene.tracks) {
        for (final beat in track.beats) {
          _addDialogueControllers(beat); // 파생 비트도 자기 편집칸(상속 값 시드)
          for (final shot in beat.shots) {
            _addShotControllers(shot);
          }
        }
      }
      // 구조(비트·샷 개수/순서)만 기준 트랙에 맞춘다 — 값은 파일에 있는 그대로(복사 없음).
      _syncTracks(scene);
    }

    // 리프레시: 파일명이 같아도 내용이 바뀌었을 수 있다(외부 편집). Flutter 이미지 캐시는
    // 경로 기준이라 안 비우면 옛 그림이 그대로 뜬다 — 캐시를 비우고 미리보기 버전을 올려
    // 위젯 키(`path:version`)를 바꿔 강제로 다시 그린다. (초기 로드는 캐시가 비어 있어 무해)
    if (keepSelection) {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      _bumpAllPreviewVersions(scenes);
    }

    final keep = keepSelection && scenes.any((s) => s.id == prevScene);
    if (keep) {
      _selectedSceneId = prevScene;
      final beats = selectedTrack?.beats ?? const <DialogueBeat>[];
      _selectedDialogueId =
          beats.any((b) => b.id == prevBeat) ? prevBeat : beats.firstOrNull?.id;
      _selectedShotId =
          shots.any((s) => s.id == prevShot) ? prevShot : shots.firstOrNull?.id;
    } else {
      final firstScene = scenes.isNotEmpty ? scenes.first : null;
      final firstShot = (firstScene != null && firstScene.beats.isNotEmpty)
          ? firstScene.beats.first
          : null;
      _selectedSceneId = firstScene?.id;
      _selectedDialogueId = firstShot?.id;
      _selectedShotId = (firstShot != null && firstShot.shots.isNotEmpty)
          ? firstShot.shots.first.id
          : null;
    }
    _savePath = _store.path();
    notifyListeners();
    // 중복 id를 갈랐으면 갈라진 상태로 굳혀 둔다(다음에 또 겹쳐 보이지 않게).
    if (remapped) {
      messenger?.call('같은 id의 씬이 겹쳐 있어 하나를 새 id로 분리했습니다');
      unawaited(save());
    }
    unawaited(_backfillActualSeconds()); // 옛 영상의 실제 길이를 뒤에서 채운다
  }

  /// 프로젝트 전체에서 **id가 유일**하도록 보장한다. 중복이면 나중에 본 쪽을 새 id로 바꾸고,
  /// 파생 트랙의 참조(baseId)도 같은 씬 안에서 다시 잇는다. 하나라도 바꿨으면 true.
  bool _ensureUniqueIds(List<StoryScene> scenes) {
    final seen = <String>{};
    var changed = false;
    for (final sc in scenes) {
      final map = <String, String>{}; // 이 씬에서 바뀐 옛id→새id
      String uniq(String id, String prefix) {
        if (seen.add(id)) return id; // 처음 본 id — 그대로
        final nid = _newId(prefix);
        seen.add(nid);
        map[id] = nid;
        changed = true;
        return nid;
      }

      sc.id = uniq(sc.id, 'scene');
      for (final t in sc.tracks) {
        for (final b in t.beats) {
          b.id = uniq(b.id, 'beat');
          for (final s in b.shots) {
            s.id = uniq(s.id, 'clip');
          }
        }
      }
      // baseId가 방금 바뀐 id를 가리키면 새 id로 잇는다(파생 트랙 내부 참조 유지).
      if (map.isNotEmpty) {
        for (final t in sc.tracks) {
          for (final b in t.beats) {
            b.baseId = map[b.baseId] ?? b.baseId;
            for (final s in b.shots) {
              s.baseId = map[s.baseId] ?? s.baseId;
            }
          }
        }
      }
    }
    return changed;
  }

  /// 파일에서 다시 불러오기(리프레시). 다른 세션·에디터에서 scene*.json을 고쳤을 때 호출.
  /// 저장하지 않은 편집 중 내용은 사라진다 — 리프레시는 디스크를 정본으로 삼는 동작이다.
  Future<void> reloadFromDisk() async {
    await _readFromDisk(keepSelection: true);
    messenger?.call('파일에서 다시 불러왔습니다');
  }

  /// 씬·비트·샷의 편집 컨트롤러를 전부 정리한다(재로딩 전 옛것 비우기).
  /// 설정·연결 상태 등 프로젝트 밖 상태는 건드리지 않는다.
  void _disposeAllItemControllers() {
    for (final m in [
      _sceneTitles,
      _sceneNotes,
      _dialogueTitles,
      _notes,
      _directions,
      _startPrompts,
      _startPromptKos,
      _endPrompts,
      _endPromptKos,
      _vprompts,
      _vpromptKos,
      _vnegs,
      _shotNotes,
      _videoNotes,
    ]) {
      for (final c in m.values) {
        c.dispose();
      }
      m.clear();
    }
  }

  /// 이미 뽑아 둔 영상 중 **실제 길이를 모르는 것**을 파일에서 재어 채운다.
  /// 길이를 안 적던 시절의 데이터가 있어서 한 번은 훑어야 한다 — 화면에 주문값이 그대로
  /// 남아 있으면 4초짜리를 10초로 알고 타임라인을 그리게 된다.
  /// 화면을 막지 않도록 로드 뒤 뒤에서 돌고, 다 재고 나서 한 번만 저장한다.
  Future<void> _backfillActualSeconds() async {
    var changed = false;
    for (final scene in _scenes) {
      for (final track in scene.tracks) {
        for (final beat in track.beats) {
          for (final shot in beat.shots) {
            final path = shot.videoPath;
            // 실측이 아직 없거나 **0으로 굳은 것**(옛 측정 버그)도 다시 잰다.
            final have = shot.videoActualSeconds;
            if (path == null || (have != null && have > 0)) continue;
            final f = File(path);
            if (!await f.exists()) continue;
            final sec = await _measureSeconds(f);
            if (sec == null) continue;
            shot.videoActualSeconds = sec;
            changed = true;
          }
        }
      }
    }
    if (!changed) return;
    notifyListeners();
    await save();
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

  /// 비트 편집칸 생성 — 상속 해석값을 시드로. [base] 생략 시 씬에서 찾는다(로드 시엔 이미 트랙에
  /// 들어 있어 찾을 수 있고, 미러링 중 새로 만들 땐 base를 넘긴다).
  void _addDialogueControllers(DialogueBeat beat, [DialogueBeat? base]) {
    base ??= baseBeatOf(beat);
    _dialogueTitles[beat.id] =
        TextEditingController(text: beat.resolvedTitle(base));
    _notes[beat.id] = TextEditingController(text: beat.resolvedNote(base));
    _directions[beat.id] =
        TextEditingController(text: beat.resolvedDirection(base));
  }

  void _disposeDialogueControllers(String dialogueId) {
    _dialogueTitles.remove(dialogueId)?.dispose();
    _notes.remove(dialogueId)?.dispose();
    _directions.remove(dialogueId)?.dispose();
  }

  /// 샷 편집칸 생성 — 상속 해석값을 시드로. [base] 생략 시 씬에서 찾는다.
  void _addShotControllers(Shot shot, [Shot? base]) {
    base ??= baseShotOf(shot);
    _startPrompts[shot.id] =
        TextEditingController(text: shot.resolvedStartPrompt(base));
    _startPromptKos[shot.id] =
        TextEditingController(text: shot.resolvedStartPromptKo(base));
    _endPrompts[shot.id] =
        TextEditingController(text: shot.resolvedEndPrompt(base));
    _endPromptKos[shot.id] =
        TextEditingController(text: shot.resolvedEndPromptKo(base));
    _vprompts[shot.id] =
        TextEditingController(text: shot.resolvedVideoPrompt(base));
    _vpromptKos[shot.id] =
        TextEditingController(text: shot.resolvedVideoPromptKo(base));
    _vnegs[shot.id] = TextEditingController(text: shot.resolvedVideoNeg(base));
    _shotNotes[shot.id] = TextEditingController(text: shot.resolvedNote(base));
    _videoNotes[shot.id] =
        TextEditingController(text: shot.resolvedVideoNote(base));
  }

  void _disposeShotControllers(String shotId) {
    _startPrompts.remove(shotId)?.dispose();
    _startPromptKos.remove(shotId)?.dispose();
    _endPrompts.remove(shotId)?.dispose();
    _endPromptKos.remove(shotId)?.dispose();
    _vprompts.remove(shotId)?.dispose();
    _vpromptKos.remove(shotId)?.dispose();
    _vnegs.remove(shotId)?.dispose();
    _shotNotes.remove(shotId)?.dispose();
    _videoNotes.remove(shotId)?.dispose();
  }

  Future<void> save() async {
    for (final scene in _scenes) {
      scene.title = _sceneTitles[scene.id]?.text ?? scene.title;
      scene.note = _sceneNotes[scene.id]?.text ?? scene.note;
      for (final track in scene.tracks) {
        // 파생 트랙은 플러시 전에 **상속 중인**(오버라이드 안 함·편집 중 아님) 편집칸을 지금의
        // 기준 값으로 맞춘다. 기준 트랙(tracks[0])이 먼저 플러시되므로 이 시점 기준 값은 최신이다.
        // 이걸 안 하면 옛 시드가 남은 상속 편집칸이 새 기준값과 달라 보여 잘못 오버라이드로 굳는다.
        if (!identical(track, scene.baseTrack)) {
          _refreshInheritedDerived(track);
        }
        for (final beat in track.beats) {
          // 편집칸(제목·메모·연출) 플러시 — 기준 비트는 타입 필드에, 파생 비트는 기준과 다르면
          // overrides로(같으면 상속 유지). 트랙1은 파생 편집으로 절대 바뀌지 않는다.
          if (!beat.isDerived) {
            beat.title = _dialogueTitles[beat.id]?.text ?? beat.title;
            beat.note = _notes[beat.id]?.text ?? beat.note;
            beat.direction = _directions[beat.id]?.text ?? beat.direction;
          } else {
            final bb = baseBeatOf(beat);
            _flushBeatStr(beat, DialogueBeat.kTitle,
                _dialogueTitles[beat.id]?.text, bb?.title ?? '');
            _flushBeatStr(beat, DialogueBeat.kNote, _notes[beat.id]?.text,
                bb?.note ?? '');
            _flushBeatStr(beat, DialogueBeat.kDirection,
                _directions[beat.id]?.text, bb?.direction ?? '');
          }
          for (final shot in beat.shots) {
            if (!shot.isDerived) {
              shot.startPrompt =
                  _startPrompts[shot.id]?.text ?? shot.startPrompt;
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
              shot.note = _shotNotes[shot.id]?.text ?? shot.note;
              shot.videoNote = _videoNotes[shot.id]?.text ?? shot.videoNote;
            } else {
              final bs = baseShotOf(shot);
              _flushShotStr(shot, Shot.kStartPrompt,
                  _startPrompts[shot.id]?.text, bs?.startPrompt ?? '');
              _flushShotStr(shot, Shot.kStartPromptKo,
                  _startPromptKos[shot.id]?.text, bs?.startPromptKo ?? '');
              _flushShotStr(shot, Shot.kEndPrompt, _endPrompts[shot.id]?.text,
                  bs?.endPrompt ?? '');
              _flushShotStr(shot, Shot.kEndPromptKo,
                  _endPromptKos[shot.id]?.text, bs?.endPromptKo ?? '');
              _flushShotStr(shot, Shot.kVideoPrompt, _vprompts[shot.id]?.text,
                  bs?.videoPrompt ?? '');
              _flushShotStr(shot, Shot.kVideoPromptKo,
                  _vpromptKos[shot.id]?.text, bs?.videoPromptKo ?? '');
              _flushShotStr(shot, Shot.kVideoNeg, _vnegs[shot.id]?.text,
                  bs?.videoNegativePrompt ?? '');
              _flushShotStr(shot, Shot.kNote, _shotNotes[shot.id]?.text,
                  bs?.note ?? '');
              _flushShotStr(shot, Shot.kVideoNote, _videoNotes[shot.id]?.text,
                  bs?.videoNote ?? '');
            }
          }
        }
      }
      // 기준 트랙이 방금 바뀌었을 수 있다 — 파생 트랙 구조를 다시 맞춘 뒤 쓴다.
      _syncTracks(scene);
      for (final track in scene.tracks) {
        _syncLinkedStartPrompts(track);
      }
    }
    await _store.save(_scenes);
  }

  /// 파생 트랙의 **상속 중인**(오버라이드 안 한) 편집칸을 지금 기준 값으로 맞춘다.
  /// - 오버라이드한 필드는 자기 값이라 건드리지 않는다.
  /// - **지금 편집 중인**(선택된) 비트/샷은 건드리지 않는다 — 사용자가 방금 타이핑한 값이므로.
  /// - 값이 같으면 세팅을 건너뛰어 커서가 튀지 않는다([_setCtrl]).
  /// 플러시 **직전에** 부른다 — 안 그러면 옛 시드가 새 기준값과 달라 잘못 오버라이드로 굳는다.
  void _refreshInheritedDerived(VideoTrack track) {
    for (final beat in track.beats) {
      final editingBeat = beat.id == _selectedDialogueId;
      if (!editingBeat) {
        final bb = baseBeatOf(beat);
        if (!beat.overrides.containsKey(DialogueBeat.kTitle)) {
          _setCtrl(_dialogueTitles[beat.id], bb?.title ?? '');
        }
        if (!beat.overrides.containsKey(DialogueBeat.kNote)) {
          _setCtrl(_notes[beat.id], bb?.note ?? '');
        }
        if (!beat.overrides.containsKey(DialogueBeat.kDirection)) {
          _setCtrl(_directions[beat.id], bb?.direction ?? '');
        }
      }
      for (final shot in beat.shots) {
        if (shot.id == _selectedShotId) continue; // 편집 중인 샷은 그대로
        final bs = baseShotOf(shot);
        void refresh(String key, TextEditingController? c, String v) {
          if (!shot.overrides.containsKey(key)) _setCtrl(c, v);
        }

        refresh(Shot.kStartPrompt, _startPrompts[shot.id], bs?.startPrompt ?? '');
        refresh(Shot.kStartPromptKo, _startPromptKos[shot.id],
            bs?.startPromptKo ?? '');
        refresh(Shot.kEndPrompt, _endPrompts[shot.id], bs?.endPrompt ?? '');
        refresh(Shot.kEndPromptKo, _endPromptKos[shot.id], bs?.endPromptKo ?? '');
        refresh(Shot.kVideoPrompt, _vprompts[shot.id], bs?.videoPrompt ?? '');
        refresh(Shot.kVideoPromptKo, _vpromptKos[shot.id],
            bs?.videoPromptKo ?? '');
        refresh(Shot.kVideoNeg, _vnegs[shot.id], bs?.videoNegativePrompt ?? '');
        refresh(Shot.kNote, _shotNotes[shot.id], bs?.note ?? '');
        refresh(Shot.kVideoNote, _videoNotes[shot.id], bs?.videoNote ?? '');
      }
    }
  }

  void _setCtrl(TextEditingController? c, String text) {
    if (c == null || c.text == text) return;
    c.text = text;
  }

  /// 시작장면을 연동한 샷의 프롬프트를 앞 샷의 끝 프롬프트에 맞춘다.
  /// 이미지는 앞 샷의 끝이 만들어질 때 복사되지만 프롬프트는 그냥 타이핑이라 그 계기가 없다 —
  /// 저장(=글자 하나 칠 때마다)마다 맞춰야 연동이 실제로 살아 있다.
  /// 연동은 **트랙 안에서** 이어진다(앞 샷 = 같은 트랙의 앞 샷).
  void _syncLinkedStartPrompts(VideoTrack track) {
    final all = [for (final beat in track.beats) ...beat.shots];
    for (var i = 1; i < all.length; i++) {
      final shot = all[i];
      if (!shotLinkStart(shot)) continue;
      final prompt = shotEndPrompt(all[i - 1]);
      if (shotStartPrompt(shot) == prompt) continue;
      // 연동 시작 프롬프트도 트랙별로 해석/기록 — 파생은 기준과 다를 때만 오버라이드.
      if (shot.isDerived) {
        _flushShotStr(shot, Shot.kStartPrompt, prompt,
            baseShotOf(shot)?.startPrompt ?? '');
      } else {
        shot.startPrompt = prompt;
      }
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
    _sceneNotes[id] = TextEditingController();
    // 새 씬은 마지막으로 쓰던 해상도를 이어받는다(설정에 기억된 기본값).
    _scenes.add(StoryScene(
      id: id,
      imageRes: _settings.imageRes,
      videoRes: _settings.videoRes,
    ));
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
    _sceneNotes.remove(scene.id)?.dispose();
    for (final track in scene.tracks) {
      for (final beat in track.beats) {
        _disposeDialogueControllers(beat.id);
        for (final shot in beat.shots) {
          _disposeShotControllers(shot.id);
        }
      }
    }
    if (wasSelected) {
      final next = _scenes.isNotEmpty ? _scenes.last : null;
      _selectSceneInternal(next?.id);
    }
    notifyListeners();
    save();
    _sweepAfterDelete(); // 지운 씬의 모든 미디어(프레임·영상·음성·배경음) 정리
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

    // 옛 id → 새 id. 파생 트랙이 기준 트랙을 가리키는 연결(baseId)을 복제본 안으로 다시 잇는다.
    final idMap = <String, String>{};
    for (final track in copy.tracks) {
      track.id = _newId('track');
      for (final beat in track.beats) {
        final newBeatId = _newId('beat');
        idMap[beat.id] = newBeatId;
        // 음성(트랙별 소유 — dialogue에).
        final voice = beat.dialogue?.voicePath;
        if (voice != null) {
          beat.dialogue!.voicePath =
              await _copyMedia(voice, '${newBeatId}_voice');
        }
        // 효과음 — 기준 비트는 타입 필드, 파생 비트는 overrides에 있다.
        final sfx = beat.isDerived
            ? beat.overrides[DialogueBeat.kSfx] as Sfx?
            : beat.sfx;
        if (sfx?.path != null) {
          sfx!.path = await _copyMedia(sfx.path, '${newBeatId}_sfx');
        }
        for (final shot in beat.shots) {
          final newShotId = _newId('clip');
          idMap[shot.id] = newShotId;
          // 프레임 — 기준 샷은 타입 필드, 파생 샷은 오버라이드했을 때만 overrides에 있다.
          if (shot.isDerived) {
            if (shot.overrides.containsKey(Shot.kStartImage)) {
              shot.overrides[Shot.kStartImage] = await _copyMedia(
                  shot.overrides[Shot.kStartImage] as String?,
                  '${newShotId}_start');
            }
            if (shot.overrides.containsKey(Shot.kEndImage)) {
              shot.overrides[Shot.kEndImage] = await _copyMedia(
                  shot.overrides[Shot.kEndImage] as String?,
                  '${newShotId}_end');
            }
          } else {
            shot.startImagePath =
                await _copyMedia(shot.startImagePath, '${newShotId}_start');
            shot.endImagePath =
                await _copyMedia(shot.endImagePath, '${newShotId}_end');
          }
          // 영상은 트랙별 소유(기준·파생 모두 타입 필드).
          shot.videoPath =
              await _copyMedia(shot.videoPath, '${newShotId}_vlow');
          shot.id = newShotId;
        }
        beat.id = newBeatId;
      }
    }
    for (final track in copy.tracks) {
      for (final beat in track.beats) {
        beat.baseId = idMap[beat.baseId] ?? beat.baseId;
        for (final shot in beat.shots) {
          shot.baseId = idMap[shot.baseId] ?? shot.baseId;
        }
      }
    }

    // 컨트롤러 등록(새 id 기준) — 파생 비트도 자기 편집칸(상속 값 시드).
    _sceneTitles[copy.id] = TextEditingController(text: copy.title);
    _sceneNotes[copy.id] = TextEditingController(text: copy.note);
    for (final track in copy.tracks) {
      for (final beat in track.beats) {
        _addDialogueControllers(beat);
        for (final shot in beat.shots) {
          _addShotControllers(shot);
        }
      }
    }
    _syncTracks(copy); // 구조만 재확인(값 복사 없음)

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
    final beats = selectedTrack?.beats ?? const <DialogueBeat>[];
    final firstShot = (scene != null && beats.isNotEmpty) ? beats.first : null;
    _selectedDialogueId = firstShot?.id;
    _selectedShotId = (firstShot != null && firstShot.shots.isNotEmpty)
        ? firstShot.shots.first.id
        : null;
  }

  // ───────── 샷(비트) 추가/삭제/선택 ─────────

  /// 새 대사 추가 — 빈 대사(샷 0개). 샷은 캔버스의 ＋ 로 직접 추가한다.
  /// 구조는 트랙끼리 같아야 하므로 **기준 트랙에 넣고** 파생 트랙에는 같은 자리를 비춰 준다.
  void addDialogue() {
    final scene = selectedScene;
    if (scene == null) return; // 씬 먼저 선택/추가
    final beat = DialogueBeat(id: _newId('beat'));
    _addDialogueControllers(beat);
    scene.baseTrack.beats.add(beat);
    _syncTracks(scene);
    _selectedDialogueId = _sameSpotId(scene, beat);
    _selectedShotId = null; // 샷 없음
    notifyListeners();
    save();
  }

  void removeDialogue(DialogueBeat beat) {
    final scene = selectedScene;
    if (scene == null) return;
    final base = beat.isDerived ? baseBeatOf(beat) : beat;
    if (base == null) return;
    final wasSelected = _selectedDialogueId == beat.id;
    scene.baseTrack.beats.remove(base);
    _disposeDialogueControllers(base.id);
    for (final shot in base.shots) {
      _disposeShotControllers(shot.id);
    }
    _syncTracks(scene); // 파생 트랙에서도 같은 자리를 걷어낸다(컨트롤러 정리 포함)
    if (wasSelected) {
      final beats = selectedTrack?.beats ?? const <DialogueBeat>[];
      final next = beats.isNotEmpty ? beats.last : null;
      _selectedDialogueId = next?.id;
      _selectedShotId = (next != null && next.shots.isNotEmpty)
          ? next.shots.first.id
          : null;
    }
    notifyListeners();
    save();
    _sweepAfterDelete(); // 지운 비트의 샷 미디어·음성 정리
  }

  /// 보고 있는 트랙에서 기준 비트 [base]와 **같은 자리**의 비트 id(기준 트랙이면 그대로).
  String? _sameSpotId(StoryScene scene, DialogueBeat base) {
    final i = scene.baseTrack.beats.indexOf(base);
    final beats = selectedTrack?.beats ?? const <DialogueBeat>[];
    if (i < 0 || i >= beats.length) return base.id;
    return beats[i].id;
  }

  /// 대사 선택(몸통 탭). 샷은 선택하지 않는다 — 샷 편집은 캔버스에서 샷을 직접 클릭.
  /// 샷 선택을 비우면 오른쪽 패널이 '대사' 탭으로 전환되고, 장면/영상 탭은 "샷을 선택하세요"로 안내한다.
  void selectDialogue(String id) {
    if (_selectedDialogueId == id && _selectedShotId == null) return;
    _followTrackOf(id);
    _selectedDialogueId = id;
    _selectedShotId = null;
    notifyListeners();
  }

  /// 고른 비트가 놓인 트랙을 **보고 있는 트랙으로 삼는다**.
  /// 캔버스가 모든 트랙을 한 카드 안에 쌓아 보여주므로 트랙을 고르는 자리가 따로 없다 —
  /// 무엇을 눌렀는지가 곧 트랙 선택이고, 인스펙터·플레이어가 그 트랙을 따라간다.
  void _followTrackOf(String beatId) {
    final sc = selectedScene;
    if (sc == null) return;
    for (var i = 0; i < sc.tracks.length; i++) {
      if (sc.tracks[i].beats.any((b) => b.id == beatId)) {
        _trackIndex = i;
        return;
      }
    }
  }



  // ───────── 샷 추가/삭제/선택 ─────────

  /// 샷 추가 — 비트와 마찬가지로 **기준 트랙에 넣고** 파생 트랙에 같은 자리를 비춘다.
  Future<void> addShot(DialogueBeat beat) async {
    final scene = selectedScene;
    final base = beat.isDerived ? baseBeatOf(beat) : beat;
    if (scene == null || base == null) return;
    final shot =
        Shot(id: _newId('clip'), videoSeconds: _settings.videoSeconds.toDouble());
    _addShotControllers(shot);
    base.shots.add(shot);
    // FE2V 컷 연속성: 컷은 이어지는 게 기본이라 앞 샷이 있으면 시작장면을 연동해서 시작한다.
    // (씬의 첫 샷은 물려받을 앞이 없으니 꺼진 채로 둔다.) 연동은 앞 샷의 끝을 그대로
    // 가리키는 것이라 여기서 옮겨올 파일이 없다.
    shot.linkStart = prevShotOf(shot) != null;
    _syncTracks(scene);
    _selectedDialogueId = beat.id;
    _selectedShotId = beat.shots.isNotEmpty ? beat.shots.last.id : shot.id;
    await save(); // 프롬프트 연동이 여기서 걸리므로 알리기 전에 저장한다
    notifyListeners();
  }

  void removeShot(DialogueBeat beat, Shot shot) {
    final scene = selectedScene;
    final baseBeat = beat.isDerived ? baseBeatOf(beat) : beat;
    final baseShot = shot.isDerived ? baseShotOf(shot) : shot;
    if (scene == null || baseBeat == null || baseShot == null) return;
    final wasSelected = _selectedShotId == shot.id;
    baseBeat.shots.remove(baseShot);
    _disposeShotControllers(baseShot.id);
    _syncTracks(scene); // 파생 트랙의 같은 샷도 함께 사라진다
    if (wasSelected) {
      _selectedShotId = beat.shots.isNotEmpty ? beat.shots.last.id : null;
    }
    notifyListeners();
    save();
    _sweepAfterDelete(); // 지운 샷의 프레임·영상 정리
  }

  /// 샷 선택 — 소속 대사도, **그 샷이 놓인 트랙도** 함께 선택된다.
  void selectShot(String dialogueId, String shotId) {
    _followTrackOf(dialogueId);
    _selectedDialogueId = dialogueId;
    _selectedShotId = shotId;
    notifyListeners();
  }

  /// 샷별 영상 길이(초) 저장. 스틸컷은 0.1초 단위까지, AI는 정수 초로 슬라이더가 넘겨준다.
  /// 파생 샷이면 그 트랙만의 길이로 오버라이드된다(기준 트랙 길이는 그대로).
  Future<void> setShotSeconds(Shot shot, double sec) async {
    final v = (sec.clamp(0.1, 15) * 10).round() / 10;
    _setShotField(shot, Shot.kVideoSeconds, v, () => shot.videoSeconds = v);
    _settings = _settings.copyWith(videoSeconds: v.round()); // 새 샷 기본값(정수로 씨앗만)
    _settingsStore.save(_settings);
    save();
  }

  // ───────── 대사(비트 소유, 0/1) ─────────
  // 대사 편집은 **자기 트랙에만** 쓴다 — 파생 비트는 overrides로, 기준 비트는 타입 필드로.
  // (음성 mp3는 트랙별 소유라 dialogue에 직접 있고 오버라이드 대상이 아니다.)

  /// 이 비트의 대사 텍스트 저장(없으면 새로).
  void setShotDialogueText(DialogueBeat beat, String text) {
    if (beat.isDerived) {
      beat.overrides
        ..remove(DialogueBeat.kSilent)
        ..[DialogueBeat.kText] = text;
    } else {
      (beat.dialogue ??= Dialogue()).text = text;
    }
    notifyListeners();
    save();
  }

  /// 이 비트의 대사 화자(Character.id, null=내레이션) 저장(없으면 새로).
  void setShotDialogueSpeaker(DialogueBeat beat, String? speakerId) {
    if (beat.isDerived) {
      beat.overrides
        ..remove(DialogueBeat.kSilent)
        ..[DialogueBeat.kSpeaker] = speakerId;
    } else {
      (beat.dialogue ??= Dialogue()).speakerId = speakerId;
    }
    notifyListeners();
    save();
  }

  /// 이 비트의 대사 제거(무음으로). 파생 비트는 이 트랙만 무음(kSilent), 기준 비트는 대사 삭제.
  void removeShotDialogue(DialogueBeat beat) {
    if (beat.isDerived) {
      beat.overrides
        ..remove(DialogueBeat.kText)
        ..remove(DialogueBeat.kSpeaker)
        ..[DialogueBeat.kSilent] = true;
    } else {
      beat.dialogue = null;
    }
    notifyListeners();
    save();
  }

  // ── 효과음/자막: 트랙별 오버라이드 — 파생 비트에서 처음 손대면 지금 보이던 값(상속본)을
  //    스냅샷해 자기 것으로 만들고, 그 뒤엔 자기 것만 고친다(기준 비트는 안 바뀐다). ──

  /// 편집할 효과음 객체 — 파생 비트면 자기 overrides의 Sfx(없으면 스냅샷 생성).
  Sfx _editableSfx(DialogueBeat beat) {
    if (!beat.isDerived) return beat.sfx ??= Sfx();
    final cur = beat.overrides[DialogueBeat.kSfx];
    if (cur is Sfx) return cur;
    final seed = _snapshotSfx(sfxOf(beat)); // 묘사·길이·강도만(소리는 다시 뽑는다)
    beat.overrides[DialogueBeat.kSfx] = seed;
    return seed;
  }

  Sfx _snapshotSfx(Sfx? s) => s == null
      ? Sfx()
      : Sfx(
          prompt: s.prompt,
          durationSeconds: s.durationSeconds,
          promptInfluence: s.promptInfluence,
        );

  void setSfxPrompt(DialogueBeat beat, String text) {
    _editableSfx(beat).prompt = text;
    notifyListeners();
    save();
  }

  void setSfxDuration(DialogueBeat beat, double sec) {
    _editableSfx(beat).durationSeconds = (sec.clamp(0.5, 22) * 10).round() / 10;
    notifyListeners();
    save();
  }

  void setSfxInfluence(DialogueBeat beat, double v) {
    _editableSfx(beat).promptInfluence = (v.clamp(0.0, 1.0) * 100).round() / 100;
    notifyListeners();
    save();
  }

  /// 편집할 자막 객체 — 파생 비트면 자기 overrides의 Caption(없으면 스냅샷 생성).
  Caption _editableCaption(DialogueBeat beat) {
    if (!beat.isDerived) return beat.caption ??= Caption();
    final cur = beat.overrides[DialogueBeat.kCaption];
    if (cur is Caption) return cur;
    final seed = _snapshotCaption(captionOf(beat));
    beat.overrides[DialogueBeat.kCaption] = seed;
    return seed;
  }

  Caption _snapshotCaption(Caption? c) => c == null
      ? Caption()
      : Caption(
          position: c.position,
          cues: [
            for (final cue in c.cues)
              CaptionCue(seconds: cue.seconds, text: cue.text)
          ],
        );

  /// 자막 구간 하나 추가(끝에). 없으면 자막을 새로 만든다.
  void addCaptionCue(DialogueBeat beat) {
    _editableCaption(beat).cues.add(CaptionCue());
    notifyListeners();
    save();
  }

  /// 자막 구간 제거. 파생 비트가 아직 상속 중이면 스냅샷 후 같은 자리 구간을 지운다.
  void removeCaptionCue(DialogueBeat beat, CaptionCue cue) {
    final idx = _cueIndex(beat, cue);
    final cap = _editableCaption(beat);
    if (idx >= 0 && idx < cap.cues.length) cap.cues.removeAt(idx);
    notifyListeners();
    save();
  }

  void setCaptionCueText(DialogueBeat beat, CaptionCue cue, String text) {
    _editCaptionCue(beat, cue, (c) => c.text = text);
  }

  void setCaptionCueSeconds(DialogueBeat beat, CaptionCue cue, double sec) {
    _editCaptionCue(
        beat, cue, (c) => c.seconds = (sec.clamp(0.1, 60) * 10).round() / 10);
  }

  void setCaptionPosition(DialogueBeat beat, CaptionPosition pos) {
    _editableCaption(beat).position = pos;
    notifyListeners();
    save();
  }

  /// 현재 보이는(상속 포함) 자막에서 [cue]의 자리 번호 — 스냅샷 후 같은 자리를 찾기 위함.
  int _cueIndex(DialogueBeat beat, CaptionCue cue) =>
      captionOf(beat)?.cues.indexOf(cue) ?? -1;

  /// 자막 구간 한 칸 편집 — 파생 비트가 상속 중이면 자리 번호로 스냅샷의 같은 구간에 적용.
  void _editCaptionCue(
      DialogueBeat beat, CaptionCue cue, void Function(CaptionCue) apply) {
    final idx = _cueIndex(beat, cue);
    final cap = _editableCaption(beat);
    final target = (idx >= 0 && idx < cap.cues.length)
        ? cap.cues[idx]
        : (cap.cues.contains(cue) ? cue : null);
    if (target != null) apply(target);
    notifyListeners();
    save();
  }

  /// 생성된 효과음만 지운다(묘사·설정은 남겨 다시 뽑을 수 있게). 파일은 고아 정리가 치운다.
  void clearSfxSound(DialogueBeat beat) {
    if (sfxOf(beat) == null) return; // 지울 효과음이 없음
    final s = _editableSfx(beat); // 파생이 상속 중이면 자기 것으로 떠(소리 없이) 만든다
    s.path = null;
    s.soundSeconds = 0;
    final k = sfxBusyKey(beat.id);
    _ver[k] = (_ver[k] ?? 0) + 1;
    notifyListeners();
    save();
    _sweepAfterDelete();
  }

  /// 대사 음성 진행 상태 키(샷 단위). 음성은 트랙끼리 공유하므로 **기준 비트 기준**으로 잡는다 —
  /// 어느 트랙에서 보고 있든 같은 진행 표시·같은 미리보기 캐시를 쓴다.
  // 음성은 **트랙별**이라 진행 표시·캐시도 그 트랙의 비트 id 기준(대본과 달리 공유 아님).
  String voiceBusyKey(String dialogueId) => '$dialogueId:voice';

  /// 이 대사에 쓸 보이스 — 화자에 보이스가 있으면 그것, 없으면(내레이션·화자 미지정)
  /// **씬 기본 성우**로 떨어진다. 둘 다 없으면 null → 음성 생성 불가.
  String? _voiceIdFor(String? speakerId, VideoTrack? track) {
    final speaker = characterById(speakerId);
    if (speaker != null && speaker.hasVoice) return speaker.voiceId.trim();
    final fallback = track?.defaultVoiceId.trim() ?? '';
    return fallback.isEmpty ? null : fallback;
  }

  /// **이 트랙**의 기본 성우(내레이션·화자 미지정 대사에 쓰는 보이스) 지정. 비우면 미지정.
  void setTrackDefaultVoice(VideoTrack track, String voiceId, String voiceName) {
    track.defaultVoiceId = voiceId.trim();
    track.defaultVoiceName = voiceName.trim();
    notifyListeners();
    save();
  }

  /// 이 비트가 속한 트랙(어느 씬이든).
  VideoTrack? trackOfBeat(DialogueBeat beat) {
    for (final sc in _scenes) {
      for (final t in sc.tracks) {
        if (t.beats.contains(beat)) return t;
      }
    }
    return null;
  }

  /// 미디어 파일 길이(초) 실측 — 음성이든 영상이든. 길이가 타임라인을 정하므로
  /// 만든 것도 불러온 것도 반드시 재어 둔다. (재생에 이미 쓰는 video_player로 잰다.)
  Future<double> _audioSeconds(File f) async {
    final c = VideoPlayerController.file(f);
    try {
      await c.initialize();
      return c.value.duration.inMilliseconds / 1000.0;
    } finally {
      await c.dispose();
    }
  }

  /// 파일 길이(초)를 재되, 못 재면 null — 길이 하나 때문에 생성 결과를 날릴 순 없다.
  /// 0(초기화 전/미지원 코덱)도 실패로 봐 **null로 반환**한다 — 0을 저장하면 화면이 0초로 굳는다.
  Future<double?> _measureSeconds(File f) async {
    try {
      final s = await _audioSeconds(f);
      return s > 0 ? s : null;
    } catch (e) {
      debugPrint('[measure] 길이 실측 실패(무시): $e');
      return null;
    }
  }

  /// 대사 음성을 기존 오디오 파일에서 불러온다(기본 동선 — 생성은 부가).
  Future<void> loadVoice(DialogueBeat beat) async {
    // 음성은 **이 트랙의 비트**에 붙인다(대본은 공유지만 음성은 트랙별 소유).
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
    // 대본(화자·텍스트)은 상속/오버라이드 해석으로 읽고, 음성(결과)은 **이 트랙의 비트**에 붙인다.
    final script = beatScript(beat);
    if (script == null || script.text.trim().isEmpty) {
      messenger?.call('대사를 먼저 입력하세요');
      return;
    }
    if (!voiceReady) {
      messenger?.call(voiceBlockReason!);
      return;
    }
    final voiceId = _voiceIdFor(script.speakerId, trackOfBeat(beat));
    if (voiceId == null) {
      messenger?.call('보이스가 없습니다 — 화자에 목소리를 지정하거나 씬 탭에서 기본 성우를 정하세요');
      return;
    }
    final key = voiceBusyKey(beat.id);
    _busy.add(key);
    notifyListeners();
    try {
      final res = await ElevenLabsService(_settings.elevenKey).generateSpeech(
        voiceId: voiceId,
        text: script.text.trim(),
        stability: _settings.ttsStability.value, // Creative/Natural/Robust
      );
      final f = File('$projectDirPath/${beat.id}_voice.mp3');
      await f.writeAsBytes(res.bytes);
      final d = beat.dialogue ??= Dialogue(); // 음성은 자기 것(파생도 자기 dialogue에)
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

  /// 효과음을 기존 오디오 파일에서 불러온다. 효과음은 트랙별 소유라 **이 비트 자기 것**에 붙인다.
  Future<void> loadSfx(DialogueBeat beat) async {
    const typeGroup = fs.XTypeGroup(
      label: 'audio',
      extensions: ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'],
    );
    final picked = await fs.openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    final key = sfxBusyKey(beat.id);
    _busy.add(key);
    notifyListeners();
    try {
      final ext = picked.name.split('.').last.toLowerCase();
      final f = File('$projectDirPath/${beat.id}_sfx.$ext');
      await f.writeAsBytes(await picked.readAsBytes());
      // 확장자가 바뀌면 옛 파일이 남으므로 정리.
      for (final e in Directory(projectDirPath).listSync().whereType<File>()) {
        final n = e.uri.pathSegments.last;
        if (n.startsWith('${beat.id}_sfx.') && e.path != f.path) {
          await e.delete();
        }
      }
      final s = _editableSfx(beat);
      s.path = f.path;
      s.soundSeconds = await _audioSeconds(f);
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
    } catch (e, st) {
      debugPrint('[loadSfx] $key 실패: $e\n$st');
      messenger?.call('효과음 불러오기 실패: $e');
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  /// 효과음(일레븐랩스 sound-generation) 생성 → mp3 저장 + 길이 실측. 이 비트 자기 것에 붙인다.
  Future<void> genSfx(DialogueBeat beat) async {
    final s = sfxOf(beat); // 묘사·길이·강도는 지금 보이는(상속 포함) 값으로 뽑는다
    if (s == null || s.prompt.trim().isEmpty) {
      messenger?.call('효과음 묘사를 먼저 입력하세요');
      return;
    }
    if (!voiceReady) {
      messenger?.call(voiceBlockReason!);
      return;
    }
    final key = sfxBusyKey(beat.id);
    _busy.add(key);
    notifyListeners();
    try {
      final bytes = await ElevenLabsService(_settings.elevenKey).generateSound(
        text: s.prompt.trim(),
        durationSeconds: s.durationSeconds,
        promptInfluence: s.promptInfluence,
      );
      final f = File('$projectDirPath/${beat.id}_sfx.mp3');
      await f.writeAsBytes(bytes);
      final own = _editableSfx(beat); // 파생이면 자기 것으로 떠서 소리를 붙인다
      own.path = f.path;
      own.soundSeconds = await _measureSeconds(f) ?? own.durationSeconds;
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
    } catch (e, st) {
      debugPrint('[sfx] $key 실패: $e\n$st');
      messenger?.call('효과음 생성 실패: $e');
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
    // 음성은 트랙별 — **보고 있는 트랙**의 비트들을 돈다(그 트랙의 take를 채운다).
    final track = selectedTrack ?? scene.baseTrack;
    for (final beat in List<DialogueBeat>.from(track.beats)) {
      if (beatScript(beat)?.text.trim().isNotEmpty ?? false) {
        await genVoice(beat);
      }
    }
  }

  bool _hasFile(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  /// 사람이 알아볼 샷 이름 — 제목이 없으면 트랙 안에서 몇 번째 샷인지로 부른다.
  String shotLabel(Shot shot) {
    if (shotTitle(shot).trim().isNotEmpty) return shotTitle(shot).trim();
    final track = trackOf(shot);
    if (track == null) return '샷';
    var n = 0;
    for (final beat in track.beats) {
      for (final s in beat.shots) {
        n++;
        if (identical(s, shot)) return '샷 $n';
      }
    }
    return '샷';
  }

  // ───────── 생성(샷) ─────────

  TextEditingController? _promptCtrlFor(String shotId, GenMode mode) =>
      switch (mode) {
        GenMode.imageStart => _startPrompts[shotId],
        GenMode.imageEnd => _endPrompts[shotId],
        GenMode.videoLow => _vprompts[shotId],
      };

  /// [backend] 영상 생성에만 의미 있음 — 생략하면 **이 샷이 놓인 트랙의 백엔드**로 뽑는다
  /// (트랙을 가르는 기준이 백엔드라서). 결과는 그 트랙의 영상 슬롯에만 들어가므로,
  /// 다른 트랙에서 뽑아 둔 영상은 그대로 남는다 — 그게 비교의 전부다.
  ///
  /// 프레임(시작·끝)을 파생 샷에서 뽑으면 그 프레임만 이 트랙 것으로 오버라이드된다
  /// (기준 트랙 프레임은 그대로 — 자동으로 필드별 분리).
  Future<void> gen(
    Shot shot,
    GenMode mode, {
    VideoBackend? backend,
  }) async {
    // 스틸컷: 프롬프트·백엔드 없이 시작 프레임을 로컬 ffmpeg로 영상화한다.
    if (mode == GenMode.videoLow && shotVideoMode(shot) == VideoMode.still) {
      await _genStill(shot);
      return;
    }
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
      final bytes = await _generateBytes(shot, mode, prompt, backend, key);
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
          _setShotStartImage(shot, f.path); // 파생이면 오버라이드
        case GenMode.imageEnd:
          _setShotEndImage(shot, f.path);
        case GenMode.videoLow:
          shot.videoPath = f.path; // 영상은 트랙별 소유(기준·파생 모두 자기 것)
          // 주문한 길이와 실제가 다른 일이 흔하다(백엔드 지원 길이·모델이 얹는 몇 프레임).
          // 타임라인은 재생되는 길이로 그려져야 하므로 파일에서 직접 잰다.
          shot.videoActualSeconds = await _measureSeconds(f);
      }
      if (mode == GenMode.imageEnd) _refreshLinkedNext(shot);
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
    } catch (e, st) {
      debugPrint('[generate] $key 실패: $e\n$st');
      messenger?.call('생성 실패: $e');
    } finally {
      _busy.remove(key);
      _progress.remove(key); // 고정 진행 표시 정리
      notifyListeners();
    }
  }

  /// 스틸컷 생성 — AI 없이 **시작 프레임 한 장**을 영상 길이만큼 채운다(로컬 ffmpeg).
  /// 켄번스([Shot.stillEffect])로 줌 인/아웃도 준다. 결과는 FE2V와 같은 `<id>_vlow.mp4` 슬롯.
  Future<void> _genStill(Shot shot) async {
    if (!VideoEdit.available) {
      messenger?.call(VideoEdit.missingHint);
      return;
    }
    final img = startPathOf(shot); // 연동 포함 시작 프레임
    if (!_hasFile(img)) {
      messenger?.call('시작 프레임을 먼저 만들어 주세요');
      return;
    }
    final key = busyKey(shot.id, GenMode.videoLow);
    _busy.add(key);
    _setProgress(key, '스틸컷 만드는 중…');
    notifyListeners();
    try {
      final out = '$projectDirPath/${shot.id}_vlow.mp4';
      final res = sceneOf(shot)?.videoRes ?? _settings.videoRes; // 씬 단위 해상도
      await VideoEdit.stillClip(
        image: img!,
        outPath: out,
        seconds: shotVideoSeconds(shot), // 0.1초 단위 그대로(파생은 상속/오버라이드 해석)
        effect: shotStillEffect(shot),
        width: res.width,
        height: res.height,
      );
      final f = File(out);
      await FileImage(f).evict();
      shot.videoPath = f.path;
      shot.videoActualSeconds = await _measureSeconds(f);
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
    } catch (e, st) {
      debugPrint('[still] $key 실패: $e\n$st');
      messenger?.call('스틸컷 실패: $e');
    } finally {
      _busy.remove(key);
      _progress.remove(key);
      notifyListeners();
    }
  }

  /// 시작/끝장면을 기존 이미지 파일에서 불러온다(생성 대신). 파생 샷이면 그 프레임만 오버라이드.
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
        _setShotStartImage(shot, f.path);
      } else {
        _setShotEndImage(shot, f.path);
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
    String prompt,
    VideoBackend? backend,
    String progressKey, // 진행 문구를 담을 busyKey — 반복 스낵바 대신 영상칸에 고정 표시
  ) async {
    if (!mode.isVideo) {
      final refs = await _refPhotoBytesList(shot);
      if (refs.isNotEmpty) {
        final who = shotRefCharacterIds(shot)
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
      final res = sceneOf(shot)?.imageRes ?? _settings.imageRes; // 씬별 해상도
      return ApiService(
        _settings.effectiveServiceUrl,
      ).generateImage(prompt, width: res.width, height: res.height);
    }
    // 영상 생성(저) = FE2V: 시작·끝 두 프레임이 입력(둘 다 필수).
    switch (backend ?? backendOf(shot)) {
      case VideoBackend.veo:
        final start = await _startFrame(shot);
        // 끝 프레임은 **있으면 보낸다**. I2V로 잡아 뒀거나 아직 안 만들었으면 시작만으로 간다 —
        // Veo 쪽 끝 프레임 고정은 계정에 따라 막혀 있고(400 use case not supported),
        // 그때는 서비스가 알아서 시작 프레임만으로 다시 시도한다.
        final end = shotNeedsEndFrame(shot) ? await _endFrame(shot) : null;
        if (start == null) {
          throw Exception('시작장면을 먼저 만들어 주세요 (첫 프레임)');
        }
        return VeoVideoService().generate(
          apiKey: _settings.geminiKey,
          model: _settings.veoModel,
          prompt: prompt,
          image: start,
          lastFrame: end,
          aspectRatio: _settings.videoAspect.value,
          resolution: _settings.videoResolution.value,
          // 길이는 **샷이 정한다**. Veo는 4·6·8초만 되므로 가장 가까운 값으로 내려간다
          // (그래서 뽑고 나면 실제 길이를 다시 재서 적는다 — gen() 참고).
          durationSeconds: _veoSeconds(shotVideoSeconds(shot).round()),
          negativePrompt: _settings.videoNegativePrompt,
          onProgress: (st) => _setProgress(progressKey, st),
        );
      case VideoBackend.serviceApi:
        final img = await _startFrameBytes(shot);
        // I2V면 끝 프레임을 아예 안 쓴다(있어도 무시) — 끝은 모델이 자유롭게 만든다.
        final endImg = shotNeedsEndFrame(shot) ? await _endFrameBytes(shot) : null;
        if (img == null) {
          throw Exception('시작 프레임을 먼저 만들어 주세요');
        }
        if (shotNeedsEndFrame(shot) && endImg == null) {
          throw Exception('끝 프레임을 먼저 만들어 주세요 (FE2V) — '
              '끝 없이 뽑으려면 프레임 탭에서 I2V로 바꾸세요');
        }
        final sc = sceneOf(shot); // 해상도는 씬 단위
        final track = trackOf(shot); // LoRA는 트랙 단위
        final res = sc?.videoRes ?? _settings.videoRes;
        // 네거티브는 샷 칸이 먼저고, 비어 있으면 설정의 전역 값으로 떨어진다.
        // 둘 다 비면 서버 워크플로에 박힌 기본 네거티브가 쓰인다.
        final neg = (_vnegs[shot.id]?.text ?? shotVideoNeg(shot)).trim();
        return ApiService(_settings.effectiveServiceUrl).generateVideo(
          image: img,
          endImage: endImg,
          prompt: prompt,
          negativePrompt:
              neg.isNotEmpty ? neg : _settings.videoNegativePrompt.trim(),
          width: res.width,
          height: res.height,
          seconds: shotVideoSeconds(shot).round(), // 자체 서버는 정수 초
          loraUrl: _effectiveLoraUrl(track),
          loraStrength: track?.loraStrength ?? 0.8,
          onProgress: (st) => _setProgress(progressKey, st),
        );
    }
  }

  /// Veo가 받아 주는 길이(4·6·8초) 중 [wanted]에 가장 가까운 값.
  /// 주문한 길이를 그대로 못 쓰는 건 사실이므로, 달라지면 화면에 알린다.
  int _veoSeconds(int wanted) {
    const allowed = [4, 6, 8];
    var best = allowed.first;
    for (final v in allowed) {
      if ((v - wanted).abs() < (best - wanted).abs()) best = v;
    }
    if (best != wanted) {
      messenger?.call('Veo는 4·6·8초만 됩니다 — $wanted초 대신 $best초로 뽑습니다');
    }
    return best;
  }

  /// 영상 생성 해상도(비율 포함) 선택 저장.
  /// 영상 생성 해상도 저장 — **씬별**. 새 씬이 이어받도록 마지막 값도 설정에 기억한다.
  void setVideoRes(VideoRes r) {
    final sc = selectedScene;
    if (sc == null) return;
    sc.videoRes = r;
    _settings = _settings.copyWith(videoRes: r); // 새 씬 기본값(마지막 사용값)
    notifyListeners();
    _settingsStore.save(_settings);
    save();
  }

  /// 스크린샷(시작·끝 프레임) 생성 해상도 저장 — **씬별**. 마지막 값은 새 씬 기본값으로 기억.
  void setImageRes(ImageRes r) {
    final sc = selectedScene;
    if (sc == null) return;
    sc.imageRes = r;
    _settings = _settings.copyWith(imageRes: r);
    notifyListeners();
    _settingsStore.save(_settings);
    save();
  }

  /// **이 트랙**의 LoRA URL 저장(트랙끼리 별개).
  void setTrackLoraUrl(VideoTrack track, String url) {
    track.loraUrl = url.trim();
    notifyListeners();
    save();
  }

  /// **이 트랙**의 재생 배속(1.0~2.0) 저장 — 미리보기·내보내기에 똑같이 걸린다.
  void setTrackSpeed(VideoTrack track, double v) {
    track.speed = ((v * 10).round() / 10).clamp(1.0, 2.0); // 0.1 단위
    notifyListeners();
    save();
  }

  /// **이 트랙**의 LoRA 강도(0~1.5) 저장.
  void setTrackLoraStrength(VideoTrack track, double v) {
    track.loraStrength = v.clamp(0.0, 1.5);
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
  /// 파생 샷이면 참조 인물 목록만 이 트랙 것으로 오버라이드된다.
  Future<void> toggleShotRefCharacter(Shot shot, String id) async {
    final cur = List<String>.from(shotRefCharacterIds(shot)); // 상속 포함 현재값
    if (cur.contains(id)) {
      cur.remove(id);
    } else if (cur.length < 3) {
      cur.add(id);
    }
    _setShotField(
        shot, Shot.kRefCharacters, cur, () => shot.refCharacterIds = cur);
    notifyListeners();
    save();
  }

  /// 참조 인물들의 대표사진 바이트(최대 3, 존재하는 것만). 없으면 빈 리스트 → 일반 t2i.
  Future<List<Uint8List>> _refPhotoBytesList(Shot shot) async {
    final out = <Uint8List>[];
    for (final id in shotRefCharacterIds(shot).take(3)) {
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

  /// 인스펙터 마지막 선택 탭(0=비트, 1=장면, 2=영상, 3=씬, 4=배경음) 저장.
  void setInspectorTab(int i) {
    if (_settings.inspectorTab == i) return;
    _settings = _settings.copyWith(inspectorTab: i);
    _settingsStore.save(_settings);
  }

  /// 프롬프트 칸의 원본/번역 토글 상태 — 한 번 고르면 유지된다(다음 샷·앱 재시작 후에도).
  bool get promptShowKo => _settings.promptShowKo;
  void setPromptShowKo(bool ko) {
    if (_settings.promptShowKo == ko) return;
    _settings = _settings.copyWith(promptShowKo: ko);
    notifyListeners();
    _settingsStore.save(_settings);
  }

  /// 대사 TTS 안정성 프리셋(Creative/Natural/Robust) 저장.
  void setTtsStability(TtsStability s) {
    if (_settings.ttsStability == s) return;
    _settings = _settings.copyWith(ttsStability: s);
    notifyListeners();
    _settingsStore.save(_settings);
  }

  int _inspectorTabReq = -1;
  int _inspectorTabReqSeq = 0;

  /// 열어 달라고 요청된 인스펙터 탭과 그 요청 횟수. 패널은 [inspectorTabReqSeq]가
  /// 바뀐 걸 보고 탭을 옮긴다 — 같은 탭을 다시 눌러도 반응하도록 횟수를 센다.
  int get inspectorTabReq => _inspectorTabReq;
  int get inspectorTabReqSeq => _inspectorTabReqSeq;

  /// 캔버스 등 바깥에서 인스펙터의 특정 탭을 연다(0=비트, 1=장면, 2=영상, 3=씬, 4=배경음).
  void openInspectorTab(int i) {
    _inspectorTabReq = i;
    _inspectorTabReqSeq++;
    setInspectorTab(i);
    notifyListeners();
  }

  /// 샷이 속한 씬 찾기(씬 → 트랙 → 대사 → 샷 탐색).
  StoryScene? sceneOf(Shot shot) {
    for (final sc in _scenes) {
      for (final t in sc.tracks) {
        for (final beat in t.beats) {
          if (beat.shots.contains(shot)) return sc;
        }
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
    final path = shotEndImage(shot); // 상속/오버라이드 해석
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return (bytes: await f.readAsBytes(), mimeType: 'image/png');
  }

  /// 샷의 생성물 하나(시작 프레임 · 끝 프레임 · 영상)를 지운다.
  /// 파생 샷에서 **자기 프레임을 지우면 다시 기준 트랙 프레임을 상속**한다(오버라이드 해제).
  /// 상속 중이던 프레임은 기준 트랙 파일이라 지우지 않는다(참조만 되돌린다).
  Future<void> removeMedia(Shot shot, GenMode mode) async {
    final path = switch (mode) {
      GenMode.imageStart => shotStartImage(shot),
      GenMode.imageEnd => shotEndImage(shot),
      GenMode.videoLow => shot.videoPath,
    };
    if (path == null) return;
    // 자기 파일인지 — 기준 샷은 항상, 파생 샷은 그 필드를 오버라이드했을 때만 자기 파일이다.
    final ownsFile = switch (mode) {
      GenMode.imageStart =>
        !shot.isDerived || shot.overrides.containsKey(Shot.kStartImage),
      GenMode.imageEnd =>
        !shot.isDerived || shot.overrides.containsKey(Shot.kEndImage),
      GenMode.videoLow => true, // 영상은 언제나 자기 것
    };
    switch (mode) {
      case GenMode.imageStart:
        if (shot.isDerived) {
          shot.overrides.remove(Shot.kStartImage); // 상속으로 되돌림
        } else {
          shot.startImagePath = null;
        }
      case GenMode.imageEnd:
        if (shot.isDerived) {
          shot.overrides.remove(Shot.kEndImage);
        } else {
          shot.endImagePath = null;
        }
      case GenMode.videoLow:
        shot.videoPath = null;
    }
    if (ownsFile) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
        await FileImage(f).evict();
      } catch (e) {
        debugPrint('[removeMedia] 파일 삭제 실패(참조는 이미 끊음): $e');
      }
    }
    final k = busyKey(shot.id, mode);
    _ver[k] = (_ver[k] ?? 0) + 1;
    notifyListeners();
    await save();
  }

  /// 트림 결과를 반영한다 — 파일은 이미 [VideoEdit.trim]이 덮어썼고, 여기서는 상태만 맞춘다.
  /// 잘린 결과는 **그 트랙 영상의 실제 길이**다(주문값 [Shot.videoSeconds]는 그대로 둔다 —
  /// 트랙끼리 공유하는 값이라 여기서 건드리면 다른 트랙의 계획까지 바뀐다).
  /// 미리보기는 경로가 같으므로 _ver을 올려 캐시를 무효화해야 갱신된다.
  Future<void> applyTrim(Shot shot, double seconds) async {
    shot.videoActualSeconds = seconds;
    final k = busyKey(shot.id, GenMode.videoLow);
    _ver[k] = (_ver[k] ?? 0) + 1;
    notifyListeners();
    await save();
  }

  /// 파생 트랙(트랙2…)의 이 샷 영상을 **기준 트랙(트랙1)으로 복사**한다 — 비교하다 마음에 든
  /// take를 기본으로 승격. 기준 샷의 기존 영상은 덮어쓴다. 파일을 복사해 각자 소유로 둔다
  /// (파생 트랙 것을 지워도 기준 트랙이 안 깨진다).
  Future<void> copyVideoToBase(Shot shot) async {
    if (!shot.isDerived) return; // 기준 트랙 샷은 복사할 곳이 없다
    final base = baseShotOf(shot);
    if (base == null) {
      messenger?.call('기준 트랙 샷을 찾을 수 없습니다');
      return;
    }
    final src = shot.videoPath;
    if (src == null || !File(src).existsSync()) {
      messenger?.call('복사할 영상이 없습니다');
      return;
    }
    final key = busyKey(base.id, GenMode.videoLow);
    _busy.add(key);
    notifyListeners();
    try {
      base.videoPath = await _copyMedia(src, '${base.id}_vlow');
      // 실제 길이는 원본 것을 그대로(같은 파일) — 없으면 복사본에서 다시 잰다.
      base.videoActualSeconds = shot.videoActualSeconds ??
          (base.videoPath != null
              ? await _measureSeconds(File(base.videoPath!))
              : null);
      _ver[key] = (_ver[key] ?? 0) + 1;
      await save();
      messenger?.call('${trackLabel(tracks.first)}(으)로 영상을 복사했습니다');
    } catch (e, st) {
      debugPrint('[copyToBase] 실패: $e\n$st');
      messenger?.call('복사 실패: $e');
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
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

    // 트랙 전부를 훑는다 — 비교하려고 뽑아 둔 다른 트랙 영상도 같이 비운다.
    // 따라가는 샷의 프레임은 기준 트랙 파일을 가리킬 뿐이라(자기 것이 아니다) 건드리지 않는다.
    for (final track in scene.tracks) {
      for (final beat in track.beats) {
        for (final shot in beat.shots) {
          // 프레임 — 자기 것만 지운다. 파생 샷은 오버라이드한 프레임만(상속 중이면 기준 트랙 것).
          if (shot.isDerived) {
            if (shot.overrides.containsKey(Shot.kStartImage)) {
              await kill(shot.overrides[Shot.kStartImage] as String?);
              shot.overrides.remove(Shot.kStartImage);
            }
            if (shot.overrides.containsKey(Shot.kEndImage)) {
              await kill(shot.overrides[Shot.kEndImage] as String?);
              shot.overrides.remove(Shot.kEndImage);
            }
          } else {
            await kill(shot.startImagePath);
            await kill(shot.endImagePath);
            shot.startImagePath = null;
            shot.endImagePath = null;
          }
          await kill(shot.videoPath);
          shot.videoPath = null;
          for (final m in GenMode.values) {
            final k = busyKey(shot.id, m);
            _ver[k] = (_ver[k] ?? 0) + 1;
          }
        }
        // 음성은 트랙별 소유 — 모든 트랙 비트의 음성을 지운다.
        final d = beat.dialogue;
        if (d != null) {
          await kill(d.voicePath);
          d.voicePath = null;
          d.voiceSeconds = 0;
          final k = voiceBusyKey(beat.id);
          _ver[k] = (_ver[k] ?? 0) + 1;
        }
        // 효과음 — 기준 비트는 타입 필드, 파생 비트는 overrides에 있다(있을 때만).
        final sx = beat.isDerived
            ? beat.overrides[DialogueBeat.kSfx] as Sfx?
            : beat.sfx;
        if (sx != null && sx.path != null) {
          await kill(sx.path);
          sx.path = null;
          sx.soundSeconds = 0;
          final sk = sfxBusyKey(beat.id);
          _ver[sk] = (_ver[sk] ?? 0) + 1;
        }
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
  /// [shot]이 속한 **트랙**의 샷 전체를 순서대로(대사 경계 무시). [sceneShots]와 달리
  /// 선택된 씬이 아니라 그 샷이 놓인 자리를 본다 — 일괄 생성은 안 열어 본 씬도 훑는다.
  /// 컷 연속성(시작장면 연동)은 트랙 안에서 이어진다.
  List<Shot> _shotsAround(Shot shot) {
    final track = trackOf(shot);
    if (track == null) return const [];
    return [for (final beat in track.beats) ...beat.shots];
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
  String? startPathOf(Shot shot) {
    if (shotLinkStart(shot)) {
      final prev = prevShotOf(shot);
      return prev == null ? null : shotEndImage(prev);
    }
    return shotStartImage(shot);
  }

  /// 시작장면 연동 켜기/끄기.
  ///
  /// 켤 때: 플래그만 세우면 된다 — 이미지는 [startPathOf]가 앞 샷에서 바로 읽는다.
  /// 직접 만들어 둔 시작 이미지는 지우지 않고 남겨둔다(끄면 그대로 돌아온다).
  ///
  /// 끌 때: 직접 만들어 둔 게 없으면 지금 보고 있던 앞 샷의 끝을 자기 파일로 굳혀준다 —
  /// 끄자마자 프레임이 사라지면 당황스럽다.
  Future<void> setLinkStart(Shot shot, bool on) async {
    if (on && prevShotOf(shot) == null) return; // 첫 샷은 물려받을 앞이 없다
    if (!on && shotLinkStart(shot) && shotStartImage(shot) == null) {
      await _materializeStart(shot);
    }
    _setShotField(shot, Shot.kLinkStart, on, () => shot.linkStart = on);
    _ver[busyKey(shot.id, GenMode.imageStart)] =
        (_ver[busyKey(shot.id, GenMode.imageStart)] ?? 0) + 1;
    await save(); // 프롬프트 연동이 여기서 걸리므로 알리기 전에 저장한다
    notifyListeners();
  }

  /// 영상 생성 방식 전환 — FE2V(시작+끝) / I2V(시작 한 장) / 스틸컷(AI 없이).
  /// 끝장면 파일은 지우지 않는다: 방식을 바꿔 뽑아보고 되돌릴 수 있어야 한다.
  Future<void> setVideoMode(Shot shot, VideoMode mode) async {
    if (shotVideoMode(shot) == mode) return;
    _setShotField(shot, Shot.kVideoMode, mode, () => shot.videoMode = mode);
    await save();
    notifyListeners();
  }

  /// 스틸컷 켄번스 효과(없음/줌 인/줌 아웃) 전환.
  Future<void> setStillEffect(Shot shot, StillEffect effect) async {
    if (shotStillEffect(shot) == effect) return;
    _setShotField(
        shot, Shot.kStillEffect, effect, () => shot.stillEffect = effect);
    await save();
    notifyListeners();
  }

  /// 연동을 끊을 때: 앞 샷의 끝장면을 이 샷의 시작 파일로 복사해 남긴다.
  /// 파생 샷이면 그 시작 프레임만 이 트랙 것으로 오버라이드된다.
  Future<void> _materializeStart(Shot shot) async {
    final prev = prevShotOf(shot);
    final srcPath = prev == null ? null : shotEndImage(prev);
    if (srcPath == null) return;
    final src = File(srcPath);
    if (!await src.exists()) return;
    final dst = File('$projectDirPath/${shot.id}_start.${srcPath.split('.').last}');
    await src.copy(dst.path);
    await FileImage(dst).evict();
    _setShotStartImage(shot, dst.path);
  }

  /// FE2V 컷 연속성: [shot]의 끝 프레임이 바뀌면 **다음 샷의 시작**도 바뀐 셈이다
  /// (연동 중이라면 그 시작이 곧 이 끝 파일이므로 — [startPathOf] 참고).
  /// 경로가 그대로라 미리보기 캐시가 옛 그림을 붙들고 있으니 버전만 올려 깨워준다.
  void _refreshLinkedNext(Shot shot) {
    final all = _shotsAround(shot);
    final i = all.indexOf(shot);
    if (i < 0 || i + 1 >= all.length) return; // 마지막 샷 → 이어질 대상 없음
    final next = all[i + 1];
    if (!shotLinkStart(next)) return;
    final k = busyKey(next.id, GenMode.imageStart);
    _ver[k] = (_ver[k] ?? 0) + 1;
  }

  /// LoRA URL 정규화: civitai 페이지 URL → api/download 링크로 변환 + 토큰 자동 부착.
  String _effectiveLoraUrl(VideoTrack? track) {
    var url = (track?.loraUrl ?? '').trim();
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
    final path = shotEndImage(shot);
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

  /// 내보내기 진행 상태 키(트랙 단위) — 버튼 비활성/스피너 표시용.
  String exportBusyKey(VideoTrack track) => 'export:${track.id}';

  /// 씬을 볼 수 있는지(=이 트랙에 실제로 뽑힌 영상이 하나라도 있는지) — 내보내기 버튼 활성 판단.
  bool trackHasVideo(VideoTrack track) {
    for (final beat in track.beats) {
      for (final s in beat.shots) {
        if (_hasFile(videoPathOf(s))) return true;
      }
    }
    return false;
  }

  /// **트랙 하나**를 하나의 mp4로 내보낸다 — 그 트랙의 영상에 대사 음성·효과음·배경음까지 합쳐서.
  /// 영상이 없는 비트는 건너뛴다. 미리보기(영상 재생 팝업)와 같은 규칙(비트 = 영상·대사 중 긴 쪽).
  /// 트랙별 영상/음성은 [videoPathOf]/[voicePathOf]가 그 트랙 것(없으면 기준 상속)으로 해석한다.
  Future<void> exportTrackMovie(VideoTrack track) async {
    final sc = sceneOfTrack(track) ?? selectedScene;
    if (sc == null) return;
    if (!VideoEdit.available) {
      messenger?.call(VideoEdit.missingHint);
      return;
    }
    // 비트마다 영상 클립(상속 포함) + 대사 음성 + 효과음을 모은다. 영상 없는 비트는 뺀다.
    final beats = <ExportBeat>[];
    for (final beat in track.beats) {
      final clips = <String>[
        for (final s in beat.shots)
          if (_hasFile(videoPathOf(s))) videoPathOf(s)!,
      ];
      if (clips.isEmpty) continue;
      // 자막(트랙별 해석). 텍스트가 하나라도 있으면 영상 위에 구워 넣는다.
      final cap = captionOf(beat);
      final expCap = (cap != null && cap.cues.any((c) => c.text.trim().isNotEmpty))
          ? ExportCaption(
              cues: [for (final c in cap.cues) (seconds: c.seconds, text: c.text)],
              position: cap.position.name, // 'top' | 'middle' | 'bottom'
            )
          : null;
      beats.add(ExportBeat(
        clips: clips,
        voice: _hasFile(voicePathOf(beat)) ? voicePathOf(beat) : null,
        sfx: _hasFile(sfxPathOf(beat)) ? sfxPathOf(beat) : null,
        caption: expCap,
      ));
    }
    if (beats.isEmpty) {
      messenger?.call('${trackLabel(track)}에는 생성된 영상이 없습니다');
      return;
    }
    // 파일명: "<씬 제목> - <트랙 이름>.mp4" (못 쓰는 문자만 걸러낸다).
    final title = sc.title.trim().isEmpty ? sc.id : sc.title.trim();
    final base = '$title - ${trackLabel(track)}';
    final safe = base.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    final loc = await fs.getSaveLocation(suggestedName: '$safe.mp4');
    if (loc == null) return;
    final key = exportBusyKey(track);
    _busy.add(key);
    notifyListeners();
    messenger?.call(
        '${trackLabel(track)} 무비 합치는 중… (비트 ${beats.length}개 · 음성·효과음·배경음 합성)');
    try {
      await VideoEdit.exportScene(
        beats: beats,
        bgm: _hasFile(sc.bgmPath) ? sc.bgmPath : null,
        width: sc.videoRes.width,
        height: sc.videoRes.height,
        outPath: loc.path,
        speed: track.speed, // 트랙 배속(미리보기와 동일)
      );
      messenger?.call('${trackLabel(track)} 무비 저장: ${loc.path}');
    } catch (e, st) {
      debugPrint('[trackMovie] 실패: $e\n$st');
      messenger?.call('무비 내보내기 실패: $e');
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  /// 이 트랙이 속한 씬.
  StoryScene? sceneOfTrack(VideoTrack track) {
    for (final sc in _scenes) {
      if (sc.tracks.contains(track)) return sc;
    }
    return null;
  }

  // ───────── 사이드/플레이어 토글 ─────────

  void toggleSceneList() {
    _sceneListOpen = !_sceneListOpen;
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
    for (final c in _shotNotes.values) {
      c.dispose();
    }
    for (final c in _videoNotes.values) {
      c.dispose();
    }
    for (final c in _sceneNotes.values) {
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
