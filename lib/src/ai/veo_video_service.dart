import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_video_service.dart';

/// Google **Veo** video generation via the Gemini API. Text-to-video (and
/// image-to-video when [image] is given). This is a *long-running operation*:
/// start → poll the operation → download the resulting mp4. Can take minutes.
///
/// NOTE: the Veo model ids and the exact long-running response shape evolve —
/// the model id is editable in the UI, and the result parsing below handles the
/// common shapes (operation.response → generated sample → video uri / inline
/// bytes). Verify against the current Gemini API if a call fails.
class VeoVideoService implements AiVideoService {
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  /// How long to keep polling the operation before giving up.
  static const _pollEvery = Duration(seconds: 10);
  static const _maxPolls = 60; // ~10 minutes

  @override
  Future<Uint8List> generate({
    required String apiKey,
    required String model,
    required String prompt,
    ({List<int> bytes, String mimeType})? image,
    ({List<int> bytes, String mimeType})? lastFrame, // 끝 프레임(FE2V 보간)
    void Function(String status)? onProgress,
    String? aspectRatio, // '16:9' | '9:16'
    String? resolution, // '720p' | '1080p'
    int? durationSeconds, // 4 | 6 | 8
    String? negativePrompt,
  }) async {
    if (apiKey.trim().isEmpty) throw const VeoException('API 키를 설정하세요.');
    if (prompt.trim().isEmpty) throw const VeoException('프롬프트를 입력하세요.');
    final key = apiKey.trim();

    onProgress?.call('영상 생성 시작…');
    String opName;
    try {
      opName = await _start(key, model.trim(), prompt, image, lastFrame,
          aspectRatio, resolution, durationSeconds, negativePrompt);
    } on VeoException catch (e) {
      // 끝 프레임 고정(FE2V)은 계정·모델에 따라 **아예 열려 있지 않다** — 그럴 때 Gemini는
      // 400 "Your use case is currently not supported."로만 답한다(2026-07 실측: 같은 요청에서
      // lastFrame만 빼면 통과). 여기서 포기하면 Veo로는 한 컷도 못 뽑으므로,
      // 시작 프레임만으로(I2V) 한 번 더 간다 — 끝 그림은 모델이 정하게 된다.
      if (lastFrame == null || !_unsupportedUseCase(e.message)) rethrow;
      onProgress?.call('끝 프레임 고정이 지원되지 않아 시작 프레임만으로 생성합니다…');
      opName = await _start(key, model.trim(), prompt, image, null, aspectRatio,
          resolution, durationSeconds, negativePrompt);
    }

    onProgress?.call('생성 중… (수 분 소요)');
    final response = await _poll(key, opName, onProgress);

    onProgress?.call('영상 내려받는 중…');
    return _download(key, response);
  }

  /// 400 중에서 **기능 자체가 안 열린 경우**만 골라낸다(요청이 틀린 것과 구분).
  static bool _unsupportedUseCase(String message) =>
      message.contains('use case is currently not supported');

