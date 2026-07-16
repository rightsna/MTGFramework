/// Shared building blocks for the MTG tools and editors.
///
/// Import this single barrel to get the reusable Image Editor + the AI stack:
///   import 'package:framework/framework.dart';
///
/// Exposes [ImageOps] (decode/encode/resize helpers), the embeddable
/// [ImageEditWorkspace] (canvas + crop / flood-alpha / resize / eraser / undo)
/// and [showImageEditDialog]; and the provider-agnostic AI stack:
/// [AiProvider] (Gemini / OpenAI) + [AiImageService], the [AiConfig] value type
/// + [AiConfigStore] persistence, [AiSettingsSection], and [showAiGenerateDialog].
///
/// The store-publishing kit ([StoreItemCard]) lives behind a SEPARATE entry
/// point — `import 'package:framework/store.dart'` — so its generic `AppLocale`/
/// `tr` symbols don't collide with tools that have their own.
library;

export 'src/image_ops.dart';
export 'src/image_edit_workspace.dart';
export 'src/ai/ai_image_service.dart';
export 'src/ai/gemini_image_service.dart';
export 'src/ai/openai_image_service.dart';
export 'src/ai/ai_provider.dart';
export 'src/ai/ai_video_service.dart';
export 'src/ai/veo_video_service.dart';
export 'src/ai/ai_config.dart';
export 'src/ai/ai_config_store.dart';
export 'src/ai/ai_settings_section.dart';
export 'src/ai/ai_generate_dialog.dart';
