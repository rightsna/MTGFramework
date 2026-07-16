import 'dart:typed_data';

/// A selectable image model. The [id] is what the API receives (editable in the
/// UI in case a provider renames a preview model); [label] is shown to the user.
class AiModelOption {
  final String id;
  final String label;
  const AiModelOption(this.id, this.label);
}

/// Output aspect ratio for generation. [ratio] is the provider-neutral "W:H"
/// string each service maps to its own knob — Gemini's `imageConfig.aspectRatio`
/// or OpenAI's nearest `size` bucket. All listed ratios are honored by Gemini;
/// OpenAI buckets them to square / landscape / portrait.
enum AiAspectRatio {
  square('정사각 (1:1)', '1:1'),
  landscape('가로 (16:9)', '16:9'),
  portrait('세로 (9:16)', '9:16'),
  landscapeClassic('가로 (4:3)', '4:3'),
  portraitClassic('세로 (3:4)', '3:4');

  const AiAspectRatio(this.label, this.ratio);

  /// Shown in the dropdown.
  final String label;

  /// Provider-neutral "W:H" sent to the service.
  final String ratio;
}

/// Common interface for image-generation backends so the Gemini and OpenAI
/// services are interchangeable behind [AiProvider]. Implementations may add
/// extra optional params (e.g. OpenAI's `size`).
abstract interface class AiImageService {
  /// Generate an image from [prompt], optionally conditioned on input [images]
  /// (image-to-image). [aspectRatio] is a provider-neutral "W:H" string (null =
  /// provider default). Returns raw image bytes. Throws a provider exception.
  Future<Uint8List> generate({
    required String apiKey,
    required String model,
    required String prompt,
    List<({List<int> bytes, String mimeType})> images,
    String? aspectRatio,
  });

  /// Verify [apiKey] via a cheap authenticated request. Throws on failure.
  Future<void> validateKey(String apiKey);
}
