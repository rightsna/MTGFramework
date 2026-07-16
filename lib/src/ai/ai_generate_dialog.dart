import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'ai_config.dart';
import 'ai_config_store.dart';
import 'ai_image_service.dart';
import 'ai_provider.dart';

/// A reference image fed into generation (image-to-image): the model composites
/// / edits it per the prompt. [label] names it in the dialog's preview.
class AiBaseImage {
  final Uint8List bytes;
  final String mimeType;
  final String label;
  const AiBaseImage(this.bytes, {this.mimeType = 'image/png', this.label = ''});
}

/// Identifies a generation context so each kind of art keeps its own shared
/// "group prompt" (the middle tier between the app-wide style and the per-call
/// prompt). [key] is the storage key; [label] is shown in the dialog.
class AiPromptGroup {
  final String key;
  final String label;
  const AiPromptGroup(this.key, this.label);
}

/// Open the self-contained AI image-generation dialog. Everything AI lives in
/// framework — the host app only supplies a [store] (where to persist the key /
/// settings) and the call context ([group], [baseImages], default prompts).
/// Returns the generated image bytes on success, or null on cancel.
Future<Uint8List?> showAiGenerateDialog(
  BuildContext context, {
  required AiConfigStore store,
  AiPromptGroup? group,
  List<AiBaseImage> baseImages = const [],
  String defaultStyle = '',
  String defaultPrompt = '',
  String title = 'AI 이미지 생성',
  bool barrierDismissible = false,
}) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => _AiGenerateDialog(
      store: store,
      group: group,
      baseImages: baseImages,
      defaultStyle: defaultStyle,
      defaultPrompt: defaultPrompt,
      title: title,
    ),
  );
}

class _AiGenerateDialog extends StatefulWidget {
  const _AiGenerateDialog({
    required this.store,
    required this.group,
    required this.baseImages,
    required this.defaultStyle,
    required this.defaultPrompt,
    required this.title,
  });

  final AiConfigStore store;
  final AiPromptGroup? group;
  final List<AiBaseImage> baseImages;
  final String defaultStyle;
  final String defaultPrompt;
  final String title;

  @override
  State<_AiGenerateDialog> createState() => _AiGenerateDialogState();
}

class _AiGenerateDialogState extends State<_AiGenerateDialog> {
  final _modelCtrl = TextEditingController();
  final _styleCtrl = TextEditingController();
  final _groupCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();

  AiConfig _config = const AiConfig();
  AiAspectRatio _aspect = AiAspectRatio.square;
  late final List<bool> _useBase =
      List<bool>.filled(widget.baseImages.length, true);
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _hasGroup => widget.group != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _modelCtrl.text = cfg.model;
      _styleCtrl.text = cfg.style.isNotEmpty ? cfg.style : widget.defaultStyle;
      _groupCtrl.text =
          _hasGroup ? (cfg.groupPrompts[widget.group!.key] ?? '') : '';
      _promptCtrl.text =
          cfg.prompt.isNotEmpty ? cfg.prompt : widget.defaultPrompt;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _styleCtrl.dispose();
    _groupCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  String get _combinedPrompt {
    final style = _styleCtrl.text.trim();
    final group = _groupCtrl.text.trim();
    final prompt = _promptCtrl.text.trim();
    return [
      if (prompt.isNotEmpty) prompt,
      if (_hasGroup && group.isNotEmpty) group,
      if (style.isNotEmpty) '스타일: $style',
    ].join('\n\n');
  }

