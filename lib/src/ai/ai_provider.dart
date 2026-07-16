import 'ai_image_service.dart';
import 'gemini_image_service.dart';
import 'openai_image_service.dart';

/// Which image-generation backend to use. Each provider exposes its service and
/// its selectable models, so the dialog/settings stay provider-agnostic.
enum AiProvider {
  gemini('Gemini (나노바나나)'),
  openai('OpenAI (GPT Image)');

  const AiProvider(this.label);

  /// Human-readable name shown in the provider dropdown.
  final String label;

  /// A fresh service instance for this provider.
  AiImageService service() => switch (this) {
        AiProvider.gemini => GeminiImageService(),
        AiProvider.openai => OpenAiImageService(),
      };

  /// Selectable image models for this provider.
  List<AiModelOption> get models => switch (this) {
        AiProvider.gemini => kGeminiImageModels,
        AiProvider.openai => kOpenAiImageModels,
      };

  /// Default model id (first preset).
  String get defaultModel => models.first.id;
}
