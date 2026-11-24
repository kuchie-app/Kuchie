import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../widgets/app_bottom_sheet.dart';
import '../../../../../../widgets/popup_widgets/app_dialog.dart';
import '../../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../../settings/presentation/reader/widgets/reader_navigation_layout_tile/reader_navigation_layout_tile.dart';
import '../../../../../settings/presentation/reader/widgets/reader_padding_slider/reader_padding_slider.dart';
import '../../../../../settings/presentation/reader/widgets/reader_tap_invert/reader_tap_invert.dart';
import '../../controller/auto_scroll_controller.dart';
import '../../controller/auto_webtoon.dart';
import '../../controller/reader_settings_model.dart';
import '../../utils/reader_mode_kind.dart';
import 'reader_settings_dialog.dart';
import 'tabs/reading_mode_tab.dart';

/// The reader's settings, kept short like Tachimanga: reading mode,
/// rotation, tap zones, background, side padding, crop borders and auto
/// scroll, with every other option one tap away under Advanced. Server and
/// on-device series open the same sheet; [localSeriesId] picks the storage.
Future<void> showReaderQuickSettings({
  required BuildContext context,
  required WidgetRef ref,
  required int mangaId,
  String? localSeriesId,
  ReaderFormatMetadata? localFormat,
  required ValueNotifier<bool> visibility,
  required ValueNotifier<double> readerPadding,
}) => showAppBottomSheet<void>(
  context: context,
  builder: (sheet) => _ReaderQuickSettings(
    mangaId: mangaId,
    localSeriesId: localSeriesId,
    localFormat: localFormat,
    readerPadding: readerPadding,
    onAdvanced: () {
      Navigator.pop(sheet);
      unawaited(
        showReaderSettingsSheet(
          context: context,
          ref: ref,
          mangaId: mangaId,
          localSeriesId: localSeriesId,
          localFormat: localFormat,
          visibility: visibility,
          readerPadding: readerPadding,
        ),
      );
    },
  ),
);

class _ReaderQuickSettings extends ConsumerWidget {
  const _ReaderQuickSettings({
    required this.mangaId,
    required this.localSeriesId,
    required this.localFormat,
    required this.readerPadding,
    required this.onAdvanced,
  });

  final int mangaId;
  final String? localSeriesId;
  final ReaderFormatMetadata? localFormat;
  final ValueNotifier<double> readerPadding;
  final VoidCallback onAdvanced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = readerSettingsModelProvider(
      mangaId,
      localSeriesId: localSeriesId,
    );
    final settings = ref.watch(provider);
    final model = ref.read(provider.notifier);
    final paged = isPagedReaderMode(settings.readerMode);
    final cropBorders = paged
        ? settings.cropBorders
        : settings.cropBordersWebtoon;
    final autoScroll = ref.watch(autoScrollActiveProvider);
    final l10n = context.l10n;
    // Tap zones are saved per viewer, so edit the one this series shows.
    final longStripViewer = !isPagedReaderMode(
      sessionReaderMode(
        ref,
        settings: settings,
        mangaId: mangaId,
        localSeriesId: localSeriesId,
        localFormat: localFormat,
      ),
    );
    final tapZones =
        (longStripViewer
            ? ref.watch(longStripNavigationLayoutKeyProvider)
            : ref.watch(pagedNavigationLayoutKeyProvider)) ??
        ReaderNavigationLayout.disabled;

