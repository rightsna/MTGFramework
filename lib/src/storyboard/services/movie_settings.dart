import 'dart:convert';
import 'dart:io';

import 'package:framework/framework.dart';
import 'package:path_provider/path_provider.dart';

/// Where screenshots (start/end frames) are generated.
enum ImageBackend {
  gemini('Gemini (나노바나나)'),
  openai('OpenAI (GPT Image)'),
  serviceApi('자체 서버 (service-api)');

  const ImageBackend(this.label);
  final String label;
}

/// Where videos are generated.
enum VideoBackend {
  veo('Veo'),
  serviceApi('자체 서버 (service-api)');

  const VideoBackend(this.label);
  final String label;
}

/// Storyboard Maker settings: which backend generates images vs videos, plus the
/// keys/URL they need. Gemini image generation and Veo both use [geminiKey].
/// 영상 비율(Veo 옵션).
enum VideoAspect {
  landscape('16:9', '16:9 (가로)'),
  portrait('9:16', '9:16 (세로)');

  const VideoAspect(this.value, this.label);
  final String value; // API에 보내는 값
  final String label;
}

/// 영상 해상도(Veo 옵션).
enum VideoResolution {
  hd720('720p', '720p'),
  hd1080('1080p', '1080p');

  const VideoResolution(this.value, this.label);
  final String value;
  final String label;
}

/// 자체 서버(LTX-2.3) FE2V 생성 해상도 — 비율(세로/가로)까지 한 값에 통합. 32의 배수(LTX 제약).
enum VideoRes {
  p352x640(352, 640, '352×640 · 세로'),
  l640x352(640, 352, '640×352 · 가로'),
  p544x960(544, 960, '544×960 · 세로'),
  l960x544(960, 544, '960×544 · 가로'),
  p704x1280(704, 1280, '704×1280 · 세로 (≈720p, Veo 대응)'),
  l1280x704(1280, 704, '1280×704 · 가로 (≈720p, Veo 대응)');

  const VideoRes(this.width, this.height, this.label);
  final int width;
  final int height;
  final String label;
}

/// videoRes 읽기 — 신 키(videoRes) 우선, 없으면 구버전(videoResTier + videoOrientation) 합성.
VideoRes _readVideoRes(Map<String, dynamic> j) {
  final v = j['videoRes'] as String?;
  if (v != null) {
    for (final r in VideoRes.values) {
      if (r.name == v) return r;
    }
  }
  final landscape = j['videoOrientation'] == 'landscape';
  if (j['videoResTier'] == 'r544x960') {
    return landscape ? VideoRes.l960x544 : VideoRes.p544x960;
  }
  return landscape ? VideoRes.l640x352 : VideoRes.p352x640;
}

/// 서버 고정 도메인(ngrok). serviceApiUrl(오버라이드)을 비워두면 이 주소로 연결한다.
/// (ai-image-editer의 BackendClient.fixedDomain과 값 동일하게 유지)
const String kServerDomain = 'https://camera-doctrine-galleria.ngrok-free.dev';

class MovieSettings {
  final ImageBackend imageBackend;
  final AiAspectRatio imageAspect; // Gemini/OpenAI 이미지 생성 비율
  final VideoBackend videoBackend;
  final String veoModel; // Veo 모델 id (3.1 / Fast / Lite)
  final VideoAspect videoAspect;
  final VideoResolution videoResolution;
  final VideoRes videoRes; // 자체 서버 FE2V 생성 해상도(비율 포함, 4종)
  final int videoSeconds; // 자체 서버 FE2V 영상 길이(초, 1~15)
  final int inspectorTab; // 인스펙터 마지막 선택 탭(0=장면, 1=영상, 2=공통)
  final int videoDurationSeconds; // 4 | 6 | 8
  final String videoNegativePrompt; // 영상 네거티브 프롬프트
  final String geminiKey;
  final String openaiKey;
  final String civitaiToken; // civitai LoRA 다운로드용 API 토큰(있으면 civitai URL에 자동 부착)
  final String elevenKey; // 일레븐랩스 TTS(대사 음성) API 키
  final String elevenVoiceId; // 기본(내레이션·보이스 없는 화자) 보이스 id
  final String elevenVoiceName; // 기본 보이스 이름(라벨)
  final String serviceApiUrl; // 사용자 오버라이드(비우면 kServerDomain 사용)

  /// 실제 연결 주소: 오버라이드가 있으면 그것, 없으면 고정 도메인.
  String get effectiveServiceUrl =>
      serviceApiUrl.trim().isEmpty ? kServerDomain : serviceApiUrl.trim();

  const MovieSettings({
    this.imageBackend = ImageBackend.serviceApi,
    this.imageAspect = AiAspectRatio.square,
    this.videoBackend = VideoBackend.serviceApi,
    this.veoModel = 'veo-3.1-generate-preview',
    this.videoAspect = VideoAspect.landscape,
    this.videoResolution = VideoResolution.hd720,
    this.videoRes = VideoRes.p352x640,
    this.videoSeconds = 5,
    this.inspectorTab = 0,
    this.videoDurationSeconds = 8,
    this.videoNegativePrompt = '',
    this.geminiKey = '',
    this.openaiKey = '',
    this.civitaiToken = '',
    this.elevenKey = '',
    this.elevenVoiceId = '',
    this.elevenVoiceName = '',
    this.serviceApiUrl = '', // 비우면 kServerDomain
  });

