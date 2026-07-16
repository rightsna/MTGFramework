import 'package:flutter/material.dart';

import 'ai_provider.dart';

/// Reusable AI connection settings — the *inner* fields only (no Scaffold, no
/// dialog). Each app embeds this in its own settings screen / popup / container
/// and keeps its own persistence.
///
/// Covers: **provider, API key (per provider), image model, shared style**, plus
/// a built-in "connection test". Edits are reported via callbacks; saving and
/// resetting the model on a provider switch are the host's job.
class AiSettingsSection extends StatefulWidget {
  const AiSettingsSection({
    super.key,
    required this.provider,
    required this.apiKey,
    required this.onProviderChanged,
    required this.onApiKeyChanged,
    this.model,
    this.onModelChanged,
    this.style,
    this.onStyleChanged,
    this.enabled = true,
    this.showHeader = true,
    this.showProvider = true,
  });

  final AiProvider provider;

  /// The key for the current [provider].
  final String apiKey;
  final ValueChanged<AiProvider> onProviderChanged;
  final ValueChanged<String> onApiKeyChanged;

  /// Optional image-model dropdown (uses [provider]'s models). Null hides it.
  final String? model;
  final ValueChanged<String>? onModelChanged;

  /// Optional shared-style field. Null hides it.
  final String? style;
  final ValueChanged<String>? onStyleChanged;

  final bool enabled;
  final bool showHeader;
  final bool showProvider;

  @override
  State<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends State<AiSettingsSection> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _styleCtrl;
  bool _obscure = true;
  bool _testing = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.apiKey);
    _styleCtrl = TextEditingController(text: widget.style ?? '');
  }

  @override
  void didUpdateWidget(AiSettingsSection old) {
    super.didUpdateWidget(old);
    // Provider switched → show that provider's key, clear the test status.
    if (old.provider != widget.provider) {
      _keyCtrl.text = widget.apiKey;
      _status = '';
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _styleCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = '연결 확인 중…';
    });
    try {
      await widget.provider.service().validateKey(_keyCtrl.text.trim());
      if (!mounted) return;
      setState(() => _status = '연결 성공 — 키가 유효합니다');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = !widget.enabled || _testing;
    final models = widget.provider.models;
    final model = widget.model == null
        ? null
        : (models.any((m) => m.id == widget.model)
            ? widget.model
            : models.first.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showHeader) ...[
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 22),
              const SizedBox(width: 8),
              Text('AI 이미지 생성',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (widget.showProvider) ...[
          DropdownButtonFormField<AiProvider>(
            initialValue: widget.provider,
            decoration: const InputDecoration(
              labelText: '프로바이더',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in AiProvider.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v != null) widget.onProviderChanged(v);
                  },
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _keyCtrl,
          obscureText: _obscure,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: '${widget.provider.label} API 키',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _obscure ? '표시' : '숨김',
              icon: Icon(_obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onChanged: widget.onApiKeyChanged,
        ),
        if (model != null) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: model,
            decoration: const InputDecoration(
              labelText: '모델',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final m in models)
                DropdownMenuItem(value: m.id, child: Text(m.label)),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v != null) widget.onModelChanged?.call(v);
                  },
          ),
        ],
        if (widget.style != null) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _styleCtrl,
            enabled: !busy,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '공통 스타일 (선택)',
              hintText: '모든 생성에 덧붙는 스타일 가이드',
              border: OutlineInputBorder(),
            ),
            onChanged: widget.onStyleChanged,
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _test,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('연결 테스트'),
          ),
        ),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_status,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}