    Future<void> pick<T>({
      required String title,
      required List<T> options,
      required T value,
      required String Function(T) label,
      required ValueChanged<T> onChanged,
    }) => showAppDialog<void>(
      context: context,
      builder: (dialog) => RadioListPopup<T>(
        title: title,
        optionList: options,
        value: value,
        getOptionTitle: label,
        onChange: (next) {
          Navigator.pop(dialog);
          onChanged(next);
        },
      ),
    );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(FluentIcons.phone_24_regular),
              title: Text(l10n.readerMode),
              subtitle: Text(settings.readerMode.toLocale(context)),
              onTap: () => pick<ReaderMode>(
                title: l10n.readerMode,
                options: ReaderMode.displayOrder,
                value: settings.readerMode,
                label: (mode) => mode.toLocale(context),
                onChanged: (mode) => unawaited(model.setReaderMode(mode)),
              ),
            ),
            ListTile(
              leading: const Icon(FluentIcons.phone_update_24_regular),
              title: Text(l10n.readerSectionRotation),
              subtitle: Text(settings.readerOrientation.toLocale(context)),
              onTap: () => pick<ReaderOrientation>(
                title: l10n.readerSectionRotation,
                options: ReaderOrientation.values,
                value: settings.readerOrientation,
                label: (orientation) => orientation.toLocale(context),
                onChanged: model.setReaderOrientation,
              ),
            ),
            ListTile(
              leading: const Icon(FluentIcons.tap_single_24_regular),
              title: Text(l10n.readerNavigationLayout),
              subtitle: Text(tapZones.toLocale(context)),
              onTap: () => showAppBottomSheet<void>(
                context: context,
                builder: (_) => _TapZonesSheet(
                  provider: provider,
                  longStrip: longStripViewer,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(FluentIcons.dark_theme_24_regular),
              title: Text(l10n.readerBackgroundColor),
              subtitle: Text(settings.backgroundColor.toLocale(context)),
              onTap: () => pick<ReaderBackgroundColor>(
                title: l10n.readerBackgroundColor,
                options: ReaderBackgroundColor.values,
                value: settings.backgroundColor,
                label: (color) => color.toLocale(context),
                onChanged: model.setBackgroundColor,
              ),
            ),
            AsyncReaderPaddingSlider(
              readerPadding: readerPadding,
              onChanged: (value) => model.setSidePadding(value),
            ),
            SwitchListTile(
              secondary: const Icon(FluentIcons.crop_24_regular),
              title: Text(l10n.cropBorders),
              value: cropBorders,
              onChanged: paged
                  ? model.setCropBorders
                  : model.setCropBordersWebtoon,
            ),
            SwitchListTile(
              secondary: const Icon(FluentIcons.play_circle_24_regular),
              title: Text(paged ? l10n.autoAdvance : l10n.autoScroll),
              value: autoScroll,
              onChanged: (_) =>
                  ref.read(autoScrollActiveProvider.notifier).toggle(),
            ),
            ListTile(
              leading: const Icon(FluentIcons.code_24_regular),
              title: Text(l10n.advanced),
              trailing: const Icon(FluentIcons.chevron_right_24_regular),
              onTap: onAdvanced,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tap zones as pictures, like Tachimanga, plus invert and page animation.
class _TapZonesSheet extends ConsumerWidget {
  const _TapZonesSheet({required this.provider, required this.longStrip});

  final ReaderSettingsModelProvider provider;

  /// Which viewer's app-wide tap zones this sheet edits.
  final bool longStrip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(provider);
    final model = ref.read(provider.notifier);
    final layoutNow =
        (longStrip
            ? ref.watch(longStripNavigationLayoutKeyProvider)
            : ref.watch(pagedNavigationLayoutKeyProvider)) ??
        ReaderNavigationLayout.disabled;
    final invertNow =
        (longStrip
            ? ref.watch(longStripTapInvertKeyProvider)
            : ref.watch(pagedTapInvertKeyProvider)) ??
        TapInvert.none;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSheetHeader(title: context.l10n.readerNavigationLayout),
          SizedBox(
            height: 196,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final layout in ReaderNavigationLayout.displayOrder)
                  _TapZoneCard(
                    layout: layout,
                    selected: layoutNow == layout,
                    onTap: () =>
                        model.setNavigationLayout(layout, longStrip: longStrip),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(FluentIcons.arrow_swap_24_regular),
            title: Text(context.l10n.readerSectionTapInvert),
            value: invertNow != TapInvert.none,
            onChanged: (on) => model.setTapInvert(
              on ? TapInvert.both : TapInvert.none,
              longStrip: longStrip,
            ),
          ),
          SwitchListTile(
            secondary: const Icon(FluentIcons.slide_transition_24_regular),
            title: Text(context.l10n.animatePageTransitions),
            value: settings.animatePageTransitions,
            onChanged: model.setAnimatePageTransitions,
          ),
        ],
      ),
    );
  }
}

class _TapZoneCard extends StatelessWidget {
  const _TapZoneCard({
    required this.layout,
    required this.selected,
    required this.onTap,
  });

  final ReaderNavigationLayout layout;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: CustomPaint(
                      painter: _TapZonePainter(
                        layout: layout,
                        outline: cs.outline,
                        next: cs.primary.withValues(alpha: .7),
                        previous: cs.tertiary.withValues(alpha: .7),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: selected ? cs.primary : cs.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      layout.toLocale(context),
                      style: context.textTheme.labelMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A phone outline with the layout's previous (blue) and next (green) zones.
class _TapZonePainter extends CustomPainter {
  _TapZonePainter({
    required this.layout,
    required this.outline,
    required this.next,
    required this.previous,
  });

  final ReaderNavigationLayout layout;
  final Color outline;
  final Color next;
  final Color previous;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.save();
    canvas.clipRRect(frame);
    final w = size.width, h = size.height;
    final nextPaint = Paint()..color = next;
    final prevPaint = Paint()..color = previous;
    void zone(Paint paint, double l, double t, double r, double b) =>
        canvas.drawRect(Rect.fromLTRB(l * w, t * h, r * w, b * h), paint);
    switch (layout) {
      case ReaderNavigationLayout.lShaped:
        zone(prevPaint, 0, 0, 1 / 3, 2 / 3);
        zone(prevPaint, 1 / 3, 0, 1, 1 / 3);
        zone(nextPaint, 2 / 3, 1 / 3, 1, 1);
        zone(nextPaint, 0, 2 / 3, 2 / 3, 1);
      case ReaderNavigationLayout.kindlish:
        zone(prevPaint, 0, 1 / 3, 1 / 3, 1);
        zone(nextPaint, 1 / 3, 1 / 3, 1, 1);
      case ReaderNavigationLayout.edge:
        zone(nextPaint, 0, 0, 1 / 3, 1);
        zone(nextPaint, 2 / 3, 0, 1, 1);
        zone(prevPaint, 1 / 3, 2 / 3, 2 / 3, 1);
      case ReaderNavigationLayout.rightAndLeft:
        zone(prevPaint, 0, 0, 1 / 3, 1);
        zone(nextPaint, 2 / 3, 0, 1, 1);
      case ReaderNavigationLayout.defaultNavigation:
      case ReaderNavigationLayout.disabled:
        canvas.drawLine(
          Offset(w * .2, h * .2),
          Offset(w * .8, h * .8),
          Paint()
            ..color = outline
            ..strokeWidth = 2,
        );
    }
    canvas.restore();
    canvas.drawRRect(
      frame,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_TapZonePainter old) =>
      old.layout != layout || old.outline != outline;
}
