import 'dart:io';
import 'dart:math' as math;

import '../models/shot.dart' show StillEffect;

/// 생성된 영상 파일을 다루는 로컬 도구 — ffmpeg/ffprobe 래퍼.
/// 지금 하는 일은 **트림(앞뒤 자르기)** 하나뿐이다: FE2V 결과에 가끔 섞이는 이상한 프레임을
/// 양 끝에서 잘라낸다. (중간 잘라내기·이어붙이기는 안 한다.)
class VideoEdit {
  /// GUI로 띄운 앱의 PATH에는 /opt/homebrew/bin이 없다(로그인 셸이 아니라서).
  /// 그래서 PATH에 기대지 않고 알려진 자리를 직접 뒤진다.
  static const _dirs = ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin'];

  static final Map<String, String?> _resolved = {};

  /// [tool]('ffmpeg'/'ffprobe')의 실제 경로. 없으면 null.
  static String? toolPath(String tool) => _resolved.putIfAbsent(tool, () {
        for (final d in _dirs) {
          final p = '$d/$tool';
          if (File(p).existsSync()) return p;
        }
        return null;
      });

  static bool get available =>
      toolPath('ffmpeg') != null && toolPath('ffprobe') != null;

  /// 설치 안내 문구(UI에서 그대로 보여준다).
  static const missingHint =
      'ffmpeg이 없어 트림할 수 없습니다.\n터미널에서 `brew install ffmpeg` 후 다시 시도하세요.';

  /// 영상 정보 조회. 실패하면 null.
  static Future<VideoInfo?> probe(String path) async {
    final ffprobe = toolPath('ffprobe');
    if (ffprobe == null) return null;
    final r = await Process.run(ffprobe, [
      '-v', 'error',
      '-show_entries', 'stream=codec_type,r_frame_rate,nb_read_packets,width,height',
      '-select_streams', 'v:0',
      '-count_packets',
      '-show_entries', 'format=duration',
      '-of', 'default=nw=1',
      path,
    ]);
    if (r.exitCode != 0) return null;

    final fields = <String, String>{};
    for (final line in (r.stdout as String).split('\n')) {
      final i = line.indexOf('=');
      if (i > 0) fields[line.substring(0, i)] = line.substring(i + 1).trim();
    }

    // r_frame_rate는 '24/1' 꼴의 유리수다.
    var fps = 24.0;
    final rate = fields['r_frame_rate'];
    if (rate != null && rate.contains('/')) {
      final parts = rate.split('/');
      final num = double.tryParse(parts[0]) ?? 24;
      final den = double.tryParse(parts[1]) ?? 1;
      if (den > 0 && num > 0) fps = num / den;
    }
    final frames = int.tryParse(fields['nb_read_packets'] ?? '') ?? 0;
    if (frames <= 0) return null;

    return VideoInfo(
      frameCount: frames,
      fps: fps,
      width: int.tryParse(fields['width'] ?? '') ?? 0,
      height: int.tryParse(fields['height'] ?? '') ?? 0,
      duration: double.tryParse(fields['duration'] ?? '') ?? frames / fps,
      hasAudio: await _hasAudio(ffprobe, path),
    );
  }

  static Future<bool> _hasAudio(String ffprobe, String path) async {
    final r = await Process.run(ffprobe, [
      '-v', 'error',
      '-select_streams', 'a:0',
      '-show_entries', 'stream=index',
      '-of', 'csv=p=0',
      path,
    ]);
    return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
  }

