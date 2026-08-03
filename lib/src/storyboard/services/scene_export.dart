import 'dart:io';

import '../models/caption.dart';
import '../models/dialogue_beat.dart';
import '../models/sfx.dart';
import '../models/shot.dart';
import '../models/story_scene.dart';
import '../models/text_overlay.dart';
import '../models/video_track.dart';
import 'movie_settings.dart'; // VideoRes
import 'video_edit.dart';

/// 씬 하나 안에서 **트랙 상속을 해석**하는 순수 Dart 리졸버.
///
/// 파생 트랙(트랙2…)의 비트·샷은 손댄 필드만 갖고 나머지는 기준 트랙을 따라간다
/// ([DialogueBeat.overrides] / [Shot.overrides]). 그래서 "이 자리에 실제로 걸리는 값"은
/// 언제나 **기준 짝을 찾아서** 물어야 하는데, 그 짝 찾기가 씬 전체를 뒤지는 일이라
/// 지금까지 `StoryboardProvider`(Flutter)에만 있었다.
///
/// 이 클래스는 그 해석을 **씬 데이터만으로** 다시 세운 것이다. Flutter를 안 물기 때문에
/// GUI(provider가 여기로 위임)와 CLI(`bin/storyboard_export.dart`)가 같은 규칙을 쓴다 —
/// 내보내기 규칙이 두 벌로 갈라지지 않게 하는 게 이 파일의 존재 이유다.
class SceneResolver {
  SceneResolver(this.scene);
  final StoryScene scene;

  // ───────── 기준 짝 찾기 ─────────

  /// 파생 샷이 비추고 있는 **기준 트랙의 짝**. 기준 트랙 샷이면 null.
  Shot? baseShotOf(Shot shot) {
    final baseId = shot.baseId;
    if (baseId == null) return null;
    for (final beat in scene.baseTrack.beats) {
      for (final s in beat.shots) {
        if (s.id == baseId) return s;
      }
    }
    return null;
  }

  /// 파생 비트가 비추고 있는 기준 비트. 기준 트랙 비트면 null.
  DialogueBeat? baseBeatOf(DialogueBeat beat) {
    final baseId = beat.baseId;
    if (baseId == null) return null;
    for (final b in scene.baseTrack.beats) {
      if (b.id == baseId) return b;
    }
    return null;
  }

  /// 이 샷이 속한 트랙(이 씬 안에서).
  VideoTrack? trackOf(Shot shot) {
    for (final t in scene.tracks) {
      for (final beat in t.beats) {
        if (beat.shots.contains(shot)) return t;
      }
    }
    return null;
  }

  // ───────── 필드 해석(상속/오버라이드) ─────────

  /// 이 샷 자리에 **걸리는** 영상 — 자기 트랙에서 뽑았으면 그것, 없으면 기준 트랙 것 상속.
  String? videoPathOf(Shot s) => s.resolvedVideoPath(baseShotOf(s));

  /// 이 비트 자리에 **들리는** 대사 음성 — 자기 것 우선, 없으면 기준 트랙 것 상속.
  String? voicePathOf(DialogueBeat b) => b.resolvedVoicePath(baseBeatOf(b));

  /// 효과음은 **샷 단위**다(비트가 아니라). 기준 샷 것을 상속하되 파생이 손대면 그것.
  Sfx? sfxOf(Shot s) => s.resolvedSfx(baseShotOf(s));
  String? sfxPathOf(Shot s) => sfxOf(s)?.path;

  /// 이 샷 자리에 **구워질 글씨**(타이틀 카드·썸네일). 문구가 비었으면 null로 본다 —
  /// 빈 글씨를 굽겠다고 ffmpeg에 필터를 태울 이유가 없다.
  TextOverlay? textOverlayOf(Shot s) {
    final o = s.resolvedTextOverlay(baseShotOf(s));
    return (o != null && o.hasText) ? o : null;
  }
  Caption? captionOf(DialogueBeat b) => b.resolvedCaption(baseBeatOf(b));

  double shotVideoSeconds(Shot s) => s.resolvedVideoSeconds(baseShotOf(s));

  /// 이 샷의 영상 해상도 — **트랙 단위**다(생성·스틸컷·내보내기 캔버스가 같은 값을 쓴다).
  /// 트랙을 못 찾으면 기준 트랙 값으로 떨어진다.
  VideoRes videoResOf(Shot s) =>
      (trackOf(s) ?? scene.baseTrack).videoRes;
  VideoMode shotVideoMode(Shot s) => s.resolvedVideoMode(baseShotOf(s));
  StillEffect shotStillEffect(Shot s) => s.resolvedStillEffect(baseShotOf(s));
  String? shotStartImage(Shot s) => s.resolvedStartImage(baseShotOf(s));
  String? shotEndImage(Shot s) => s.resolvedEndImage(baseShotOf(s));
  String shotTitle(Shot s) => s.resolvedTitle(baseShotOf(s));
  String beatTitle(DialogueBeat b) => b.resolvedTitle(baseBeatOf(b));

