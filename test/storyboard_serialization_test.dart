import 'package:framework/src/storyboard/models/character.dart';
import 'package:framework/src/storyboard/models/shot.dart';
import 'package:framework/src/storyboard/models/dialogue.dart';
import 'package:framework/src/storyboard/models/dialogue_beat.dart';
import 'package:framework/src/storyboard/models/sfx.dart';
import 'package:framework/src/storyboard/models/caption.dart';
import 'package:framework/src/storyboard/models/story_scene.dart';
import 'package:framework/src/storyboard/models/video_track.dart';
import 'package:flutter_test/flutter_test.dart';

/// `scene<N>.json` 직렬화 검증. 씬 = 대사들의 나열, 각 대사 = 대사(0/1) + 샷들.
/// 자기설명적이고, 미디어는 파일명(상대)만 담기며, 왕복 후 값이 보존되고, 구버전도 마이그레이션되는지.
void main() {
  const dir = '/proj/abc';

  StoryScene sampleScene() => StoryScene(
        id: 'scene_1',
        title: '오프닝',
        commonPrompt: '세로 9:16, 애니풍',
        loraUrl: 'https://civitai.com/x',
        loraStrength: 0.7,
        bgmPrompt: 'cinematic, ambient, calm, piano',
        bgmSeconds: 45,
        bgmPath: '$dir/scene_1_bgm.mp3',
        defaultVoiceId: 'voice_narrator',
        defaultVoiceName: '내레이터',
        tracks: [
          VideoTrack(id: 'track_1', name: '트랙 1', beats: [
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
                refCharacterIds: ['char_miles'],
                startPrompt: '마일스 입을 뗀다, 클로즈업',
                endPrompt: '눈을 감는다',
                videoPrompt: '카메라 천천히 전진',
                videoSeconds: 3,
                startImagePath: '$dir/clip_1_start.png',
                endImagePath: '$dir/clip_1_end.png',
                videoPath: '$dir/clip_1_vlow.mp4',
              ),
              Shot(
                id: 'clip_2',
                refCharacterIds: ['char_sheriff'],
                startPrompt: '보안관 무표정 리액션',
                videoSeconds: 3,
              ),
            ],
          ),
          // 무음 대사(대사 없음) — establishing 샷 1개.
          DialogueBeat(
            id: 'shot_2',
            shots: [Shot(id: 'clip_3', startPrompt: '모텔 외경')],
          ),
          ]),
        ],
      );

  test('JSON은 대사 나열 + 각 대사=대사(0/1)+샷들 + 미디어는 파일명(상대)만', () {
    final j = sampleScene().toJson();

    expect(j.keys,
        containsAll(['id', 'title', 'commonPrompt', 'tracks', 'bgm', 'lora']));
    expect(j['bgm'], {
      'prompt': 'cinematic, ambient, calm, piano',
      'seconds': 45,
      'file': 'scene_1_bgm.mp3',
    });

    // 씬 > 트랙 > 비트 — 트랙 1(기준)의 비트들을 본다.
    final tracks = j['tracks'] as List;
    expect(tracks.length, 1);
    expect((tracks.first as Map)['backend'], 'serviceApi');
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
    expect(c1['refCharacters'], ['char_miles']);
    // inherit = 시작장면을 앞 샷 끝장면에 연동할지.
    expect(c1['startScene'], {
      'prompt': '마일스 입을 뗀다, 클로즈업',
      'promptKo': '',
      'image': 'clip_1_start.png',
      'inherit': false,
    });
    // mode = 영상 생성 방식(fe2v/i2v/still). 기본은 fe2v. stillEffect = 스틸컷 켄번스(기본 none).
    // negativePrompt = 빼고 싶은 것만 적는 칸(비면 서버 워크플로 기본 네거티브).
    expect(c1['video'], {
      'prompt': '카메라 천천히 전진',
      'promptKo': '',
      'negativePrompt': '',
      'seconds': 3.0, // 길이는 double 하나로 통일(스틸컷 0.1초·AI 정수 초 공용)
      'actualSeconds': null, // 아직 안 재본 것(뽑고 나면 실제 길이가 들어간다)
      'file': 'clip_1_vlow.mp4',
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
    expect(after.loraUrl, 'https://civitai.com/x');
    expect(after.bgmPath, '$dir/scene_1_bgm.mp3');
    expect(after.defaultVoiceId, 'voice_narrator');
    expect(after.defaultVoiceName, '내레이터');
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
    expect(c1.refCharacterIds, ['char_miles']);
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
    expect(sc.loraStrength, 0.8);
    expect(sc.bgmSeconds, 30);
    expect(sc.bgmPath, isNull);

    final beat = DialogueBeat.fromJson({'id': 'b_min'}, dir);
    expect(beat.shots, isEmpty);
    expect(beat.dialogue, isNull);
    expect(beat.sfx, isNull);
  });

  test('효과음(SFX)은 기준 비트에 저장되고 왕복 보존, 파생 비트엔 안 적힌다', () {
    final base = DialogueBeat(
      id: 'b1',
      sfx: Sfx(
        prompt: 'deep cinematic impact boom',
        durationSeconds: 1.6,
        promptInfluence: 0.6,
        path: '$dir/b1_sfx.mp3',
        soundSeconds: 1.55,
      ),
    );
    final j = base.toJson();
    final sfxJson = j['sfx'] as Map;
    expect(sfxJson['prompt'], 'deep cinematic impact boom');
    expect(sfxJson['durationSeconds'], 1.6);
    expect(sfxJson['promptInfluence'], 0.6);
    expect((sfxJson['sound'] as Map)['file'], 'b1_sfx.mp3'); // 파일명(상대)만

    final back = DialogueBeat.fromJson(j, dir);
    expect(back.sfx!.prompt, 'deep cinematic impact boom');
    expect(back.sfx!.durationSeconds, 1.6);
    expect(back.sfx!.promptInfluence, 0.6);
    expect(back.sfx!.path, '$dir/b1_sfx.mp3'); // 절대경로로 복원
    expect(back.sfx!.hasSound, isTrue);

    // 파생 비트(base 있음)는 효과음을 적지 않는다(트랙 공유 — 기준 비트에만).
    final derived = DialogueBeat(id: 'b1_t2', baseId: 'b1', sfx: Sfx(prompt: 'x'));
    expect(derived.toJson().containsKey('sfx'), isFalse);
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
      'startScene': {'prompt': 'a', 'image': null},
      'endScene': {'prompt': '문 닫힘', 'image': 'y_end.png'},
    }, dir);
    expect(withEnd.endPrompt, '문 닫힘');
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