  /// [path]를 [first]~[last] 프레임(양끝 포함)만 남기고 잘라 **덮어쓴다**.
  /// 프레임 번호로 자르므로(select 필터) 경계가 정확하다 — 시간 지정처럼 반올림으로
  /// 한 프레임 밀리지 않는다. 오디오가 있으면 같은 구간으로 함께 자른다.
  ///
  /// 잘라낸 뒤의 실제 길이(초)를 돌려준다. 실패하면 예외를 던지고 원본은 그대로 둔다.
  static Future<double> trim(
    String path, {
    required int first,
    required int last,
    required double fps,
  }) async {
    final ffmpeg = toolPath('ffmpeg');
    if (ffmpeg == null) throw Exception(missingHint);
    if (last < first) throw Exception('트림 구간이 잘못되었습니다.');

    final hasAudio = (await probe(path))?.hasAudio ?? false;
    // 원본을 직접 덮으면 실패했을 때 되돌릴 수 없다 — 임시 파일에 쓰고 성공해야 교체한다.
    final out = '$path.trim.mp4';
    final args = <String>[
      '-y',
      '-i', path,
      '-vf', "select='between(n\\,$first\\,$last)',setpts=PTS-STARTPTS",
      '-r', '$fps',
      '-c:v', 'libx264',
      '-crf', '18',
      '-preset', 'veryfast',
      '-pix_fmt', 'yuv420p',
      if (hasAudio) ...[
        '-af',
        'atrim=start=${first / fps}:end=${(last + 1) / fps},asetpts=PTS-STARTPTS',
        '-c:a', 'aac',
        '-b:a', '192k',
      ] else
        '-an',
      out,
    ];
    final r = await Process.run(ffmpeg, args);
    final tmp = File(out);
    if (r.exitCode != 0) {
      if (await tmp.exists()) await tmp.delete();
      throw Exception('트림 실패: ${(r.stderr as String).trim().split('\n').last}');
    }
    await tmp.rename(path);
    return (last - first + 1) / fps;
  }

  /// 사진 한 장([image])을 [seconds]초짜리 영상([outPath])으로 만든다 — **스틸컷**(AI 없이).
  /// [effect]로 켄번스(줌 인/아웃)를 준다. 출력은 [width]×[height] — FE2V 결과와 섞어
  /// 이어붙일 수 있게 규격을 맞춘다. 24fps·H.264·무음.
  static Future<void> stillClip({
    required String image,
    required String outPath,
    required double seconds,
    required StillEffect effect,
    required int width,
    required int height,
    double fps = 24,
  }) async {
    final ffmpeg = toolPath('ffmpeg');
    if (ffmpeg == null) throw Exception(missingHint);
    final sec = seconds < 0.1 ? 0.1 : seconds; // 최소 0.1초
    final frames = (sec * fps).round();
    final w = width, h = height;

    // 켄번스는 12%까지 아주 천천히 — 앨범 미리보기처럼. on = 출력 프레임 인덱스(시간축).
    final vf = switch (effect) {
      StillEffect.none =>
        'scale=$w:$h:force_original_aspect_ratio=increase,'
            'crop=$w:$h,setsar=1,format=yuv420p',
      StillEffect.zoomIn => _kenBurns(w, h, frames, fps, '1.0+0.12*on/$frames'),
      StillEffect.zoomOut =>
        _kenBurns(w, h, frames, fps, '1.12-0.12*on/$frames'),
    };

    final r = await Process.run(ffmpeg, [
      '-y',
      '-loop', '1',
      '-i', image,
      '-t', '$sec',
      '-r', '$fps',
      '-vf', vf,
      '-c:v', 'libx264', '-crf', '18', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
      '-an',
      outPath,
    ]);
    if (r.exitCode != 0) {
      final f = File(outPath);
      if (await f.exists()) await f.delete();
      throw Exception(
          '스틸컷 실패: ${(r.stderr as String).trim().split('\n').last}');
    }
  }

  /// 켄번스 필터 체인 — 큰 캔버스로 먼저 덮어(줌 시 화질·잔떨림 완화) zoompan으로 w×h 출력.
  static String _kenBurns(
          int w, int h, int frames, double fps, String zExpr) =>
      'scale=${w * 2}:${h * 2}:force_original_aspect_ratio=increase,'
      'crop=${w * 2}:${h * 2},'
      "zoompan=z='$zExpr':d=$frames:"
      "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
      's=${w}x$h:fps=$fps,setsar=1,format=yuv420p';