  /// 트랙 나열 기준 [shot]의 바로 앞 샷(대사 경계는 건너뛴다). 첫 샷이면 null.
  Shot? prevShotOf(Shot shot) {
    final track = trackOf(shot);
    if (track == null) return null;
    final all = [for (final beat in track.beats) ...beat.shots];
    final i = all.indexOf(shot);
    return i <= 0 ? null : all[i - 1];
  }

  /// 이 샷의 시작 프레임. (앞 샷에서 가져오는 건 한 번짜리 동작이라 여기서 볼 게 없다 —
  /// 가져온 순간 이 샷의 자기 파일이 된다.)
  String? startPathOf(Shot shot) => shotStartImage(shot);

  // ───────── 트랙 단위 상태 ─────────

  /// 트랙 표시 이름 — 비어 있으면 순서로 부른다(GUI 라벨과 같은 규칙).
  String trackLabel(VideoTrack t) {
    if (t.name.trim().isNotEmpty) return t.name.trim();
    final i = scene.tracks.indexOf(t);
    return '트랙 ${i < 0 ? '?' : i + 1}';
  }

  /// 이 샷 자리에 **무엇이 몇 초 걸리는지** — 해석은 여기 한 번뿐이다.
  /// 영상이 없으면 시작 프레임을 그 자리에 세운다(그것도 없으면 빈 자리).
  ShotSlot slotOf(DialogueBeat beat, Shot s) {
    final video = videoPathOf(s);
    final hasVideo = hasFile(video);
    final img = hasVideo ? null : startPathOf(s);
    return ShotSlot(
      beat: beat,
      shot: s,
      videoPath: hasVideo ? video : null,
      imagePath: hasFile(img) ? img : null,
      seconds: shotVideoSeconds(s),
      isStillMode: shotVideoMode(s) == VideoMode.still,
    );
  }

  /// 트랙의 모든 샷 자리를 순서대로. **미리보기와 내보내기가 이걸 같이 읽는다** —
  /// 재생에서 본 것과 내보낸 결과가 어긋나지 않으려면 자리 해석이 한 벌이어야 한다.
  List<ShotSlot> slots(VideoTrack track) => [
        for (final beat in track.beats)
          for (final s in beat.shots) slotOf(beat, s),
      ];

  /// 아직 안 구운 스틸컷 샷들 — 방식이 스틸이고, 걸린 영상이 없고, 시작 프레임은 있는 것.
  /// 스틸컷은 AI가 아니라 로컬 ffmpeg 산출물이라 내보내기가 직접 채워도 된다.
  List<Shot> pendingStills(VideoTrack track) => [
        for (final slot in slots(track))
          if (slot.canBakeStill) slot.shot,
      ];

  /// 내보낼 게 있는지 — 걸린 영상이 하나라도 있거나, 여기서 구울 스틸컷이 있으면 참.
  bool trackHasVideo(VideoTrack track) {
    for (final beat in track.beats) {
      for (final s in beat.shots) {
        if (hasFile(videoPathOf(s))) return true;
      }
    }
    return pendingStills(track).isNotEmpty;
  }

  /// 파일이 실제로 있는지(경로가 비었거나 지워졌으면 false).
  static bool hasFile(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();
}

/// 타임라인의 한 자리(샷 하나) — "여기에 무엇이 몇 초 걸리는가"만 말한다.
/// [SceneResolver.slotOf]가 만들고, 미리보기(재생 목록)와 내보내기가 함께 읽는다.
class ShotSlot {
  const ShotSlot({
    required this.beat,
    required this.shot,
    required this.videoPath,
    required this.imagePath,
    required this.seconds,
    required this.isStillMode,
  });

  final DialogueBeat beat;
  final Shot shot;

  /// 이 자리에 걸린 영상(상속 해석 + 파일 존재 확인까지 끝난 것). 없으면 null.
  final String? videoPath;

  /// 영상이 없을 때 대신 세울 시작 프레임. 이것도 없으면 빈 자리(검은 화면).
  final String? imagePath;

  /// 이 자리가 차지하는 길이(초) — 주문한 길이. 실제 재생은 대사와 긴 쪽을 따른다.
  final double seconds;

  /// 스틸컷 방식인지 — 영상이 없어도 로컬 ffmpeg로 구울 수 있는 자리라는 뜻.
  final bool isStillMode;

