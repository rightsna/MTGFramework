import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_locale.dart';
import '../../models/store_device.dart';
import '../../models/store_locale.dart';
import 'screenshot_thumb.dart';

/// A single, hover-aware project card: app icon preview (left) + screenshot
/// strip (right), a "fastlane 배포" button, and an overflow menu (reveal in
/// Finder). Screenshots show as a device/graphic tab picking one language row.
class ProjectCard extends StatefulWidget {
  const ProjectCard({
    super.key,
    required this.name,
    required this.appIcon,
    required this.featureGraphicByLocale,
    required this.locales,
    required this.shotsByDeviceLocale,
    required this.enabled,
    required this.onOpenIcon,
    required this.onOpenGraphic,
    required this.onNewScreenshot,
    required this.onOpenScreenshot,
    required this.onDeleteScreenshot,
    required this.onManageLanguages,
    required this.onDeploy,
    required this.onReveal,
  });

  final String name;
  final File? appIcon;

  /// locale code → feature graphic file (or null).
  final Map<String, File?> featureGraphicByLocale;
  final List<String> locales;

  /// device code → locale code → preview files.
  final Map<String, Map<String, List<File>>> shotsByDeviceLocale;

  final bool enabled;
  final VoidCallback onOpenIcon;
  final void Function(String locale) onOpenGraphic;
  final void Function(String device, String locale) onNewScreenshot;
  final void Function(String device, String locale, File preview)
      onOpenScreenshot;
  final void Function(File preview) onDeleteScreenshot;
  final VoidCallback onManageLanguages;
  final VoidCallback onDeploy;
  final VoidCallback onReveal;

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _hover = false;