  /// [inputs]를 순서대로 이어붙여 [outPath]로 쓴다(씬 무비 내보내기).
  ///
  /// 1차: concat demuxer + 스트림 복사(재인코딩 없음 — 같은 파이프라인 산출물이면 이걸로 끝).
  /// 실패하면 2차: concat 필터로 재인코딩 — 첫 클립의 해상도·24fps로 통일하고, 오디오가
  /// 없는 클립은 무음을 깔아 트랙 수를 맞춘다(트랙 수가 다르면 concat 필터가 거부한다).
  static Future<void> concat(List<String> inputs, String outPath) async {
    final ffmpeg = toolPath('ffmpeg');
    if (ffmpeg == null) throw Exception(missingHint);
    if (inputs.isEmpty) throw Exception('이어붙일 영상이 없습니다.');

    // 1차 — 무재인코딩. 목록 파일의 경로는 concat demuxer 규칙대로 작은따옴표 이스케이프.
    final list = File('$outPath.list.txt');
    await list.writeAsString(
        inputs.map((p) => "file '${p.replaceAll("'", r"'\''")}'").join('\n'));
    var r = await Process.run(ffmpeg,
        ['-y', '-f', 'concat', '-safe', '0', '-i', list.path, '-c', 'copy', outPath]);
    await list.delete();
    if (r.exitCode == 0) return;

    // 2차 — 재인코딩 폴백. 기준 해상도 = 첫 클립.
    final infos = <VideoInfo?>[for (final p in inputs) await probe(p)];
    final w = (infos.first?.width ?? 0) > 0 ? infos.first!.width : 704;
    final h = (infos.first?.height ?? 0) > 0 ? infos.first!.height : 1280;

    final args = <String>['-y'];
    for (final p in inputs) {
      args.addAll(['-i', p]);
    }
    final fc = StringBuffer();
    for (var i = 0; i < inputs.length; i++) {
      fc.write('[$i:v]scale=$w:$h:force_original_aspect_ratio=decrease,'
          'pad=$w:$h:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=24[v$i];');
      if (infos[i]?.hasAudio ?? false) {
        // 채널 수를 stereo로 통일 — 안 그러면 mono/stereo가 섞여 concat 필터가 거부한다.
        fc.write('[$i:a]aresample=48000,'
            'aformat=sample_fmts=fltp:channel_layouts=stereo[a$i];');
      } else {
        // 무음 클립: A/V 길이가 어긋나지 않게 그 클립의 영상 길이만큼 무음을 깐다.
        final dur = infos[i]?.duration ?? 3.0;
        fc.write('anullsrc=r=48000:cl=stereo,atrim=0:$dur[a$i];');
      }
    }
    for (var i = 0; i < inputs.length; i++) {
      fc.write('[v$i][a$i]');
    }
    fc.write('concat=n=${inputs.length}:v=1:a=1[v][a]');
    args.addAll([
      '-filter_complex', fc.toString(),
      '-map', '[v]', '-map', '[a]',
      '-c:v', 'libx264', '-crf', '18', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-b:a', '192k',
      outPath,
    ]);
    r = await Process.run(ffmpeg, args);
    if (r.exitCode != 0) {
      final f = File(outPath);
      if (await f.exists()) await f.delete();
      throw Exception('합치기 실패: ${(r.stderr as String).trim().split('\n').last}');
    }
  }

  /// 미디어(영상·오디오) 길이(초). 실패하면 0. (probe는 비디오 스트림 전용이라 오디오엔 못 쓴다.)
  static Future<double> _mediaDuration(String path) async {
    final ffprobe = toolPath('ffprobe');
    if (ffprobe == null) return 0;
    final r = await Process.run(ffprobe, [
      '-v', 'error',
      '-show_entries', 'format=duration',
      '-of', 'default=nw=1:nk=1',
      path,
    ]);
    if (r.exitCode != 0) return 0;
    return double.tryParse((r.stdout as String).trim()) ?? 0;
  }