  /// 내보내기가 지금 구울 수 있는 스틸컷 자리인지.
  bool get canBakeStill =>
      isStillMode && videoPath == null && imagePath != null;
}

/// 트랙 하나를 mp4 하나로 내보낸 결과.
class ExportResult {
  const ExportResult({
    required this.outPath,
    required this.beats,
    required this.skippedBeats,
    required this.stillsRendered,
    required this.stillsFailed,
    required this.changed,
  });

  /// 실제로 쓴 파일 경로.
  final String outPath;

  /// 무비에 들어간 비트 수.
  final int beats;

  /// 영상이 없어 빠진 비트 수.
  final int skippedBeats;

  /// 내보내면서 새로 구운 스틸컷 수.
  final int stillsRendered;

  /// 굽다 실패한 스틸컷 수(그 비트는 빠진다).
  final int stillsFailed;

  /// 씬 데이터가 바뀌었는지(스틸컷을 구워 videoPath가 채워짐) — 부르는 쪽이 저장해야 한다.
  final bool changed;

  /// 사람에게 보여 줄 "빠진 것" 요약. 빠진 게 없으면 빈 문자열.
  String get droppedNote {
    final parts = [
      if (skippedBeats > 0) '영상 없는 비트 $skippedBeats개 제외',
      if (stillsFailed > 0) '스틸컷 영상 생성 실패 $stillsFailed개',
    ];
    return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
  }
}

/// 내보낼 게 하나도 없을 때(영상 0개, 구울 스틸컷도 0개) 던진다 — 부르는 쪽이 안내만 하면 된다.
class NothingToExportException implements Exception {
  NothingToExportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// **트랙 하나 → mp4 하나**. GUI 버튼과 CLI가 공유하는 내보내기 본체.
///
/// 하는 일 순서대로:
///  1. 안 구운 스틸컷을 먼저 굽는다 — 스틸은 AI가 아니라 시작 프레임 + 길이만으로 정해지는
///     로컬 산출물인데, 샷마다 생성을 눌러야 했던 탓에 대사만 다 넣고 내보내면 스틸 비트가
///     통째로 빠진 몇 초짜리 무비가 나왔다.
///  2. 비트마다 영상 클립(상속 포함) + 대사 음성 + 효과음 + 자막을 모은다. 영상 없는 비트는 뺀다.
///  3. [VideoEdit.exportScene]으로 굽는다(비트 길이 = 영상·대사 중 긴 쪽, 배경음은 전체에).
///
/// 빠진 비트는 조용히 넘어가지 않고 [ExportResult]에 개수로 남는다 — 짧은 무비가 말없이
/// 나오는 게 제일 나쁘다.
class SceneExporter {
  /// 저장 파일 이름 제안 — `<씬 제목> - <트랙 이름>.mp4` (파일명에 못 쓰는 문자만 걸러낸다).
  static String suggestedName(StoryScene scene, VideoTrack track) {
    final r = SceneResolver(scene);
    final title = scene.title.trim().isEmpty ? scene.id : scene.title.trim();
    final base = '$title - ${r.trackLabel(track)}';
    return '${base.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')}.mp4';
  }

