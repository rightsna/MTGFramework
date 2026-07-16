import 'dart:typed_data';

import 'ai_image_service.dart' show AiModelOption;

export 'ai_image_service.dart' show AiModelOption;

/// Common interface for video-generation backends (so Veo and an app's own
/// server can be swapped). Generation is long-running (minutes); [onProgress]
/// reports human-readable status while waiting.
abstract interface class AiVideoService {
  /// Generate a video from [prompt], optionally animating a still [image]
  /// (image-to-video). Returns raw video bytes (mp4). Throws on failure.
  Future<Uint8List> generate({
    required String apiKey,
    required String model,
    required String prompt,
    ({List<int> bytes, String mimeType})? image,
    void Function(String status)? onProgress,
  });

  /// Verify [apiKey]. Throws on failure.
  Future<void> validateKey(String apiKey);
}

/// Re-exported helper type for callers building video-model dropdowns.
typedef AiVideoModelOption = AiModelOption;
