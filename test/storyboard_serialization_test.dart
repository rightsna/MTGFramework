import 'package:framework/src/storyboard/models/character.dart';
import 'package:framework/src/storyboard/models/shot.dart';
import 'package:framework/src/storyboard/models/dialogue.dart';
import 'package:framework/src/storyboard/models/dialogue_beat.dart';
import 'package:framework/src/storyboard/models/sfx.dart';
import 'package:framework/src/storyboard/models/caption.dart';
import 'package:framework/src/storyboard/models/story_scene.dart';
import 'package:framework/src/storyboard/models/video_track.dart';
import 'package:framework/src/storyboard/services/movie_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// `scene<N>.json` 직렬화 검증. 씬 = 대사들의 나열, 각 대사 = 대사(0/1) + 샷들.
/// 자기설명적이고, 미디어는 파일명(상대)만 담기며, 왕복 후 값이 보존되는지.
/// (구형식 마이그레이션은 없다 — 데이터를 한 번에 옮기고 코드에서 걷어냈다.)
void main() {
  const dir = '/proj/abc';

  StoryScene sampleScene() => StoryScene(
        id: 'scene_1',
        title: '오프닝',
        commonPrompt: '세로 9:16, 애니풍',
        bgmPrompt: 'cinematic, ambient, calm, piano',
        bgmSeconds: 45,
        bgmPath: '$dir/scene_1_bgm.mp3',
        tracks: [
          VideoTrack(
              id: 'track_1',
              name: '트랙 1',
              defaultVoiceId: 'voice_narrator',
              defaultVoiceName: '내레이터',
              beats: [
          // 대사 있는 대사 — 샷 2개(첫 샷 립싱크 + 컷어웨이).
          DialogueBeat(
            id: 'shot_1',
            title: '첫 컷',
            note: '역광 주의 · 클라 요청으로 톤 어둡게',
            dialogue: Dialogue(
              speakerId: 'char_miles',
              text: '형사님, 그 밤에 무슨 일이 있었죠?',
              voicePath: '$dir/shot_1_voice.mp3',
              voiceSeconds: 5.4,
            ),
            shots: [
              Shot(
                id: 'clip_1',
                videoPrompt: '카메라 천천히 전진',
                videoSeconds: 3,
                startImagePath: '$dir/clip_1_start.png',
                endImagePath: '$dir/clip_1_end.png',
                videoPath: '$dir/clip_1_vlow.mp4',
              ),
              Shot(
                id: 'clip_2',
                videoSeconds: 3,
              ),
            ],
          ),
          // 무음 대사(대사 없음) — establishing 샷 1개.
          DialogueBeat(
            id: 'shot_2',
            shots: [Shot(id: 'clip_3')],
          ),
          ]),
        ],
      );

  test('JSON은 대사 나열 + 각 대사=대사(0/1)+샷들 + 미디어는 파일명(상대)만', () {
    final j = sampleScene().toJson();

    // 기본 성우는 트랙별로 옮겨 씬 최상위에는 더 이상 없다(트랙 JSON 안에 있다).
    expect(j.keys, containsAll(['id', 'title', 'commonPrompt', 'tracks', 'bgm']));
    expect(j.keys, isNot(contains('lora')));
    expect(j.keys, isNot(contains('voice')));
    expect(j['bgm'], {
      'prompt': 'cinematic, ambient, calm, piano',
      'seconds': 45,
      'file': 'scene_1_bgm.mp3',
    });

    // 씬 > 트랙 > 비트 — 트랙 1(기준)의 비트들을 본다.
    final tracks = j['tracks'] as List;
    expect(tracks.length, 1);
    expect((tracks.first as Map)['backend'], 'serviceApi');
    // 기본 성우가 트랙 JSON에 적힌다. (LoRA는 기능째 없어져 아예 안 적힌다.)
    expect((tracks.first as Map).containsKey('lora'), isFalse);
    expect((tracks.first as Map)['voice'],
        {'id': 'voice_narrator', 'name': '내레이터'});
    final dialogues = (tracks.first as Map)['beats'] as List;
    expect(dialogues.length, 2);

    // 대사1: 상태·메모·대사 + 샷 2개.
    final s1 = dialogues.first as Map;
    expect(s1['note'], '역광 주의 · 클라 요청으로 톤 어둡게');
    expect(s1['dialogue'], {
      'speaker': 'char_miles',
      'text': '형사님, 그 밤에 무슨 일이 있었죠?',
      'voice': {'file': 'shot_1_voice.mp3', 'seconds': 5.4},
    });
    final clips1 = s1['shots'] as List;
    expect(clips1.length, 2);
    final c1 = clips1.first as Map;
    // 프레임은 그림만 남는다 — 프롬프트·인물참조(로컬 이미지 생성)는 기능째 걷어냈다.
    expect(c1['startScene'], {'image': 'clip_1_start.png'});
    expect(c1.containsKey('refCharacters'), isFalse);
    // mode = 영상 생성 방식(fe2v/i2v/still). 기본은 fe2v. stillEffect = 스틸컷 켄번스(기본 none).
    // negativePrompt = 빼고 싶은 것만 적는 칸(비면 서버 워크플로 기본 네거티브).
    expect(c1['video'], {
      'prompt': '카메라 천천히 전진',
      'promptKo': '',
      'negativePrompt': '',
      'seconds': 3.0, // 길이는 double 하나로 통일(스틸컷 0.1초·AI 정수 초 공용)
      'actualSeconds': null, // 아직 안 재본 것(뽑고 나면 실제 길이가 들어간다)
      'file': 'clip_1_vlow.mp4',
      'jobId': null, // 비동기 생성 중인 서버 job_id(없으면 null)
      'mode': 'fe2v',
      'stillEffect': 'none',
      'note': '', // 영상 탭 메모(장면 메모와 별개)
    });

    // 샷2: 무음(dialogue=null).
    final s2 = dialogues[1] as Map;
    expect(s2['dialogue'], isNull);
    expect((s2['shots'] as List).length, 1);

    // 절대경로 없음.
    expect(j.toString(), isNot(contains('/proj/abc')));
  });

  test('왕복 후 값 보존 + 미디어는 dir 기준 절대경로로 복원', () {
    final after = StoryScene.fromJson(sampleScene().toJson(), dir);

    expect(after.id, 'scene_1');
    expect(after.commonPrompt, '세로 9:16, 애니풍');
    expect(after.bgmPath, '$dir/scene_1_bgm.mp3');
    // 기본 성우는 트랙 단위로 왕복 보존된다.
    expect(after.tracks.first.defaultVoiceId, 'voice_narrator');
    expect(after.tracks.first.defaultVoiceName, '내레이터');
    expect(after.beats.length, 2);

    final s1 = after.beats.first;
    expect(s1.note, '역광 주의 · 클라 요청으로 톤 어둡게');
    expect(s1.hasDialogue, isTrue);
    expect(s1.dialogue!.speakerId, 'char_miles');
    expect(s1.dialogue!.text, '형사님, 그 밤에 무슨 일이 있었죠?');
    expect(s1.dialogue!.voicePath, '$dir/shot_1_voice.mp3');
    expect(s1.dialogue!.voiceSeconds, 5.4);
    expect(s1.dialogue!.hasVoice, isTrue);
    // 실제 길이 = 샷 길이 합(3+3=6). 재생되는 건 영상이고 음성은 그 위에 얹히는 트랙.
    expect(s1.seconds, 6.0);
    expect(s1.shotSeconds, 6);
    // 음성 길이(5.4)는 샷들이 덮어야 할 '목표'. 차이 0.6s = 음성 뒤 여백.
    expect(s1.targetSeconds, 5.4);
    expect(s1.coverageGap, closeTo(0.6, 1e-9));

    expect(s1.shots.length, 2);
    final c1 = s1.shots.first;
    expect(c1.endImagePath, '$dir/clip_1_end.png');
    expect(c1.startImagePath, '$dir/clip_1_start.png');
    expect(c1.videoPath, '$dir/clip_1_vlow.mp4');

    // 무음 대사: 대사 없음 → 길이는 샷 길이 합.
    final s2 = after.beats[1];
    expect(s2.hasDialogue, isFalse);
    expect(s2.dialogue, isNull);
    expect(s2.seconds, s2.shotSeconds.toDouble());

    // 씬 전체 길이 = 각 대사의 실제 길이(샷 합) 합 — 음성 길이(5.4)가 아니라 영상 기준.
    expect(after.totalSeconds, s1.shotSeconds + s2.shotSeconds);
    expect(after.shotCount, 3);
  });

  test('영상 네거티브 프롬프트 왕복 + 옛 데이터는 빈 값', () {
    final shot = Shot(
      id: 'clip_neg',
      videoPrompt: 'the hand presses the button',
      videoNegativePrompt: 'hand, text, watermark',
    );
    final j = shot.toJson();
    expect((j['video'] as Map)['negativePrompt'], 'hand, text, watermark');

    final back = Shot.fromJson(j, dir);
    expect(back.videoNegativePrompt, 'hand, text, watermark');

    // 'negativePrompt' 키가 없던 옛 데이터 — 빈 값으로 읽혀 서버 기본 네거티브를 쓴다.
    // 옛 'i2v' bool은 새 videoMode로 매핑된다(true→i2v, false/없음→fe2v).
    final old = Shot.fromJson({
      'id': 'clip_old',
      'video': {'prompt': 'x', 'seconds': 3, 'i2v': false},
    }, dir);
    expect(old.videoNegativePrompt, '');
    expect(old.videoMode, VideoMode.fe2v);
    final oldI2v = Shot.fromJson({
      'id': 'clip_old2',
      'video': {'prompt': 'x', 'seconds': 3, 'i2v': true},
    }, dir);
    expect(oldI2v.videoMode, VideoMode.i2v);
  });

  test('진행 중 영상 job_id는 왕복 보존된다 — 앱 재시작 후 매칭·이어받기의 근거', () {
    // 기준 샷: 제출됐지만 아직 결과 없음(videoJobId 있고 videoPath 없음).
    final base = Shot(id: 'clip_job', videoJobId: 'job-abc-123');
    final back = Shot.fromJson(base.toJson(), dir);
    expect(back.videoJobId, 'job-abc-123'); // 재시작해도 어떤 job이었는지 그대로
    expect(back.videoPath, isNull);

    // 파생 샷(트랙2)도 자기 job_id를 따로 소유·보존한다.
    final derived = Shot(id: 'clip_job_d', baseId: 'clip_job', videoJobId: 'job-def-456');
    final backD = Shot.fromJson(derived.toJson(), dir);
    expect(backD.videoJobId, 'job-def-456');

    // 완료 후엔 job_id가 없고 파일만 남는 상태도 정상 왕복.
    final done = Shot(id: 'clip_done', videoPath: '$dir/clip_done_vlow.mp4');
    final backDone = Shot.fromJson(done.toJson(), dir);
    expect(backDone.videoJobId, isNull);
    expect(backDone.videoPath, '$dir/clip_done_vlow.mp4');
  });

  test('폴더가 이동해도 미디어 경로가 새 dir 기준으로 복원된다', () {
    final moved = StoryScene.fromJson(sampleScene().toJson(), '/new/home');
    expect(moved.bgmPath, '/new/home/scene_1_bgm.mp3');
    expect(moved.beats.first.dialogue!.voicePath, '/new/home/shot_1_voice.mp3');
    expect(moved.beats.first.shots.first.startImagePath,
        '/new/home/clip_1_start.png');
  });

  test('대사(값 객체 · id 없음) 자기설명 + 화자 없는 줄(내레이션) 왕복', () {
    final line = Dialogue(
      speakerId: 'char_x',
      text: '안녕하세요',
      voicePath: '$dir/x_voice.mp3',
      voiceSeconds: 1.2,
    );
    final j = line.toJson();
    expect(j, {
      'speaker': 'char_x',
      'text': '안녕하세요',
      'voice': {'file': 'x_voice.mp3', 'seconds': 1.2},
    });
    expect(j.containsKey('id'), isFalse);

    final back = Dialogue.fromJson(j, '/new/home');
    expect(back.speakerId, 'char_x');
    expect(back.voicePath, '/new/home/x_voice.mp3');
    expect(back.voiceSeconds, 1.2);
    expect(back.hasVoice, isTrue);

    // 내레이션(화자 없음).
    final narr = Dialogue.fromJson(Dialogue(text: '밤이 깊었다').toJson(), dir);
    expect(narr.speakerId, isNull);
    expect(narr.hasVoice, isFalse);
  });

  test('빠진 키는 기본값으로 — 씬/대사 최소 JSON', () {
    // 구스키마 폴백은 제거됐다(데이터는 정본 스키마로 마이그레이션 완료).
    // 키가 아예 없을 때 터지지 않고 기본값으로 읽히는지만 본다.
    final sc = StoryScene.fromJson({'id': 'scene_min'}, dir);
    expect(sc.beats, isEmpty);
    expect(sc.tracks.length, 1, reason: '트랙이 없으면 기준 트랙 하나로 시작한다');
    expect(sc.bgmSeconds, 30);
    expect(sc.bgmPath, isNull);

    final beat = DialogueBeat.fromJson({'id': 'b_min'}, dir);
    expect(beat.shots, isEmpty);
    expect(beat.dialogue, isNull);
  });

  test('영상 해상도는 트랙 JSON에 적히고 왕복 보존된다', () {
    final sc = sampleScene();
    sc.baseTrack.videoRes = VideoRes.p704x1280;
    final j = sc.toJson();

    // 씬에는 프레임 해상도만 남는다 — 영상 해상도는 트랙 것이다.
    expect((j['res'] as Map).containsKey('video'), isFalse);
    expect((j['res'] as Map)['image'], isNotNull);
    expect(((j['tracks'] as List).first as Map)['res'], {'video': 'p704x1280'});

    final after = StoryScene.fromJson(j, dir);
    expect(after.baseTrack.videoRes, VideoRes.p704x1280);
  });

  test('트랙마다 다른 해상도를 갖는다 — 씬은 프레임 해상도만', () {
    final sc = StoryScene.fromJson({
      'id': 'scene_res',
      'res': {'image': 'p704x1280'},
      'tracks': [
        {
          'id': 't1',
          'name': '트랙 1',
          'res': {'video': 'p544x960'},
        },
        {
          'id': 't2',
          'name': '트랙 2',
          'res': {'video': 'p352x640'},
        },
      ],
    }, dir);

    expect(sc.tracks.first.videoRes, VideoRes.p544x960);
    expect(sc.tracks.last.videoRes, VideoRes.p352x640);
    expect(sc.imageRes, ImageRes.p704x1280, reason: '프레임 해상도는 씬에 남는다');
  });

  test('Veo 파라미터는 트랙 해상도에서 유도된다', () {
    expect(VideoRes.p352x640.veoAspect, '9:16');
    expect(VideoRes.l1280x704.veoAspect, '16:9');
    expect(VideoRes.p352x640.veoResolution, '720p', reason: '긴 변 640 ≤ 720');
    expect(VideoRes.p544x960.veoResolution, '1080p', reason: '긴 변 960 > 720');
  });

  test('IA2V 방식은 왕복 보존되고 끝 프레임을 요구하지 않는다', () {
    final shot = Shot(id: 'c_ia', videoMode: VideoMode.ia2v);
    expect((shot.toJson()['video'] as Map)['mode'], 'ia2v');

    final back = Shot.fromJson(shot.toJson(), dir);
    expect(back.resolvedVideoMode(null), VideoMode.ia2v);
    expect(back.needsEndFrameWith(null), isFalse,
        reason: '끝 프레임은 서버가 시작 프레임으로 물린다 — 사람이 만들 필요 없다');
    // 시작 프레임만 있으면 뽑을 준비가 된 것으로 본다(음성 유무는 생성 시점에 본다).
    final ready = Shot.fromJson(
        (Shot(id: 'c_ia2', videoMode: VideoMode.ia2v, startImagePath: '$dir/a.png')
            .toJson()),
        dir);
    expect(ready.videoInputsReadyWith(null), isTrue);
  });

  test('효과음(SFX)은 **샷**에 저장되고 왕복 보존, 파생 샷은 오버라이드로만 적힌다', () {
    final base = Shot(
      id: 'c1',
      sfx: Sfx(
        prompt: 'deep cinematic impact boom',
        durationSeconds: 1.6,
        promptInfluence: 0.6,
        path: '$dir/c1_sfx.mp3',
        soundSeconds: 1.55,
      ),
    );
    final j = base.toJson();
    final sfxJson = j['sfx'] as Map;
    expect(sfxJson['prompt'], 'deep cinematic impact boom');
    expect(sfxJson['durationSeconds'], 1.6);
    expect(sfxJson['promptInfluence'], 0.6);
    expect((sfxJson['sound'] as Map)['file'], 'c1_sfx.mp3'); // 파일명(상대)만

    final back = Shot.fromJson(j, dir);
    expect(back.sfx!.prompt, 'deep cinematic impact boom');
    expect(back.sfx!.durationSeconds, 1.6);
    expect(back.sfx!.promptInfluence, 0.6);
    expect(back.sfx!.path, '$dir/c1_sfx.mp3'); // 절대경로로 복원
    expect(back.sfx!.hasSound, isTrue);
    expect(back.resolvedSfx(null)!.prompt, 'deep cinematic impact boom');

    // 파생 샷: 손대기 전엔 아무것도 안 적히고(기준 샷 상속), 손대면 overrides로 간다.
    final inherit = Shot(id: 'c1_t2', baseId: 'c1');
    expect((inherit.toJson()['overrides'] as Map).containsKey('sfx'), isFalse);
    expect(inherit.resolvedSfx(back)!.prompt, 'deep cinematic impact boom',
        reason: '상속으로 기준 샷 효과음이 들린다');

    inherit.overrides[Shot.kSfx] = Sfx(prompt: 'glass shatter');
    final ov = Shot.fromJson(inherit.toJson(), dir);
    expect(ov.resolvedSfx(back)!.prompt, 'glass shatter', reason: '자기 것 우선');
  });

  test('자막(캡션)은 구간 목록·위치가 왕복 보존되고, 파생 비트엔 안 적힌다', () {
    final base = DialogueBeat(
      id: 'b2',
      caption: Caption(
        position: CaptionPosition.top,
        cues: [
          CaptionCue(seconds: 1, text: '완전히'),
          CaptionCue(seconds: 3, text: ''), // 공백 구간
          CaptionCue(seconds: 3, text: '다른 사람이 나타났다'),
        ],
      ),
    );
    final back = DialogueBeat.fromJson(base.toJson(), dir);
    expect(back.caption!.position, CaptionPosition.top);
    expect(back.caption!.cues.length, 3);
    expect(back.caption!.cues[0].seconds, 1);
    expect(back.caption!.cues[0].text, '완전히');
    expect(back.caption!.cues[1].text, ''); // 공백 유지
    expect(back.caption!.cues[2].text, '다른 사람이 나타났다');
    expect(back.caption!.totalSeconds, 7);

    final derived =
        DialogueBeat(id: 'b2_t2', baseId: 'b2', caption: Caption());
    expect(derived.toJson().containsKey('caption'), isFalse);
  });

  test('새 대사 기본값 + 끝장면(샷) 왕복', () {
    expect(DialogueBeat(id: 'x').hasDialogue, isFalse);

    // 끝 이미지/프롬프트가 보존된다(FE2V 필수 프레임).
    final withEnd = Shot.fromJson({
      'id': 'y',
      'startScene': {'image': null},
      'endScene': {'image': 'y_end.png'},
    }, dir);
    expect(withEnd.endImagePath, '$dir/y_end.png');
  });

  test('Character 직렬화 — 미디어 파일명(상대) + 목소리 + 왕복 + 대표 폴백', () {
    final c = Character(
      id: 'char_1',
      name: '마일스 머서',
      description: '은퇴 형사',
      coverImagePath: '$dir/char_1_cover.png',
      photoPaths: ['$dir/char_1_cover.png', '$dir/char_1_a.png'],
      voiceId: 'el_abc123',
      voiceName: '중년 남성 · 낮고 건조',
    );
    final j = c.toJson();
    expect(j['cover'], 'char_1_cover.png');
    expect(j['photos'], ['char_1_cover.png', 'char_1_a.png']);
    expect(j['voiceId'], 'el_abc123');
    expect(j['voiceName'], '중년 남성 · 낮고 건조');
    expect(j.toString(), isNot(contains('/proj/abc')));

    final back = Character.fromJson(j, dir);
    expect(back.name, '마일스 머서');
    expect(back.coverImagePath, '$dir/char_1_cover.png');
    expect(back.voiceId, 'el_abc123');
    expect(back.hasVoice, isTrue);

    expect(Character(id: 'c3').hasVoice, isFalse);
    expect(Character(id: 'c2', photoPaths: ['$dir/x.png']).cover, '$dir/x.png');
    expect(Character.fromJson(j, '/new/home').coverImagePath,
        '/new/home/char_1_cover.png');
  });
}