  /// 씬 무비 **내보내기** — 미리보기와 같은 규칙으로 영상·대사·효과음·배경음을 한 파일로 굽는다.
  ///  - 비트마다: 영상 클립들을 이어붙이고, 길이는 **영상·대사 중 긴 쪽**. 대사가 더 길면 마지막
  ///    프레임을 그만큼 정지시켜 늘린다(미리보기의 "긴 쪽 기준"과 동일).
  ///  - 대사 음성 + 효과음을 비트 시작부터 얹어 섞는다(효과음이 비트보다 길면 잘린다).
  ///  - 마지막으로 배경음(BGM)을 전체에 낮은 볼륨으로 루프해 깔아 준다.
  /// 규격은 [width]×[height]·[fps]로 통일해 비트끼리 이어붙는다.
  static Future<void> exportScene({
    required List<ExportBeat> beats,
    String? bgm,
    required int width,
    required int height,
    required String outPath,
    double fps = 24,
    double bgmVolume = 0.4,
  }) async {
    final ffmpeg = toolPath('ffmpeg');
    if (ffmpeg == null) throw Exception(missingHint);
    if (beats.isEmpty) throw Exception('내보낼 비트가 없습니다.');

    final tmp = Directory('${outPath}_export_tmp');
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create(recursive: true);
    // 자막(ASS) 파일은 **경로에 특수문자가 없는** 시스템 임시폴더에 둔다 — subtitles 필터는
    // 파일 경로 이스케이프가 까다로워서, 사용자가 고른 저장 경로(한글·공백 가능) 밑을 피한다.
    final capDir = Directory.systemTemp.createTempSync('mtg_cap');
    try {
      // 1) 비트마다 영상+오디오를 합쳐 한 세그먼트로.
      final segs = <String>[];
      for (var i = 0; i < beats.length; i++) {
        final seg = '${tmp.path}/beat_$i.mp4';
        // 자막이 있으면 이 비트의 ASS를 굽고(시간은 비트 시작=0 기준) 경로를 넘긴다.
        final assPath = _writeBeatAss(
            beats[i].caption, width, height, '${capDir.path}/beat_$i.ass');
        await _renderBeat(ffmpeg, beats[i], width, height, fps, seg, assPath);
        segs.add(seg);
      }
      // 2) 세그먼트들을 이어붙인다 — **영상은 무손실 복사 + 오디오는 stereo aac로 재인코딩**.
      //    세그먼트마다 채널 수가 다르거나(대사 mono vs 효과음 mix stereo) aac 프라이밍이 있으면
      //    순수 스트림복사 concat은 그 경계부터 오디오가 어긋난다("효과음 뒤 대사 사라짐"). 오디오만
      //    다시 구우면 채널·타임스탬프가 통일돼 안전하고, 영상은 그대로라 화질 손실이 없다.
      final scene = bgm == null ? outPath : '${tmp.path}/scene.mp4';
      await _concatExport(ffmpeg, segs, scene);
      // 3) 배경음을 전체에 깐다(있으면).
      if (bgm != null) await _mixBgm(ffmpeg, scene, bgm, bgmVolume, outPath);
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
      if (await capDir.exists()) await capDir.delete(recursive: true);
    }
  }

  /// 내보내기용 이어붙이기 — 영상은 무손실 복사, 오디오는 stereo·48k aac로 재인코딩해 통일한다.
  /// 세그먼트 채널 수가 섞여도(대사 mono vs 효과음 mix stereo) 오디오가 어긋나지 않는다.
  /// 실패하면(드묾) 필터 재인코딩 concat으로 폴백.
  static Future<void> _concatExport(
      String ffmpeg, List<String> segs, String outPath) async {
    if (segs.isEmpty) throw Exception('이어붙일 영상이 없습니다.');
    final list = File('$outPath.list.txt');
    await list.writeAsString(
        segs.map((p) => "file '${p.replaceAll("'", r"'\''")}'").join('\n'));
    final r = await Process.run(ffmpeg, [
      '-y', '-f', 'concat', '-safe', '0', '-i', list.path,
      '-c:v', 'copy',
      '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2',
      outPath,
    ]);
    await list.delete();
    if (r.exitCode == 0) return;
    // 폴백: 영상까지 재인코딩하는 필터 concat.
    await concat(segs, outPath);
  }

