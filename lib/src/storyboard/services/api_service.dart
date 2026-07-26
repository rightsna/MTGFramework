import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thin client for the ForgeCloud gateway (service-api).
/// No ComfyUI graphs here — just REST calls. The server hides all of that.
///
/// 영상: 시작+끝 두 프레임으로 FE2V 생성. 해상도는 설정(VideoRes)에서 선택.
enum GenMode {
  imageStart,
  imageEnd,
  videoLow; // 영상 생성 (FE2V). 해상도는 설정(VideoRes)에서 선택.

  bool get isVideo => this == GenMode.videoLow;
  String get label => switch (this) {
        GenMode.imageStart => '시작장면',
        GenMode.imageEnd => '끝장면',
        GenMode.videoLow => '영상 생성',
      };
}

/// service-api 접속 상태 스냅샷.
class ApiStatus {
  const ApiStatus({
    required this.reachable,
    this.videoReady = false,
    this.audioReady = false,
  });

  final bool reachable; // /health 응답 여부
  final bool videoReady; // video-ltx 워크플로 설치됨(=/video 사용 가능)
  final bool audioReady; // bgm 워크플로 설치됨(=/bgm 사용 가능)

  factory ApiStatus.offline() => const ApiStatus(reachable: false);
}

class ApiService {
  ApiService(this.baseUrl);
  final String baseUrl;

  String get _base => baseUrl.replaceAll(RegExp(r'/+$'), '');

  /// ngrok 무료 터널은 브라우저 UA 요청에 경고 HTML을 끼운다. 이 헤더로 인터스티셜을
  /// 건너뛰어 도메인 접속 시에도 항상 실제 응답(JSON/미디어)을 받는다.
  static const Map<String, String> _ngrok = {
    'ngrok-skip-browser-warning': 'true',
  };

  /// 접속 상태 확인: /health 로 서버 도달 여부, /workflow/video-ltx 로 영상 워크플로 설치 여부.
  Future<ApiStatus> checkStatus() async {
    bool reachable = false;
    try {
      final r = await http
          .get(Uri.parse('$_base/health'), headers: _ngrok)
          .timeout(const Duration(seconds: 6));
      reachable = r.statusCode == 200;
    } catch (_) {}
    if (!reachable) return ApiStatus.offline();
    bool videoReady = false;
    try {
      final r = await http
          .get(Uri.parse('$_base/workflow/video-ltx'), headers: _ngrok)
          .timeout(const Duration(seconds: 3));
      videoReady = r.statusCode == 200;
    } catch (_) {}
    bool audioReady = false;
    try {
      final r = await http
          .get(Uri.parse('$_base/workflow/bgm'), headers: _ngrok)
          .timeout(const Duration(seconds: 3));
      audioReady = r.statusCode == 200;
    } catch (_) {}
    return ApiStatus(
        reachable: true, videoReady: videoReady, audioReady: audioReady);
  }

  /// 텍스트→이미지 (/image). 시작/끝 스크린샷 생성용.
  /// [width]/[height]는 함께 지정(둘 다 8의 배수). 0이면 서버 워크플로 기본(1024×1024 정사각).
  Future<Uint8List> generateImage(
    String prompt, {
    int width = 0,
    int height = 0,
  }) async {
    final r = await http.post(
      Uri.parse('$_base/image'),
      headers: const {'Content-Type': 'application/json', ..._ngrok},
      body: jsonEncode({
        'prompt': prompt,
        if (width > 0 && height > 0) 'width': width,
        if (width > 0 && height > 0) 'height': height,
      }),
    );
    _check(r.statusCode, r.bodyBytes);
    return r.bodyBytes;
  }

