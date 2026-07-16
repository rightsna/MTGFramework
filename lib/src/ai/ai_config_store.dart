import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'ai_config.dart';

/// Loads/saves an [AiConfig] as JSON at an app-chosen location. The *only*
/// app-specific bit of AI persistence — construct one with the file path and
/// hand it to the shared dialog/settings; everything else lives in framework.
class AiConfigStore {
  /// Resolves the backing file lazily (the path may need async lookup).
  final Future<File> Function() _resolve;

  const AiConfigStore(this._resolve);

  /// Store at an absolute file [path] (e.g. a project's dist/ai_config.json).
  AiConfigStore.path(String path) : _resolve = (() async => File(path));

  /// Store at `<app-support>/[name]` — for sandboxed desktop tools.
  AiConfigStore.appSupport([String name = 'ai_config.json'])
      : _resolve = (() async {
          final dir = await getApplicationSupportDirectory();
          return File('${dir.path}/$name');
        });

  Future<AiConfig> load() async {
    final f = await _resolve();
    if (!await f.exists()) return const AiConfig();
    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return const AiConfig();
      return AiConfig.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return const AiConfig();
    }
  }

  Future<void> save(AiConfig config) async {
    final f = await _resolve();
    if (!await f.parent.exists()) await f.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await f.writeAsString(encoder.convert(config.toJson()));
  }
}