  /// 비트 자막을 ASS 파일로 쓴다(구간별 Dialogue). 자막이 없거나 전부 공백이면 null.
  /// 시간은 **비트 시작=0** 기준(세그먼트가 그 시점부터 시작하므로) — concat 후 자연히 맞는다.
  static String? _writeBeatAss(
      ExportCaption? cap, int w, int h, String assPath) {
    if (cap == null || !cap.hasText) return null;
    final align = switch (cap.position) { 'top' => 8, 'middle' => 5, _ => 2 };
    final fontSize = (h * 0.055).round().clamp(18, 96);
    final marginV = (h * 0.045).round();
    // 미리보기처럼 글씨 뒤에 반투명 검은 박스를 깐다(BorderStyle=3). 박스 색은 OutlineColour,
    // Outline 값이 글씨 둘레 여백. ASS 알파는 00=불투명 → 미리보기 60% 불투명(0x99) ≈ &H66.
    final boxPad = (fontSize * 0.22).round().clamp(2, 14);
    final sb = StringBuffer()
      ..writeln('[Script Info]')
      ..writeln('ScriptType: v4.00+')
      ..writeln('PlayResX: $w')
      ..writeln('PlayResY: $h')
      ..writeln('WrapStyle: 0')
      ..writeln('ScaledBorderAndShadow: yes')
      ..writeln('')
      ..writeln('[V4+ Styles]')
      ..writeln('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
          'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, '
          'ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, '
          'MarginL, MarginR, MarginV, Encoding')
      // 흰 글씨 + 반투명 검은 박스(BorderStyle=3, 박스색=OutlineColour &H66000000).
      // 한글은 libass가 폴백 폰트로 렌더. (BackColour는 그림자용 — 안 씀.)
      ..writeln('Style: Default,Arial,$fontSize,&H00FFFFFF,&H000000FF,&H66000000,'
          '&H00000000,0,0,0,0,100,100,0,0,3,$boxPad,0,$align,60,60,$marginV,1')
      ..writeln('')
      ..writeln('[Events]')
      ..writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, '
          'MarginV, Effect, Text');
    var t = 0.0;
    for (final cue in cap.cues) {
      final start = t;
      final end = t + cue.seconds;
      t = end;
      final text = cue.text.trim();
      if (text.isEmpty) continue; // 공백 구간(자막 없음)
      final safe = text
          .replaceAll('\\', '\\\\')
          .replaceAll('\n', '\\N')
          .replaceAll('{', '(')
          .replaceAll('}', ')');
      sb.writeln('Dialogue: 0,${_assTime(start)},${_assTime(end)},'
          'Default,,0,0,0,,$safe');
    }
    File(assPath).writeAsStringSync(sb.toString());
    return assPath;
  }

  /// 초 → ASS 시간 문자열(H:MM:SS.cc, 센티초).
  static String _assTime(double sec) {
    final cs = (math.max(0.0, sec) * 100).round();
    final h = cs ~/ 360000;
    final m = (cs % 360000) ~/ 6000;
    final s = (cs % 6000) ~/ 100;
    final c = cs % 100;
    String two(int v) => v.toString().padLeft(2, '0');
    return '$h:${two(m)}:${two(s)}.${two(c)}';
  }

  /// 비트 하나를 세그먼트로 굽는다 — 클립 이어붙이기 + (대사가 길면)프레임 정지 연장 + 오디오 믹스.
  static Future<void> _renderBeat(
    String ffmpeg,
    ExportBeat b,
    int w,
    int h,
    double fps,
    String outPath,
    String? assPath, // 자막 ASS 경로(없으면 null)
  ) async {
    var dv = 0.0; // 영상 길이 합
    for (final c in b.clips) {
      dv += await _mediaDuration(c);
    }
    final voiceDur = b.voice == null ? 0.0 : await _mediaDuration(b.voice!);
    final beatDur = math.max(dv, voiceDur); // 긴 쪽 기준
    final durStr = beatDur.toStringAsFixed(3);

    final args = <String>['-y'];
    for (final c in b.clips) {
      args.addAll(['-i', c]);
    }
    final voiceIdx = b.voice == null ? -1 : b.clips.length;
    if (b.voice != null) args.addAll(['-i', b.voice!]);
    final sfxIdx = b.sfx == null ? -1 : (voiceIdx >= 0 ? voiceIdx + 1 : b.clips.length);
    if (b.sfx != null) args.addAll(['-i', b.sfx!]);

    final fc = StringBuffer();
    // 영상: 각 클립을 규격에 맞춰 스케일·패딩 후 이어붙인다.
    for (var i = 0; i < b.clips.length; i++) {
      fc.write('[$i:v]scale=$w:$h:force_original_aspect_ratio=decrease,'
          'pad=$w:$h:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=$fps[v$i];');
    }
    for (var i = 0; i < b.clips.length; i++) {
      fc.write('[v$i]');
    }
    fc.write('concat=n=${b.clips.length}:v=1:a=0[vc];');
    // 대사가 더 길면 마지막 프레임을 그만큼 정지시켜 늘린다.
    final ext = beatDur - dv;
    if (ext > 0.02) {
      fc.write('[vc]tpad=stop_mode=clone:stop_duration=${ext.toStringAsFixed(3)}[vp];');
    } else {
      fc.write('[vc]null[vp];');
    }
    // 자막을 영상 위에 구워 넣는다(있으면). 경로는 특수문자 없는 임시폴더라 그대로 태운다.
    if (assPath != null) {
      fc.write('[vp]subtitles=$assPath[v];');
    } else {
      fc.write('[vp]null[v];');
    }
    // 오디오: 대사·효과음을 비트 시작부터 얹고 비트 길이에 맞춘다(짧으면 무음 패딩, 길면 컷).
    // ⚠️ 모든 비트의 오디오를 **stereo·48kHz로 통일**한다 — 안 그러면 mono 음성 비트와
    //    stereo 효과음 섞은 비트의 채널 수가 달라, 세그먼트 이어붙일(concat) 때 그 지점부터
    //    오디오가 떨어져 나간다(효과음 비트 이후 대사가 사라지던 버그).
    const aFmt = 'aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo';
    final aparts = <String>[];
    if (voiceIdx >= 0) {
      fc.write('[$voiceIdx:a]$aFmt,apad,atrim=0:$durStr,'
          'asetpts=PTS-STARTPTS[av];');
      aparts.add('[av]');
    }
    if (sfxIdx >= 0) {
      fc.write('[$sfxIdx:a]$aFmt,apad,atrim=0:$durStr,'
          'asetpts=PTS-STARTPTS[as];');
      aparts.add('[as]');
    }
    if (aparts.isEmpty) {
      fc.write('anullsrc=r=48000:cl=stereo,atrim=0:$durStr[a];');
    } else if (aparts.length == 1) {
      fc.write('${aparts.first}$aFmt[a];');
    } else {
      fc.write('${aparts.join()}amix=inputs=${aparts.length}:normalize=0,'
          '$aFmt[a];');
    }

    args.addAll([
      '-filter_complex', fc.toString(),
      '-map', '[v]', '-map', '[a]',
      '-t', durStr,
      '-c:v', 'libx264', '-crf', '18', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-b:a', '192k', '-ar', '48000',
      outPath,
    ]);
    final r = await Process.run(ffmpeg, args);
    if (r.exitCode != 0) {
      throw Exception('비트 합성 실패: ${(r.stderr as String).trim().split('\n').last}');
    }
  }

  /// 완성된 씬 영상 위에 배경음을 낮은 볼륨으로 루프해 깐다. 영상은 재인코딩하지 않는다.
  static Future<void> _mixBgm(
    String ffmpeg,
    String scene,
    String bgm,
    double vol,
    String outPath,
  ) async {
    final r = await Process.run(ffmpeg, [
      '-y',
      '-i', scene,
      '-stream_loop', '-1', '-i', bgm, // 씬 길이까지 반복
      '-filter_complex',
      '[1:a]aresample=48000,volume=${vol.toStringAsFixed(2)}[bg];'
          '[0:a][bg]amix=inputs=2:duration=first:normalize=0[a]',
      '-map', '0:v', '-map', '[a]',
      '-c:v', 'copy',
      '-c:a', 'aac', '-b:a', '192k', '-ar', '48000',
      '-shortest',
      outPath,
    ]);
    if (r.exitCode != 0) {
      final f = File(outPath);
      if (await f.exists()) await f.delete();
      throw Exception('배경음 합성 실패: ${(r.stderr as String).trim().split('\n').last}');
    }
  }
}