  /// Kick off the long-running generation; returns the operation name.
  Future<String> _start(
    String key,
    String model,
    String prompt,
    ({List<int> bytes, String mimeType})? image,
    ({List<int> bytes, String mimeType})? lastFrame,
    String? aspectRatio,
    String? resolution,
    int? durationSeconds,
    String? negativePrompt,
  ) async {
    final instance = <String, dynamic>{'prompt': prompt};
    if (image != null) {
      // image-to-video: a still first frame (predict-style payload).
      instance['image'] = {
        'bytesBase64Encoded': base64Encode(image.bytes),
        'mimeType': image.mimeType,
      };
    }
    if (lastFrame != null) {
      // first-last-frame interpolation: pin the closing frame.
      instance['lastFrame'] = {
        'bytesBase64Encoded': base64Encode(lastFrame.bytes),
        'mimeType': lastFrame.mimeType,
      };
    }
    final parameters = <String, dynamic>{
      if (aspectRatio != null && aspectRatio.isNotEmpty)
        'aspectRatio': aspectRatio,
      if (resolution != null && resolution.isNotEmpty) 'resolution': resolution,
      'durationSeconds': ? durationSeconds,
      if (negativePrompt != null && negativePrompt.trim().isNotEmpty)
        'negativePrompt': negativePrompt.trim(),
    };
    http.Response resp;
    try {
      resp = await http.post(
        Uri.parse('$_base/models/$model:predictLongRunning'),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': key,
        },
        body: jsonEncode({
          'instances': [instance],
          if (parameters.isNotEmpty) 'parameters': parameters,
        }),
      );
    } on SocketException {
      throw const VeoException('네트워크에 연결할 수 없습니다.');
    } catch (e) {
      throw VeoException('요청 실패: $e');
    }
    if (resp.statusCode != 200) {
      throw VeoException(_errorMessage(resp.statusCode, resp.body));
    }
    final data = _decode(resp.body);
    final name = data['name'];
    if (name is! String || name.isEmpty) {
      throw const VeoException('생성 작업을 시작하지 못했습니다.');
    }
    return name;
  }

  /// Poll the operation until it reports done; returns its `response` map.
  Future<Map<String, dynamic>> _poll(
    String key,
    String opName,
    void Function(String status)? onProgress,
  ) async {
    for (var i = 0; i < _maxPolls; i++) {
      await Future<void>.delayed(_pollEvery);
      http.Response resp;
      try {
        resp = await http.get(Uri.parse('$_base/$opName'),
            headers: {'x-goog-api-key': key});
      } on SocketException {
        throw const VeoException('네트워크에 연결할 수 없습니다.');
      }
      if (resp.statusCode != 200) {
        throw VeoException(_errorMessage(resp.statusCode, resp.body));
      }
      final data = _decode(resp.body);
      if (data['done'] == true) {
        final error = data['error'];
        if (error is Map && error['message'] is String) {
          throw VeoException('생성 실패: ${error['message']}');
        }
        final response = data['response'];
        if (response is Map) return response.cast<String, dynamic>();
        throw const VeoException('생성 결과가 비어 있습니다.');
      }
      onProgress?.call('생성 중… (${(i + 1) * _pollEvery.inSeconds}s)');
    }
    throw const VeoException('생성 시간이 초과되었습니다.');
  }

  /// Pull the mp4 bytes out of the finished operation response — either an
  /// inline base64 payload or a file URI we then download with the key.
  Future<Uint8List> _download(String key, Map<String, dynamic> response) async {
    final video = _findVideo(response);
    if (video == null) throw const VeoException('영상을 받지 못했습니다.');

    final inline = video['bytesBase64Encoded'] ?? video['videoBytes'];
    if (inline is String && inline.isNotEmpty) {
      try {
        return base64Decode(inline);
      } catch (_) {
        throw const VeoException('영상 디코딩에 실패했습니다.');
      }
    }
    final uri = video['uri'] ?? video['fileUri'];
    if (uri is String && uri.isNotEmpty) {
      http.Response resp;
      try {
        resp = await http.get(Uri.parse(uri), headers: {'x-goog-api-key': key});
      } on SocketException {
        throw const VeoException('네트워크에 연결할 수 없습니다.');
      }
      if (resp.statusCode != 200) {
        throw VeoException('영상 다운로드 실패 (${resp.statusCode}).');
      }
      return resp.bodyBytes;
    }
    throw const VeoException('영상을 받지 못했습니다.');
  }

  /// Walk the common response shapes to the first video object.
  Map<String, dynamic>? _findVideo(Map<String, dynamic> response) {
    // e.g. response.generateVideoResponse.generatedSamples[0].video
    final gvr = response['generateVideoResponse'];
    final samples = (gvr is Map ? gvr['generatedSamples'] : null) ??
        response['generatedSamples'] ??
        response['videos'];
    if (samples is List && samples.isNotEmpty && samples.first is Map) {
      final s = (samples.first as Map).cast<String, dynamic>();
      final v = s['video'] ?? s;
      if (v is Map) return v.cast<String, dynamic>();
    }
    return null;
  }

  @override
  Future<void> validateKey(String apiKey) async {
    if (apiKey.trim().isEmpty) throw const VeoException('API 키를 입력하세요.');
    http.Response resp;
    try {
      resp = await http.get(Uri.parse('$_base/models'),
          headers: {'x-goog-api-key': apiKey.trim()});
    } on SocketException {
      throw const VeoException('네트워크에 연결할 수 없습니다.');
    } catch (e) {
      throw VeoException('요청 실패: $e');
    }
    if (resp.statusCode != 200) {
      throw VeoException(_errorMessage(resp.statusCode, resp.body));
    }
  }

  Map<String, dynamic> _decode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw const VeoException('응답을 해석할 수 없습니다.');
    }
  }

  String _errorMessage(int code, String body) {
    var detail = '';
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] is Map && m['error']['message'] is String) {
        detail = ' ${m['error']['message']}';
      }
    } catch (_) {}
    switch (code) {
      case 400:
        return 'API 요청이 잘못되었습니다 (400).$detail';
      // 403은 "키가 틀림"만이 아니다 — 결제 미설정·모델 미허용도 여기로 온다.
      // 서버가 준 이유를 반드시 같이 보여준다(이유를 지우면 원인 못 찾는다).
      case 401:
      case 403:
        return 'API 키가 거부되었습니다 ($code).$detail';
      case 429:
        return '요청이 너무 많습니다 (429).$detail';
      default:
        return '오류 $code.$detail';
    }
  }
}

class VeoException implements Exception {
  final String message;
  const VeoException(this.message);
  @override
  String toString() => message;
}

const List<AiModelOption> kVeoVideoModels = [
  AiModelOption('veo-3.1-generate-preview', 'Veo 3.1'),
  AiModelOption('veo-3.1-fast-generate-preview', 'Veo 3.1 Fast'),
  AiModelOption('veo-3.1-lite-generate-preview', 'Veo 3.1 Lite'),
  AiModelOption('veo-3.0-generate-001', 'Veo 3 (deprecated)'),
];
