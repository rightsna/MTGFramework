/// The storyboard / movie-production kit — one project's video pipeline as an
/// embeddable unit, same idea as `package:framework/store.dart`: the host hands
/// [StoryboardScreen] a project folder + display name and the kit does the rest
/// (scene/shot authoring, AI image·video·TTS·BGM generation, preview, media
/// management — everything persists inside that folder as storyboard.json +
/// `scene<N>.json` + media files).
///
/// What stays host-side: the notion of a project LIST (which folders exist,
/// naming, deletion) — see storyboard-maker's ProjectListScreen for the
/// reference shell. Backend settings (ForgeCloud service-api URL, Gemini/
/// OpenAI/ElevenLabs keys) persist per host app in its app-support folder
/// (movie_settings.json) via [MovieSettingsStore]; [showSettingsDialog] edits
/// them.
///
/// SEPARATE entry point from `package:framework/framework.dart` — the shared
/// UI constants in ui.dart (accent, gap, …) have collision-prone names, so
/// hosts opt in explicitly (use `show`/`hide` if they clash).
library;

export 'src/storyboard/models/character.dart';
export 'src/storyboard/models/clip.dart';
export 'src/storyboard/models/dialogue.dart';
export 'src/storyboard/models/shot.dart';
export 'src/storyboard/models/story_scene.dart';
export 'src/storyboard/screens/settings/settings_dialog.dart';
export 'src/storyboard/screens/storyboard_screen.dart';
export 'src/storyboard/screens/ui.dart';
export 'src/storyboard/services/movie_settings.dart';
export 'src/storyboard/services/storyboard_store.dart';