  /// 인물 레퍼런스 기반 장면 생성 (/edit, FireRed 멀티 레퍼런스). 참조 이미지 1~3장 + 지시문 →
  /// 각 인물 정체성(얼굴·의상)을 유지하며 지시문대로 장면을 생성한다. (w/h 미지정=전체)
  /// image(필수) + image2·image3(선택)로 보낸다.
  Future<Uint8List> generateImageWithRefs({
    required List<Uint8List> references,
    required String prompt,
    bool translate = false,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/edit'))
      ..headers.addAll(_ngrok)
      ..fields['prompt'] = prompt
      ..fields['translate'] = translate ? 'true' : 'false';
    for (var i = 0; i < references.length && i < 3; i++) {
      final field = i == 0 ? 'image' : 'image${i + 1}';
      req.files.add(http.MultipartFile.fromBytes(field, references[i],
          filename: '$field.png'));
    }
    final r = await http.Response.fromStream(await req.send());
    _check(r.statusCode, r.bodyBytes);
    return r.bodyBytes;
  }

  /// 텍스트→배경음악 (/bgm, ACE-Step 인스트루멘탈). 스타일 태그 + 길이(초) → mp3 바이트.
  Future<Uint8List> generateBgm({
    required String prompt,
    required int seconds,
  }) async {
    final r = await http.post(
      Uri.parse('$_base/bgm'),
      headers: const {'Content-Type': 'application/json', ..._ngrok},
      body: jsonEncode({'prompt': prompt, 'seconds': seconds}),
    );
    _check(r.statusCode, r.bodyBytes);
    return r.bodyBytes;
  }

  /// 이미지→영상. 모션 프롬프트 + 해상도(32의 배수).
  ///  - [endImage] 를 주면 **FE2V**: 시작을 첫 프레임, 끝을 마지막 프레임으로 고정해 그 사이를 생성.
  ///  - [endImage] 가 null 이면 **I2V**: 시작 한 장만 고정하고 끝은 모델이 자유롭게.
  /// 서버는 image_end 유무로 워크플로(video-ltx / video-ltx-i2v)를 알아서 고른다.
  ///
  /// 영상은 수 분(8초면 2~7분) 걸린다. 한 요청을 끝까지 열어두면 프록시(ngrok)가 60초쯤에
  /// 끊어버리므로(ERR_NGROK_3004), **제출 → 폴링 → 결과 수신** 3단계로 나눠 부른다.
  /// 각 요청이 1초 미만이라 프록시 타임아웃에 안 걸린다.
  /// **제출만** 하고 job_id를 즉시 돌려준다(비동기 생성). 라이브 폴링은 하지 않는다 —
  /// 호출부가 job_id를 저장해두고, 리컨실러가 [pollVideoStatus]/[fetchVideoResult]로 나중에 받는다.
  /// 이렇게 하면 앱을 껐다 켜도 진행 중 생성이 살아남고, 동시에 여러 개를 걸어도 폴링 폭주가 없다.
  ///
  /// 서버가 큐 백프레셔로 503(Retry-After)을 주면 잠깐 뒤 다시 제출한다(최대 10분).
  /// MultipartRequest는 한 번 보내면 스트림이 소진돼 재사용이 안 되므로 시도마다 새로 만든다.
  Future<String> submitVideoJob({
    required Uint8List image,
    Uint8List? endImage, // null = I2V (끝 프레임 없이 생성)
    required String prompt,
    String negativePrompt = '', // 빼고 싶은 것만 — 비우면 워크플로 기본 네거티브
    required int width,
    required int height,
    required int seconds,
    String loraUrl = '',
    double loraStrength = 0.8,
    void Function(String status)? onProgress,
  }) async {
    http.MultipartRequest buildReq() {
      final r = http.MultipartRequest('POST', Uri.parse('$_base/video'))
        ..headers.addAll(_ngrok)
        ..fields['prompt'] = prompt
        ..fields['negative_prompt'] = negativePrompt
        ..fields['width'] = '$width'
        ..fields['height'] = '$height'
        ..fields['seconds'] = '$seconds'
        ..fields['lora_url'] = loraUrl
        ..fields['lora_strength'] = '$loraStrength'
        ..files.add(
            http.MultipartFile.fromBytes('image', image, filename: 'start.png'));
      // I2V면 끝 프레임을 아예 안 붙인다 — 서버가 그걸 보고 i2v 워크플로로 간다.
      if (endImage != null) {
        r.files.add(http.MultipartFile.fromBytes('image_end', endImage,
            filename: 'end.png'));
      }
      return r;
    }

    final queueStarted = DateTime.now();
    while (true) {
      final sub = await http.Response.fromStream(await buildReq().send());
      if (sub.statusCode == 503) {
        if (DateTime.now().difference(queueStarted).inMinutes >= 10) {
          throw Exception('영상 큐가 계속 가득 차 있습니다 — 잠시 후 다시 시도해 주세요');
        }
        onProgress?.call('생성 대기열 혼잡 — 순서 기다리는 중…');
        await Future<void>.delayed(const Duration(seconds: 5));
        continue;
      }
      _check(sub.statusCode, sub.bodyBytes);
      return (jsonDecode(utf8.decode(sub.bodyBytes)) as Map)['job_id'] as String;
    }
  }

  /// 영상 job 상태 한 번 조회: state = running|done|error. 네트워크/타임아웃이면 던진다
  /// (호출부=리컨실러가 잡아 다음 스윕에 다시 시도 — 한 번 실패로 생성을 죽이지 않는다).
  Future<({String state, String? error})> pollVideoStatus(String jobId) async {
    final s = await http
        .get(Uri.parse('$_base/video/$jobId'), headers: _ngrok)
        .timeout(const Duration(seconds: 10));
    _check(s.statusCode, s.bodyBytes);
    final j = jsonDecode(utf8.decode(s.bodyBytes)) as Map<String, dynamic>;
    return (state: (j['state'] as String?) ?? 'running', error: j['error'] as String?);
  }

  /// 완료된 job의 mp4 바이트. 다운로드가 무료 ngrok 터널 포화로 한 번 끊겨도 몇 번 재시도한다.
  Future<Uint8List> fetchVideoResult(String jobId) async {
    Object? lastErr;
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        final r = await http.get(Uri.parse('$_base/video/$jobId/result'),
            headers: _ngrok);
        _check(r.statusCode, r.bodyBytes);
        return r.bodyBytes;
      } catch (e) {
        lastErr = e;
        if (attempt < 4) await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    throw Exception('영상 다운로드 실패(4회 재시도) — 네트워크를 확인해 주세요: $lastErr');
  }

  /// 진행 중인 영상 job 취소(best-effort) — 서버가 대기 중이면 큐에서 빼고, 실행 중이면 멈춘다.
  /// 이미 끝났거나 유실됐어도 서버는 조용히 성공한다. 짧은 타임아웃 — 취소는 빨라야 하니까.
  Future<void> cancelVideoJob(String jobId) async {
    final r = await http
        .delete(Uri.parse('$_base/video/$jobId'), headers: _ngrok)
        .timeout(const Duration(seconds: 10));
    _check(r.statusCode, r.bodyBytes);
  }

  // ───────── LoRA 관리 (서버 custom/ 폴더) ─────────

  /// 받아둔 커스텀 LoRA 목록 + 총 용량(MB).
  Future<({List<LoraInfo> items, double totalMb})> listLoras() async {
    final r = await http
        .get(Uri.parse('$_base/loras'), headers: _ngrok)
        .timeout(const Duration(seconds: 10));
    _check(r.statusCode, r.bodyBytes);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final items = [
      for (final e in (j['loras'] as List))
        LoraInfo(e['name'] as String, (e['size_mb'] as num).toDouble()),
    ];
    return (items: items, totalMb: (j['total_mb'] as num).toDouble());
  }

  Future<void> deleteLora(String name) async {
    final r = await http
        .delete(Uri.parse('$_base/loras/${Uri.encodeComponent(name)}'), headers: _ngrok)
        .timeout(const Duration(seconds: 10));
    _check(r.statusCode, r.bodyBytes);
  }

  Future<void> clearLoras() async {
    final r = await http
        .delete(Uri.parse('$_base/loras'), headers: _ngrok)
        .timeout(const Duration(seconds: 15));
    _check(r.statusCode, r.bodyBytes);
  }

  void _check(int status, Uint8List body) {
    if (status != 200) {
      throw Exception('$status: ${utf8.decode(body)}');
    }
  }
}

/// 서버에 받아둔 LoRA 하나의 정보.
class LoraInfo {
  const LoraInfo(this.name, this.sizeMb);
  final String name;
  final double sizeMb;
}
