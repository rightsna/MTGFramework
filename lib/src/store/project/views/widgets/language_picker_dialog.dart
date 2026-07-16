import 'package:flutter/material.dart';

import '../../../l10n/app_locale.dart';
import '../../models/store_locale.dart';

/// Result of the language picker: the chosen locale codes (catalog order, never
/// empty) and whether newly-added languages should be seeded from the primary.
class LangPickResult {
  const LangPickResult(this.locales, this.cloneNewFromPrimary);
  final List<String> locales;
  final bool cloneNewFromPrimary;
}

/// Pick which App Store languages a project authors screenshots for. Returns a
/// [LangPickResult] on Save, or null on Cancel. Codes already on the project
/// that aren't in the catalog are listed too, so an externally-authored locale
/// folder is never silently dropped.
class LanguagePickerDialog extends StatefulWidget {
  const LanguagePickerDialog({
    super.key,
    required this.initial,
    required this.primaryLabel,
  });
  final List<String> initial;

  /// Display label of the first (primary) language — shown in the clone toggle.
  final String primaryLabel;

  @override
  State<LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<LanguagePickerDialog> {
  late final Set<String> _sel = {...widget.initial};
  bool _clone = false;

  @override
  Widget build(BuildContext context) {
    final english = AppLocale.of(context).english;
    final codes = <String>[
      for (final l in kStoreLocales) l.code,
      ...widget.initial.where((c) => storeLocaleByCode(c) == null),
    ];
    final initialSet = widget.initial.toSet();
    final hasNew = _sel.any((c) => !initialSet.contains(c));
    return AlertDialog(
      title: Text(tr(context, '스크린샷 언어', 'Screenshot languages')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, '언어별로 스크린샷 셋을 따로 관리합니다. 해제해도 파일은 지워지지 않습니다.',
                  'Each language keeps its own screenshot set. Unchecking only hides its folder — files are kept.'),
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final code in codes)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _sel.contains(code),
                      title:
                          Text(storeLocaleLabel(code, english: english)),
                      subtitle: Text(code,
                          style: const TextStyle(fontSize: 11)),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _sel.add(code);
                        } else {
                          _sel.remove(code);
                        }
                      }),
                    ),
                ],
              ),
            ),
            const Divider(height: 16),
            // Clone toggle: seed newly-added languages from the primary set.
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _clone,
              onChanged: hasNew ? (v) => setState(() => _clone = v) : null,
              title: Text(
                tr(context, '새 언어를 복제로 채우기',
                    'Fill new languages by cloning'),
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                tr(
                  context,
                  "추가한 언어를 '${widget.primaryLabel}' 스샷으로 복제합니다 (비어있는 언어만).",
                  "Copy '${widget.primaryLabel}' screenshots into newly added languages (empty ones only).",
                ),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(context, '취소', 'Cancel')),
        ),
        FilledButton(
          onPressed: _sel.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    LangPickResult(
                      [for (final c in codes) if (_sel.contains(c)) c],
                      _clone && hasNew,
                    ),
                  ),
          child: Text(tr(context, '저장', 'Save')),
        ),
      ],
    );
  }
}
