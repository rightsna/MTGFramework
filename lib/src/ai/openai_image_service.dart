import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'ai_image_service.dart';

/// OpenAI image generation (gpt-image-1 / DALL·E). One of the [AiImageService]
/// backends behind AiProvider: text-to-image via `/v1/images/generations`, and
/// image-to-image (with input [images]) via `/v1/images/edits`. Returns raw
/// image bytes. Throws [OpenAiException] with a readable message on failure.
class OpenAiImageService implements AiImageService {
  static const _genUrl = 'https://api.openai.com/v1/images/generations';
  static const _editUrl = 'https://api.openai.com/v1/images/edits';
  static const _modelsUrl = 'https://api.openai.com/v1/models';

  /// Generate an image from [prompt], optionally conditioned on input [images]
  /// (image-to-image / edit — gpt-image-1). [size] is the output resolution.
  /// Returns raw image bytes. Throws [OpenAiException].
  @override
  Future<Uint8List> generate({
    required String apiKey,
    required String model,
    required String prompt,
    List<({List<int> bytes, String mimeType})> images = const [],
    String? aspectRatio,
    String? size,
  }) async {
    if (apiKey.trim().isEmpty) throw const OpenAiException('API 키를 설정하세요.');
    if (prompt.trim().isEmpty) throw const OpenAiException('프롬프트를 입력하세요.');

    // OpenAI takes a pixel size, not a ratio — bucket the ratio to the nearest
    // size this model supports. An explicit [size] wins if given.
    final outSize = size ?? _sizeForRatio(model, aspectRatio);

    http.Response resp;
    try {
      resp = images.isEmpty
          ? await _generation(apiKey, model, prompt, outSize)
          : await _edit(apiKey, model, prompt, outSize, images);
    } on SocketException {
      throw const OpenAiException('네트워크에 연결할 수 없습니다.');
    } on OpenAiException {
      rethrow;
    } catch (e) {
      throw OpenAiException('요청 실패: $e');
    }

    if (resp.statusCode != 200) {
      throw OpenAiException(_errorMessage(resp.statusCode, resp.body));
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw const OpenAiException('응답을 해석할 수 없습니다.');
    }
    return _firstImage(data);
  }

  Future<http.Response> _generation(
      String apiKey, String model, String prompt, String size) {
    return http.post(
      Uri.parse(_genUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      },
      body: jsonEncode({
        'model': model.trim(),
        'prompt': prompt,
        'n': 1,
        'size': size,
      }),
    );
  }

  Future<http.Response> _edit(
    String apiKey,
    String model,
    String prompt,
    String size,
    List<({List<int> bytes, String mimeType})> images,
  ) async {
    final req = http.MultipartRequest('POST', Uri.parse(_editUrl))
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..fields['model'] = model.trim()
      ..fields['prompt'] = prompt
      ..fields['n'] = '1'
      ..fields['size'] = size;
    for (var i = 0; i < images.length; i++) {
      final im = images[i];
      final ext = _ext(im.mimeType);
      // contentType을 명시하지 않으면 application/octet-stream으로 전송돼 OpenAI가
      // 거부한다("unsupported mimetype"). 실제 이미지 타입을 지정한다(jpg→jpeg).
      req.files.add(http.MultipartFile.fromBytes(
        'image[]',
        im.bytes,
        filename: 'image_$i.$ext',
        contentType: MediaType('image', ext == 'jpg' ? 'jpeg' : ext),
      ));
    }
    final streamed = await req.send();
    return http.Response.fromStream(streamed);
  }

  /// OpenAI only offers square / landscape / portrait sizes (and they differ by
  /// model), so map the provider-neutral [aspectRatio] to the nearest one.
  /// Null ratio → square, matching the previous fixed default.
  String _sizeForRatio(String model, String? aspectRatio) {
    final isDalle = model.trim().startsWith('dall-e');
    if (aspectRatio == null || aspectRatio.trim().isEmpty) return '1024x1024';
    final parts = aspectRatio.split(':');
    final w = double.tryParse(parts.first.trim()) ?? 1;
    final h = double.tryParse(parts.length > 1 ? parts[1].trim() : '1') ?? 1;
    if ((w - h).abs() < 0.01) return '1024x1024'; // square
    if (w > h) return isDalle ? '1792x1024' : '1536x1024'; // landscape
    return isDalle ? '1024x1792' : '1024x1536'; // portrait
  }

  String _ext(String mimeType) {
    if (mimeType.contains('jpeg') || mimeType.contains('jpg')) return 'jpg';
    if (mimeType.contains('webp')) return 'webp';
    return 'png';
  }

  /// Verify [apiKey] via a cheap authenticated GET. Throws [OpenAiException].
  @override
  Future<void> validateKey(String apiKey) async {
    if (apiKey.trim().isEmpty) throw const OpenAiException('API 키를 입력하세요.');
    http.Response resp;
    try {
      resp = await http.get(Uri.parse(_modelsUrl),
          headers: {'Authorization': 'Bearer ${apiKey.trim()}'});
    } on SocketException {
      throw const OpenAiException('네트워크에 연결할 수 없습니다.');
    } catch (e) {
      throw OpenAiException('요청 실패: $e');
    }
    if (resp.statusCode != 200) {
      throw OpenAiException(_errorMessage(resp.statusCode, resp.body));
    }
  }

  /// OpenAI returns `data[0].b64_json` (gpt-image-1 default) or `data[0].url`
  /// (DALL·E default) — handle both.
  Uint8List _firstImage(Map<String, dynamic> data) {
    final list = data['data'];
    if (list is! List || list.isEmpty || list.first is! Map) {
      throw const OpenAiException('이미지를 받지 못했습니다.');
    }
    final first = (list.first as Map).cast<String, dynamic>();
    final b64 = first['b64_json'];
    if (b64 is String && b64.isNotEmpty) {
      try {
        return base64Decode(b64);
      } catch (_) {
        throw const OpenAiException('이미지 디코딩에 실패했습니다.');
      }
    }
    throw const OpenAiException('이미지를 받지 못했습니다.');
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
      case 401:
        return 'API 키가 거부되었습니다 (401). 키를 확인하세요.';
      case 403:
        return '권한이 없습니다 (403).$detail';
      case 429:
        return '요청이 너무 많습니다 (429). 잠시 후 다시 시도하세요.';
      default:
        return '오류 $code.$detail';
    }
  }
}

class OpenAiException implements Exception {
  final String message;
  const OpenAiException(this.message);
  @override
  String toString() => message;
}

const List<AiModelOption> kOpenAiImageModels = [
  AiModelOption('gpt-image-2', 'GPT Image 2'),
  AiModelOption('gpt-image-1', 'GPT Image 1'),
  AiModelOption('gpt-image-1-mini', 'GPT Image 1 mini'),
  AiModelOption('dall-e-3', 'DALL·E 3'),
];