  Future<void> _generate() async {
    if (_promptCtrl.text.trim().isEmpty) {
      setState(() => _error = '프롬프트를 입력하세요.');
      return;
    }
    if (_config.apiKey.trim().isEmpty) {
      setState(() => _error =
          '${_config.provider.label} API 키가 설정되지 않았습니다. 설정에서 키를 입력하세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Persist everything first so model/style/group/prompt survive a failure.
    final groups = Map<String, String>.of(_config.groupPrompts);
    if (_hasGroup) groups[widget.group!.key] = _groupCtrl.text.trim();
    final updated = _config.copyWith(
      model: _modelCtrl.text.trim(),
      style: _styleCtrl.text.trim(),
      prompt: _promptCtrl.text.trim(),
      groupPrompts: groups,
    );
    await widget.store.save(updated);
    _config = updated;
    try {
      final images = <({List<int> bytes, String mimeType})>[
        for (var i = 0; i < widget.baseImages.length; i++)
          if (_useBase[i])
            (
              bytes: widget.baseImages[i].bytes,
              mimeType: widget.baseImages[i].mimeType,
            ),
      ];
      final bytes = await _config.provider.service().generate(
        apiKey: _config.apiKey,
        model: _modelCtrl.text,
        prompt: _combinedPrompt,
        images: images,
        aspectRatio: _aspect.ratio,
      );
      if (!mounted) return;
      Navigator.of(context).pop<Uint8List>(bytes);
    } catch (e) {
      // Gemini/OpenAi exceptions stringify to their readable message.
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _keyStatusRow() {
    final has = _config.apiKey.trim().isNotEmpty;
    final label = _config.provider.label;
    return Row(
      children: [
        Icon(has ? Icons.key : Icons.key_off,
            size: 18, color: has ? Colors.green : Colors.orange),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            has ? '$label API 키: 설정됨' : '$label API 키: 미설정',
            style: TextStyle(fontSize: 13, color: has ? null : Colors.orange),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 20),
          const SizedBox(width: 8),
          Text(widget.title),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 프로바이더 선택 — 바꾸면 모델을 그 프로바이더 기본값으로.
                    DropdownButtonFormField<AiProvider>(
                      initialValue: _config.provider,
                      decoration: const InputDecoration(
                        labelText: '프로바이더',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in AiProvider.values)
                          DropdownMenuItem(value: p, child: Text(p.label)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() {
                                _config = _config.copyWith(provider: v);
                                _modelCtrl.text = v.defaultModel;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _config.provider.models
                                  .any((m) => m.id == _modelCtrl.text)
                              ? _modelCtrl.text
                              : null,
                          hint: const Text('모델 선택'),
                          items: [
                            for (final m in _config.provider.models)
                              DropdownMenuItem(value: m.id, child: Text(m.label)),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setState(() => _modelCtrl.text = v);
                                  }
                                },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _modelCtrl,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: '모델 id',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AiAspectRatio>(
                      initialValue: _aspect,
                      decoration: const InputDecoration(
                        labelText: '비율',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final a in AiAspectRatio.values)
                          DropdownMenuItem(value: a, child: Text(a.label)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v != null) setState(() => _aspect = v);
                            },
                    ),
                    const SizedBox(height: 12),
                    _keyStatusRow(),
                    if (widget.baseImages.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('기반 이미지 (이걸 합성·수정해서 생성)',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < widget.baseImages.length; i++)
                            _BasePreview(
                              base: widget.baseImages[i],
                              included: _useBase[i],
                              onToggle: _busy
                                  ? null
                                  : () => setState(
                                      () => _useBase[i] = !_useBase[i]),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _styleCtrl,
                      enabled: !_busy,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText:
                            _hasGroup ? '① 공통 스타일 (앱 전역 공유)' : '공통 스타일 (전역 공유)',
                        hintText: '모든 생성에 공통 적용할 화풍·톤',
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (_hasGroup) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _groupCtrl,
                        enabled: !_busy,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: '② 그룹 프롬프트 — ${widget.group!.label} (그룹 공유)',
                          hintText: '이 그룹의 모든 생성에 공통 적용',
                          border: const OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _promptCtrl,
                      enabled: !_busy,
                      autofocus: true,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: _hasGroup ? '③ 프롬프트 (이번 생성)' : '프롬프트 (이번 생성)',
                        hintText: '이번에 생성할 이미지 (영어가 대체로 더 정확)',
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          onPressed: (_busy || _loading) ? null : _generate,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(_busy ? '생성 중…' : '생성'),
        ),
      ],
    );
  }
}

/// A toggleable thumbnail of one reference image. Dimmed when excluded.
class _BasePreview extends StatelessWidget {
  final AiBaseImage base;
  final bool included;
  final VoidCallback? onToggle;
  const _BasePreview({
    required this.base,
    required this.included,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: included
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white24,
                    width: included ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                clipBehavior: Clip.antiAlias,
                child: Opacity(
                  opacity: included ? 1 : 0.35,
                  child: Image.memory(base.bytes, fit: BoxFit.cover),
                ),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: Icon(
                  included ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                  color: included
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white54,
                ),
              ),
            ],
          ),
          if (base.label.isNotEmpty)
            SizedBox(
              width: 56,
              child: Text(
                base.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}
