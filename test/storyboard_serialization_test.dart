import 'package:framework/src/storyboard/models/character.dart';
import 'package:framework/src/storyboard/models/clip.dart';
import 'package:framework/src/storyboard/models/dialogue.dart';
import 'package:framework/src/storyboard/models/shot.dart';
import 'package:framework/src/storyboard/models/story_scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// `scene<N>.json` 직렬화 검증. 씬 = 샷들의 나열, 각 샷 = 대사(0/1) + 클립들.
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
        shots: [
          // 대사 있는 샷 — 클립 2개(첫 클립 립싱크 + 컷어웨이).
          Shot(
            id: 'shot_1',
            title: '첫 컷',
            note: '역광 주의 · 클라 요청으로 톤 어둡게',
            status: ShotStatus.review,
            dialogue: Dialogue(
              speakerId: 'char_miles',
              text: '형사님, 그 밤에 무슨 일이 있었죠?',
              voicePath: '$dir/shot_1_voice.mp3',
              voiceSeconds: 5.4,
            ),
            clips: [
              VideoClip(
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
              VideoClip(
                id: 'clip_2',
                refCharacterIds: ['char_sheriff'],
                startPrompt: '보안관 무표정 리액션',
                videoSeconds: 3,
              ),
            ],
          ),
          // 무음 샷(대사 없음) — establishing 클립 1개.
          Shot(
            id: 'shot_2',
            clips: [VideoClip(id: 'clip_3', startPrompt: '모텔 외경')],
          ),
        ],
      );

  test('JSON은 샷 나열 + 각 샷=대사(0/1)+클립들 + 미디어는 파일명(상대)만', () {
    final j = sampleScene().toJson();

    expect(j.keys,
        containsAll(['id', 'title', 'commonPrompt', 'shots', 'bgm', 'lora']));
    expect(j['bgm'], {
      'prompt': 'cinematic, ambient, calm, piano',
      'seconds': 45,
      'file': 'scene_1_bgm.mp3',
    });

    final shots = j['shots'] as List;
    expect(shots.length, 2);

    // 샷1: 상태·메모·대사 + 클립 2개.
    final s1 = shots.first as Map;
    expect(s1['status'], 'review');
    expect(s1['note'], '역광 주의 · 클라 요청으로 톤 어둡게');
    expect(s1['dialogue'], {
      'speaker': 'char_miles',
      'text': '형사님, 그 밤에 무슨 일이 있었죠?',
      'voice': {'file': 'shot_1_voice.mp3', 'seconds': 5.4},
    });
    final clips1 = s1['clips'] as List;
    expect(clips1.length, 2);
    final c1 = clips1.first as Map;
    // 클립엔 status/note 없음(샷 소유).
    expect(c1.containsKey('status'), isFalse);
    expect(c1['refCharacters'], ['char_miles']);
    expect(c1['startScene'], {'prompt': '마일스 입을 뗀다, 클로즈업', 'image': 'clip_1_start.png'});
    expect(c1['video'], {
      'prompt': '카메라 천천히 전진',
      'seconds': 3,
      'file': 'clip_1_vlow.mp4',
    });

    // 샷2: 무음(dialogue=null).
    final s2 = shots[1] as Map;
    expect(s2['dialogue'], isNull);
    expect((s2['clips'] as List).length, 1);

    // 절대경로 없음.
    expect(j.toString(), isNot(contains('/proj/abc')));
  });

  test('왕복 후 값 보존 + 미디어는 dir 기준 절대경로로 복원', () {
    final after = StoryScene.fromJson(sampleScene().toJson(), dir);

    expect(after.id, 'scene_1');
    expect(after.commonPrompt, '세로 9:16, 애니풍');
    expect(after.loraUrl, 'https://civitai.com/x');
    expect(after.bgmPath, '$dir/scene_1_bgm.mp3');
    expect(after.shots.length, 2);

    final s1 = after.shots.first;
    expect(s1.status, ShotStatus.review);
    expect(s1.note, '역광 주의 · 클라 요청으로 톤 어둡게');
    expect(s1.hasDialogue, isTrue);
    expect(s1.dialogue!.speakerId, 'char_miles');
    expect(s1.dialogue!.text, '형사님, 그 밤에 무슨 일이 있었죠?');
    expect(s1.dialogue!.voicePath, '$dir/shot_1_voice.mp3');
    expect(s1.dialogue!.voiceSeconds, 5.4);
    expect(s1.dialogue!.hasVoice, isTrue);
    // 샷 길이 = 대사 음성 길이(5.4). 클립 길이 합은 3+3=6이지만 대사가 있으면 대사가 기준.
    expect(s1.seconds, 5.4);
    expect(s1.clipSeconds, 6);

    expect(s1.clips.length, 2);
    final c1 = s1.clips.first;
    expect(c1.refCharacterIds, ['char_miles']);
    expect(c1.endImagePath, '$dir/clip_1_end.png');
    expect(c1.startImagePath, '$dir/clip_1_start.png');
    expect(c1.videoPath, '$dir/clip_1_vlow.mp4');

    // 무음 샷: 대사 없음 → 길이는 클립 길이 합.
    final s2 = after.shots[1];
    expect(s2.hasDialogue, isFalse);
    expect(s2.dialogue, isNull);
    expect(s2.seconds, s2.clipSeconds.toDouble());

    // 씬 전체 길이 = 각 샷 길이 합(5.4 + 무음샷 클립합).
    expect(after.totalSeconds, 5.4 + s2.clipSeconds);
    expect(after.clipCount, 3);
  });

  test('폴더가 이동해도 미디어 경로가 새 dir 기준으로 복원된다', () {
    final moved = StoryScene.fromJson(sampleScene().toJson(), '/new/home');
    expect(moved.bgmPath, '/new/home/scene_1_bgm.mp3');
    expect(moved.shots.first.dialogue!.voicePath, '/new/home/shot_1_voice.mp3');
    expect(moved.shots.first.clips.first.startImagePath,
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

  test('구버전(평면 클립 리스트) → 클립 1개짜리 무음 샷들로 마이그레이션', () {
    // 옛 스키마: 씬이 `shots`(또는 `clips`) = flat 영상 단위 리스트. 대사/샷 개념 없음.
    final legacy = {
      'id': 'scene_old',
      'title': '옛씬',
      'loraUrl': 'u',
      'bgmPrompt': 'lofi',
      'shots': [
        {
          'id': 'oldclip_1',
          'status': 'done', // 옛 클립의 상태 → 샷으로 끌어올림
          'note': '옛 메모',
          'prompt': '옛 프롬프트', // 구버전 단일 prompt
          'startImagePath': '/old/place/oldclip_1_start.png',
        }
      ],
    };
    final sc = StoryScene.fromJson(legacy, dir);
    expect(sc.loraUrl, 'u');
    expect(sc.bgmPrompt, 'lofi');
    expect(sc.shots.length, 1);

    final shot = sc.shots.single;
    expect(shot.dialogue, isNull); // 무음 샷
    expect(shot.status, ShotStatus.done); // 옛 클립 status → 샷
    expect(shot.note, '옛 메모');
    expect(shot.clips.length, 1);

    final clip = shot.clips.single;
    expect(clip.startPrompt, '옛 프롬프트'); // prompt → startPrompt
    expect(clip.startImagePath, '$dir/oldclip_1_start.png');
    expect(clip.endImagePath, isNull); // 끝 데이터 없음
  });

  test('새 샷 기본값 + 끝장면(클립) 왕복', () {
    expect(Shot(id: 'x').hasDialogue, isFalse);
    expect(Shot(id: 'x').status, ShotStatus.ready);

    // 끝 이미지/프롬프트가 보존된다(FE2V 필수 프레임).
    final legacyWithEnd = VideoClip.fromJson({
      'id': 'y',
      'startPrompt': 'a',
      'endPrompt': '문 닫힘',
      'endImagePath': '/old/y_end.png',
    }, dir);
    expect(legacyWithEnd.endPrompt, '문 닫힘');
    expect(legacyWithEnd.endImagePath, '$dir/y_end.png');
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
