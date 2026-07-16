import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_image_service.dart';

/// Gemini ("나노바나나") image generation against Google's Generative Language
/// API. Text-to-image (and optional image-to-image via [images]). Returns raw
/// image bytes (PNG/JPEG). One of the [AiImageService] backends behind AiProvider.
class GeminiImageService implements AiImageService {
  static const _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Generate an image from [prompt], optionally conditioned on input [images]
  /// (image-to-image). Returns raw image bytes. Throws [GeminiException].
  @override
  Future<Uint8List> generate({
    required String apiKey,
    required String model,
    required String prompt,
    List<({List<int> bytes, String mimeType})> images = const [],
    String? aspectRatio,
  }) async {
    if (apiKey.trim().isEmpty) throw const GeminiException('API 키를 설정하세요.');
    if (prompt.trim().isEmpty) throw const GeminiException('프롬프트를 입력하세요.');

    final parts = <Map<String, dynamic>>[
      for (final im in images)
        {
          'inlineData': {
            'mimeType': im.mimeType,
            'data': base64Encode(im.bytes),
          }
        },
      {'text': prompt},
    ];

    final uri = Uri.parse('$_base/${model.trim()}:generateContent');
    http.Response resp;
    try {
      resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey.trim(),
        },
        body: jsonEncode({
          'contents': [
            {'parts': parts}
          ],
          'generationConfig': {
            'responseModalities': ['TEXT', 'IMAGE'],
            if (aspectRatio != null && aspectRatio.trim().isNotEmpty)
              'imageConfig': {'aspectRatio': aspectRatio.trim()},
          },
        }),
      );
    } on SocketException {
      throw const GeminiException('네트워크에 연결할 수 없습니다.');
    } catch (e) {
      throw GeminiException('요청 실패: $e');
    }

    if (resp.statusCode != 200) {
      throw GeminiException(_errorMessage(resp.statusCode, resp.body));
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw const GeminiException('응답을 해석할 수 없습니다.');
    }

    final bytes = _firstImage(data);
    if (bytes == null) {
      final text = _firstText(data);
      throw GeminiException(
          '이미지를 받지 못했습니다.${text != null ? '\n모델 응답: $text' : ''}');
    }
    return bytes;
  }

  /// Verify [apiKey] via a cheap authenticated GET. Throws [GeminiException].
  @override
  Future<void> validateKey(String apiKey) async {
    if (apiKey.trim().isEmpty) throw const GeminiException('API 키를 입력하세요.');
    http.Response resp;
    try {
      resp = await http.get(Uri.parse(_base),
          headers: {'x-goog-api-key': apiKey.trim()});
    } on SocketException {
      throw const GeminiException('네트워크에 연결할 수 없습니다.');
    } catch (e) {
      throw GeminiException('요청 실패: $e');
    }
    if (resp.statusCode != 200) {
      throw GeminiException(_errorMessage(resp.statusCode, resp.body));
    }
  }

  Uint8List? _firstImage(Map<String, dynamic> data) {
    for (final p in _parts(data)) {
      final inline = p['inlineData'] ?? p['inline_data'];
      if (inline is Map && inline['data'] is String) {
        try {
          return base64Decode(inline['data'] as String);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  String? _firstText(Map<String, dynamic> data) {
    for (final p in _parts(data)) {
      if (p['text'] is String) return p['text'] as String;
    }
    return null;
  }

  List<Map<String, dynamic>> _parts(Map<String, dynamic> data) {
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) return const [];
    final first = candidates.first;
    if (first is! Map) return const [];
    final content = first['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) return const [];
    return parts.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
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
      case 403:
        return 'API 키가 거부되었습니다 ($code). 키를 확인하세요.';
      case 429:
        return '요청이 너무 많습니다 (429). 잠시 후 다시 시도하세요.';
      default:
        return '오류 $code.$detail';
    }
  }
}

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);
  @override
  String toString() => message;
}

const List<AiModelOption> kGeminiImageModels = [
  AiModelOption('gemini-2.5-flash-image', '나노바나나 (2.5 Flash Image)'),
  AiModelOption('gemini-3-pro-image-preview', '나노바나나 Pro (3 Pro Image)'),
];