  /// Tab view tab — a device code or [_graphicTab] (null → first device).
  static const _graphicTab = 'graphic';
  String? _selectedTab;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hover
                ? cs.primary.withValues(alpha: 0.55)
                : cs.outlineVariant.withValues(alpha: 0.35),
          ),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.16),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.name,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, '언어 관리', 'Manage languages'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.translate,
                        size: 18, color: cs.onSurfaceVariant),
                    onPressed: widget.enabled ? widget.onManageLanguages : null,
                  ),
                  FilledButton.icon(
                    onPressed: widget.enabled ? widget.onDeploy : null,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.rocket_launch_outlined, size: 16),
                    label: Text(tr(context, 'fastlane 배포', 'Deploy')),
                  ),
                  PopupMenuButton<String>(
                    tooltip: tr(context, '더보기', 'More'),
                    enabled: widget.enabled,
                    icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
                    onSelected: (v) {
                      if (v == 'finder') widget.onReveal();
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'finder',
                        child: Row(children: [
                          const Icon(Icons.folder_open_outlined, size: 18),
                          const SizedBox(width: 10),
                          Text(tr(ctx, '게임 폴더 열기', 'Reveal game folder')),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _iconZone(cs, text),
                  const SizedBox(width: 12),
                  Expanded(child: _assetTabs(cs, text)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconZone(ColorScheme cs, TextTheme text) {
    final f = widget.appIcon;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tr(context, '앱 아이콘 편집', 'Edit app icon'),
        child: InkWell(
          onTap: widget.enabled ? widget.onOpenIcon : null,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: f == null
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                cs.surfaceContainerHighest,
                                cs.surfaceContainer,
                              ],
                            )
                          : null,
                      color: f == null ? null : const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: f == null
                        ? Icon(Icons.apps_rounded,
                            size: 30,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6))
                        : Image.file(
                            f,
                            fit: BoxFit.cover,
                            cacheWidth: 168,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                          ),
                  ),
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: _hover ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Icon(Icons.edit_outlined,
                              color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(tr(context, '앱 아이콘', 'App Icon'),
                  style: text.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _graphicThumb(ColorScheme cs, String locale, String label, File? f) {
    // 84 wide at the 1024:500 ratio ≈ 41 tall.
    const w = 84.0;
    const h = w * 500 / 1024;
    return Tooltip(
      message: '$label · ${tr(context, '그래픽 1024×500', 'Graphic 1024×500')}',
      child: InkWell(
        onTap: widget.enabled ? () => widget.onOpenGraphic(locale) : null,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(locale,
                style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            Stack(
              children: [
                Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    gradient: f == null
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              cs.surfaceContainerHighest,
                              cs.surfaceContainer,
                            ],
                          )
                        : null,
                    color: f == null ? null : const Color(0xFF000000),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: f == null
                      ? Icon(Icons.wallpaper_outlined,
                          size: 18,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6))
                      : Image.file(
                          f,
                          fit: BoxFit.cover,
                          cacheWidth: 168,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.broken_image_outlined,
                            size: 14,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                ),
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _hover ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(Icons.edit_outlined,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Default tab: the first tab (devices, then graphic) that has
  /// saved content, so an empty mobile tab doesn't hide a project that only has
  /// desktop shots. Falls back to the first device when everything is empty.
  String _defaultTab() {
    for (final d in kStoreDevices) {
      final byLocale = widget.shotsByDeviceLocale[d.code];
      if (byLocale != null && byLocale.values.any((l) => l.isNotEmpty)) {
        return d.code;
      }
    }
    if (widget.featureGraphicByLocale.values.any((f) => f != null)) {
      return _graphicTab;
    }
    return kStoreDevices.first.code;
  }

  Widget _assetTabs(ColorScheme cs, TextTheme text) {
    final english = AppLocale.of(context).english;
    const localeColW = 64.0;
    final tabCodes = [for (final d in kStoreDevices) d.code, _graphicTab];
    final sel =
        tabCodes.contains(_selectedTab) ? _selectedTab! : _defaultTab();
    final isGraphic = sel == _graphicTab;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 탭: 모바일 | 패드 | 데스크탑 | 그래픽
        SegmentedButton<String>(
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: [
            for (final d in kStoreDevices)
              ButtonSegment(
                value: d.code,
                label: Text(storeDeviceLabel(d.code, english: english),
                    style: const TextStyle(fontSize: 12)),
              ),
            ButtonSegment(
              value: _graphicTab,
              label: Text(tr(context, '그래픽', 'Graphic'),
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
          selected: {sel},
          onSelectionChanged: widget.enabled
              ? (s) => setState(() => _selectedTab = s.first)
              : null,
        ),
        const SizedBox(height: 10),
        // 선택한 탭의 내용 — 언어별 행
        for (final code in widget.locales)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: localeColW,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: Text(storeLocaleLabel(code, english: english),
                        style: text.labelMedium),
                  ),
                ),
                Expanded(
                  child: isGraphic
                      ? _graphicCell(cs, text, code)
                      : _deviceCell(cs, text, sel, code),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// One (device, locale) cell: its screenshots wrap to new rows when they
  /// overflow the column width; the add tile is always last.
  Widget _deviceCell(
      ColorScheme cs, TextTheme text, String device, String locale) {
    final byLocale =
        widget.shotsByDeviceLocale[device] ?? const <String, List<File>>{};
    final shots = byLocale[locale] ?? const <File>[];
    // 가로형 기기(데스크탑 등)는 정사각 썸네일.
    final dev = storeDeviceByCode(device);
    final landscape = dev != null && dev.exportW > dev.exportH;
    final thumbW = landscape ? 84.0 : 50.0;
    final addW = landscape ? 84.0 : 56.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final f in shots)
            ScreenshotThumb(
              preview: f,
              width: thumbW,
              enabled: widget.enabled,
              onOpen: () => widget.onOpenScreenshot(device, locale, f),
              onDelete: () => widget.onDeleteScreenshot(f),
            ),
          _addTile(cs, text, device, locale, addW),
        ],
      ),
    );
  }

  /// One (graphic, locale) cell: the 1024×500 feature graphic for the language.
  Widget _graphicCell(ColorScheme cs, TextTheme text, String locale) {
    final english = AppLocale.of(context).english;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Align(
        alignment: Alignment.topLeft,
        child: _graphicThumb(cs, locale,
            storeLocaleLabel(locale, english: english),
            widget.featureGraphicByLocale[locale]),
      ),
    );
  }

  Widget _addTile(ColorScheme cs, TextTheme text, String device, String locale,
      double width) {
    return _tile(
      text,
      width: width,
      icon: Icons.add,
      label: tr(context, '추가', 'Add'),
      tooltip: tr(context, '새 스샷', 'New screenshot'),
      color: cs.onSurfaceVariant,
      border: cs.outlineVariant.withValues(alpha: 0.6),
      onTap: widget.enabled ? () => widget.onNewScreenshot(device, locale) : null,
    );
  }

  /// 추가 타일. [color]는 아이콘/텍스트, [border]는 테두리, [fill]은
  /// (있으면) 배경 채움.
  Widget _tile(
    TextTheme text, {
    required double width,
    required IconData icon,
    required String label,
    required String tooltip,
    required Color color,
    required Color border,
    Color? fill,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: width,
          height: 84,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(label, style: text.labelSmall?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