  MovieSettings copyWith({
    ImageBackend? imageBackend,
    AiAspectRatio? imageAspect,
    VideoBackend? videoBackend,
    String? veoModel,
    VideoAspect? videoAspect,
    VideoResolution? videoResolution,
    VideoRes? videoRes,
    int? videoSeconds,
    int? inspectorTab,
    int? videoDurationSeconds,
    String? videoNegativePrompt,
    String? geminiKey,
    String? openaiKey,
    String? civitaiToken,
    String? elevenKey,
    String? elevenVoiceId,
    String? elevenVoiceName,
    String? serviceApiUrl,
  }) =>
      MovieSettings(
        imageBackend: imageBackend ?? this.imageBackend,
        imageAspect: imageAspect ?? this.imageAspect,
        videoBackend: videoBackend ?? this.videoBackend,
        veoModel: veoModel ?? this.veoModel,
        videoAspect: videoAspect ?? this.videoAspect,
        videoResolution: videoResolution ?? this.videoResolution,
        videoRes: videoRes ?? this.videoRes,
        videoSeconds: videoSeconds ?? this.videoSeconds,
        inspectorTab: inspectorTab ?? this.inspectorTab,
        videoDurationSeconds: videoDurationSeconds ?? this.videoDurationSeconds,
        videoNegativePrompt: videoNegativePrompt ?? this.videoNegativePrompt,
        geminiKey: geminiKey ?? this.geminiKey,
        openaiKey: openaiKey ?? this.openaiKey,
        civitaiToken: civitaiToken ?? this.civitaiToken,
        elevenKey: elevenKey ?? this.elevenKey,
        elevenVoiceId: elevenVoiceId ?? this.elevenVoiceId,
        elevenVoiceName: elevenVoiceName ?? this.elevenVoiceName,
        serviceApiUrl: serviceApiUrl ?? this.serviceApiUrl,
      );

  Map<String, dynamic> toJson() => {
        'imageBackend': imageBackend.name,
        'imageAspect': imageAspect.name,
        'videoBackend': videoBackend.name,
        'veoModel': veoModel,
        'videoAspect': videoAspect.name,
        'videoResolution': videoResolution.name,
        'videoRes': videoRes.name,
        'videoSeconds': videoSeconds,
        'inspectorTab': inspectorTab,
        'videoDurationSeconds': videoDurationSeconds,
        'videoNegativePrompt': videoNegativePrompt,
        'geminiKey': geminiKey,
        'openaiKey': openaiKey,
        'civitaiToken': civitaiToken,
        'elevenKey': elevenKey,
        'elevenVoiceId': elevenVoiceId,
        'elevenVoiceName': elevenVoiceName,
        'serverUrl': serviceApiUrl, // 새 키 — 옛 'serviceApiUrl'(localhost 저장분)은 무시
      };

  factory MovieSettings.fromJson(Map<String, dynamic> j) => MovieSettings(
        imageBackend: ImageBackend.values.firstWhere(
          (e) => e.name == j['imageBackend'],
          orElse: () => ImageBackend.serviceApi,
        ),
        imageAspect: AiAspectRatio.values.firstWhere(
          (e) => e.name == j['imageAspect'],
          orElse: () => AiAspectRatio.square,
        ),
        videoBackend: VideoBackend.values.firstWhere(
          (e) => e.name == j['videoBackend'],
          orElse: () => VideoBackend.serviceApi,
        ),
        veoModel: (j['veoModel'] as String?) ?? 'veo-3.1-generate-preview',
        videoAspect: VideoAspect.values.firstWhere(
          (e) => e.name == j['videoAspect'],
          orElse: () => VideoAspect.landscape,
        ),
        videoResolution: VideoResolution.values.firstWhere(
          (e) => e.name == j['videoResolution'],
          orElse: () => VideoResolution.hd720,
        ),
        videoRes: _readVideoRes(j),
        videoSeconds: (j['videoSeconds'] as int?) ?? 5,
        inspectorTab: (j['inspectorTab'] as int?) ?? 0,
        videoDurationSeconds: (j['videoDurationSeconds'] as int?) ?? 8,
        videoNegativePrompt: (j['videoNegativePrompt'] as String?) ?? '',
        geminiKey: (j['geminiKey'] as String?) ?? '',
        openaiKey: (j['openaiKey'] as String?) ?? '',
        civitaiToken: (j['civitaiToken'] as String?) ?? '',
        elevenKey: (j['elevenKey'] as String?) ?? '',
        elevenVoiceId: (j['elevenVoiceId'] as String?) ?? '',
        elevenVoiceName: (j['elevenVoiceName'] as String?) ?? '',
        // 새 키만 읽는다(옛 'serviceApiUrl'은 무시 → 기존 설치도 도메인 디폴트로 시작).
        serviceApiUrl: (j['serverUrl'] as String?) ?? '',
      );
}

/// Persists [MovieSettings] to the app support folder (movie_settings.json).
class MovieSettingsStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/movie_settings.json');
  }

  Future<MovieSettings> load() async {
    final f = await _file();
    if (!await f.exists()) return const MovieSettings();
    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return const MovieSettings();
      return MovieSettings.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return const MovieSettings();
    }
  }

  Future<void> save(MovieSettings s) async {
    final f = await _file();
    const encoder = JsonEncoder.withIndent('  ');
    await f.writeAsString(encoder.convert(s.toJson()));
  }
}
