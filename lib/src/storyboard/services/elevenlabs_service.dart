import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 일레븐랩스 TTS 클라이언트(외부 API). 대사 텍스트 → 음성(mp3) + 길이(초).
/// ForgeCloud service-api(자체 서버)와 별개로, 클라에서 직접 호출한다.
/// 다국어(한국어 포함) 지원 · 인물별 보이스로 목소리 일관성 + 더빙에 유리.
class ElevenLabsService {
  ElevenLabsService(this.apiKey);
  final String apiKey;

  static const _base = 'https://api.elevenlabs.io/v1';
  // Eleven v3 — 감정/톤 오디오 태그 지원(한국어 포함 70+). 대사에 [crying]/[whispers]/[sighs]
  // 같은 대괄호 태그를 문장 앞에 넣으면 감정 표현이 반영된다. with-timestamps로 길이도 측정됨.
  static const defaultModel = 'eleven_v3';

  Map<String, String> get _headers => {'xi-api-key': apiKey};

  /// 텍스트 → 음성. with-timestamps 엔드포인트로 **오디오 + 정렬(길이)** 을 한 번에 받는다.
  /// 정렬의 마지막 end-time이 곧 음성 길이(초). 반환: (bytes: mp3, seconds: 길이).
  Future<({Uint8List bytes, double seconds})> generateSpeech({
    required String voiceId,
    required String text,
    String modelId = defaultModel,
  }) async {
    final r = await http.post(
      Uri.parse('$_base/text-to-speech/$voiceId/with-timestamps'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'model_id': modelId}),
    );
    if (r.statusCode != 200) {
      throw Exception('일레븐랩스 ${r.statusCode}: ${utf8.decode(r.bodyBytes)}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final b64 = j['audio_base64'] as String?;
    if (b64 == null) throw Exception('일레븐랩스 응답에 오디오가 없습니다');
    final bytes = base64Decode(b64);
    final align = (j['alignment'] as Map?)?.cast<String, dynamic>();
    final ends = (align?['character_end_times_seconds'] as List?)?.cast<num>();
    final seconds = (ends != null && ends.isNotEmpty)
        ? ends.last.toDouble()
        : _estimate(text); // 정렬이 없으면 글자수 기반 대략치
    return (bytes: bytes, seconds: seconds);
  }

  // 정렬 정보가 없을 때의 대략적 길이(초) — 글자수 기반.
  double _estimate(String text) =>
      (text.trim().length * 0.09).clamp(1.0, 60.0);

  /// 사용 가능한 보이스 목록(인물별·기본 보이스 지정용).
  Future<List<ElevenVoice>> listVoices() async {
    final r = await http
        .get(Uri.parse('$_base/voices'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw Exception('일레븐랩스 ${r.statusCode}: ${utf8.decode(r.bodyBytes)}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final v in (j['voices'] as List? ?? const []))
        ElevenVoice(
          id: v['voice_id'] as String,
          name: (v['name'] as String?) ?? '(이름 없음)',
          category: v['category'] as String?,
        ),
    ];
  }
}

/// 일레븐랩스 보이스 하나(목록용).
class ElevenVoice {
  const ElevenVoice({required this.id, required this.name, this.category});
  final String id;
  final String name;
  final String? category; // premade / cloned / professional …
}