/// [VideoEdit.exportScene]에 넘기는 비트 하나 — 영상 클립들 + (있으면)대사 음성·효과음·자막.
class ExportBeat {
  const ExportBeat({required this.clips, this.voice, this.sfx, this.caption});

  /// 이 비트의 영상들(순서대로) — 최소 1개. 없으면 이 비트는 내보내기에서 빠진다.
  final List<String> clips;
  final String? voice; // 대사 음성(mp3)
  final String? sfx; // 효과음(mp3)
  final ExportCaption? caption; // 자막(시간순 구간 + 위치) — 영상 위에 구워 넣는다
}

/// 내보내기용 자막 한 벌 — 비트 시작부터 순서대로 흐르는 구간들 + 세로 위치.
/// (모델의 Caption을 video_edit이 모델을 몰라도 되게 원시값으로 옮긴 것.)
class ExportCaption {
  const ExportCaption({required this.cues, required this.position});

  /// (초, 텍스트) 순서대로. 텍스트가 빈 구간은 공백(그 시간만큼 자막 없음).
  final List<({double seconds, String text})> cues;

  /// 세로 위치 — 'top' | 'middle' | 'bottom'.
  final String position;

  bool get hasText => cues.any((c) => c.text.trim().isNotEmpty);
}

/// [VideoEdit.probe] 결과.
class VideoInfo {
  const VideoInfo({
    required this.frameCount,
    required this.fps,
    required this.width,
    required this.height,
    required this.duration,
    required this.hasAudio,
  });

  final int frameCount;
  final double fps;
  final int width;
  final int height;
  final double duration;
  final bool hasAudio;
}
