import 'dart:io';

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