  /// [track]을 [outPath] 하나로 굽는다.
  ///
  /// [speed]를 주면 그 배속으로(트랙 설정은 안 건드린다), 안 주면 [VideoTrack.speed]로.
  /// [onProgress]는 진행 문구, [onFileWritten]은 파일을 새로 쓴 뒤 부르는 훅
  /// (GUI는 여기서 이미지 캐시를 비운다), [measureSeconds]는 길이 실측 방식 주입
  /// (안 주면 ffprobe). 셋 다 선택 — 없으면 조용히 돈다.
  static Future<ExportResult> exportTrack({
    required StoryScene scene,
    required VideoTrack track,
    required String outPath,
    required String projectDirPath,
    double? speed,
    void Function(String message)? onProgress,
    Future<void> Function(File file)? onFileWritten,
    Future<double?> Function(File file)? measureSeconds,
  }) async {
    final r = SceneResolver(scene);
    if (!VideoEdit.available) throw Exception(VideoEdit.missingHint);
    if (!r.trackHasVideo(track)) {
      throw NothingToExportException(
          '${r.trackLabel(track)}에는 생성된 영상이 없습니다');
    }

    // 1) 안 구운 스틸컷 — 실패한 샷은 빈 자리로 남고 아래에서 '빠진 비트'로 잡힌다.
    final pending = r.pendingStills(track);
    var stillsRendered = 0, stillsFailed = 0;
    for (var i = 0; i < pending.length; i++) {
      onProgress?.call('스틸컷 영상 ${i + 1}/${pending.length} 만드는 중…');
      try {
        await renderStill(
          scene: scene,
          shot: pending[i],
          projectDirPath: projectDirPath,
          onFileWritten: onFileWritten,
          measureSeconds: measureSeconds,
        );
        stillsRendered++;
      } catch (_) {
        stillsFailed++;
      }
    }

    // 2) 비트별 클립·오디오·자막 수집.
    final beats = <ExportBeat>[];
    var skipped = 0;
    for (final beat in track.beats) {
      // 자리 해석은 리졸버 하나로 — 미리보기가 세운 것과 같은 자리를 본다.
      // (영상 없는 자리는 굽지 못하니 여기선 빠진다. 미리보기는 시작 프레임으로 세운다.)
      final clips = <String>[];
      // 효과음은 **샷 단위**라 "몇 번째 클립에서 시작하는지"를 함께 넘긴다 —
      // 그 자리까지의 클립 길이 합이 비트 안 오프셋이 된다(길이 실측은 굽는 쪽에서).
      final sfx = <({int clipIndex, String path})>[];
      for (final slot in beat.shots.map((s) => r.slotOf(beat, s))) {
        if (slot.videoPath == null) continue; // 영상 없는 자리는 못 굽는다
        final sp = r.sfxPathOf(slot.shot);
        if (SceneResolver.hasFile(sp)) {
          sfx.add((clipIndex: clips.length, path: sp!));
        }
        clips.add(slot.videoPath!);
      }
      if (clips.isEmpty) {
        skipped++;
        continue;
      }
      // 자막(트랙별 해석). 텍스트가 하나라도 있으면 영상 위에 구워 넣는다.
      final cap = r.captionOf(beat);
      final expCap =
          (cap != null && cap.cues.any((c) => c.text.trim().isNotEmpty))
              ? ExportCaption(
                  cues: [
                    for (final c in cap.cues) (seconds: c.seconds, text: c.text)
                  ],
                  position: cap.position.name, // 'top' | 'middle' | 'bottom'
                )
              : null;
      final voice = r.voicePathOf(beat);
      beats.add(ExportBeat(
        clips: clips,
        voice: SceneResolver.hasFile(voice) ? voice : null,
        sfx: sfx,
        caption: expCap,
      ));
    }
    if (beats.isEmpty) {
      throw NothingToExportException(
          '${r.trackLabel(track)}에는 생성된 영상이 없습니다');
    }

    // 3) 굽는다.
    onProgress?.call('${r.trackLabel(track)} 무비 합치는 중… '
        '(비트 ${beats.length}개 · 음성·효과음·배경음 합성)');
    await VideoEdit.exportScene(
      beats: beats,
      bgm: SceneResolver.hasFile(scene.bgmPath) ? scene.bgmPath : null,
      width: track.videoRes.width, // 캔버스는 **그 트랙**의 해상도
      height: track.videoRes.height,
      outPath: outPath,
      speed: speed ?? track.speed,
    );
    return ExportResult(
      outPath: outPath,
      beats: beats.length,
      skippedBeats: skipped,
      stillsRendered: stillsRendered,
      stillsFailed: stillsFailed,
      changed: stillsRendered > 0,
    );
  }

  /// 스틸컷 한 샷을 굽는다(AI 없이 시작 프레임 한 장을 영상 길이만큼 채운다).
  /// 결과는 FE2V와 같은 슬롯(`<id>_vlow.mp4`)에 들어가고 [Shot.videoPath]가 채워진다 —
  /// 저장은 부르는 쪽 몫.
  static Future<void> renderStill({
    required StoryScene scene,
    required Shot shot,
    required String projectDirPath,
    Future<void> Function(File file)? onFileWritten,
    Future<double?> Function(File file)? measureSeconds,
  }) async {
    final r = SceneResolver(scene);
    final img = r.startPathOf(shot); // 연동 포함 시작 프레임
    if (!SceneResolver.hasFile(img)) throw Exception('시작 프레임이 없습니다');
    final out = '$projectDirPath/${shot.id}_vlow.mp4';
    await VideoEdit.stillClip(
      image: img!,
      outPath: out,
      seconds: r.shotVideoSeconds(shot), // 0.1초 단위 그대로(상속/오버라이드 해석)
      effect: r.shotStillEffect(shot),
      width: r.videoResOf(shot).width, // 트랙 단위 해상도
      height: r.videoResOf(shot).height,
      overlay: r.textOverlayOf(shot), // 타이틀 카드·썸네일 글씨(있으면 프레임에 굽는다)
    );
    final f = File(out);
    await onFileWritten?.call(f);
    shot.videoPath = f.path;
    shot.videoActualSeconds = measureSeconds != null
        ? await measureSeconds(f)
        : await _probeSeconds(f);
  }

  /// 길이 실측 기본값 — ffprobe. 못 재면 null(0을 저장하면 화면이 0초로 굳는다).
  static Future<double?> _probeSeconds(File f) async {
    final s = await VideoEdit.mediaSeconds(f.path);
    return s > 0 ? s : null;
  }
}
