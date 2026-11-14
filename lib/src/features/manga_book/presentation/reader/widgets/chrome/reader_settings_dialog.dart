// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_hooks/flutter_hooks.dart' hide useTabController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_hooks/material_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/app_bottom_sheet.dart';
import '../../../../../../widgets/ios/apple_glass_segments.dart';
import '../../../../../../widgets/touch_tab_pager.dart';
import '../../controller/auto_webtoon.dart';
import '../../controller/reader_preview_channel.dart';
import '../../controller/reader_settings_model.dart';
import 'tabs/custom_filter_tab.dart';
import 'tabs/general_tab.dart';
import 'tabs/reading_mode_tab.dart';

part 'reader_settings_dialog.g.dart';

typedef ReaderSettingsPreviewState = ({Color scrim, bool chromeHidden});

/// Live-preview state driven by the sheet's tab: the Custom-filter tab clears
/// the scrim and hides the chrome so the page shows.
@riverpod
class ReaderSettingsPreview extends _$ReaderSettingsPreview {
  static const ReaderSettingsPreviewState _shown = (
    scrim: Colors.black54,
    chromeHidden: false,
  );
  static const ReaderSettingsPreviewState _pageVisible = (
    scrim: Colors.transparent,
    chromeHidden: true,
  );

  @override
  ReaderSettingsPreviewState build() => _shown;

  void onTabChanged(int index) => state = index == 2 ? _pageVisible : _shown;
}

/// Keep the modal barrier blocking gestures even when its colour is transparent.
class _ReaderSettingsSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _ReaderSettingsSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    super.sheetAnimationStyle,
  }) : super(
         isScrollControlled: true,
         useSafeArea: true,
         backgroundColor: Colors.transparent,
         elevation: 0,
         showDragHandle: false,
       );

  Color _barrierColor = Colors.black54;

  @override
  Color get barrierColor => _barrierColor;

  set barrierColor(Color value) {
    if (value == _barrierColor) return;
    _barrierColor = value;
    changedInternalState();
  }
}

/// Restore preview state once on every dismiss path through Future.whenComplete.
Future<void> showReaderSettingsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required int mangaId,
  String? localSeriesId,
  ReaderFormatMetadata? localFormat,
  required ValueNotifier<bool> visibility,
  required ValueNotifier<double> readerPadding,
}) {
  final navigator = Navigator.of(context);
  final route = _ReaderSettingsSheetRoute<void>(
    barrierLabel: MaterialLocalizations.of(context).scrimLabel,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    sheetAnimationStyle: context.motionStyle,
    builder: (_) => ReaderSettingsDialog(
      mangaId: mangaId,
      localSeriesId: localSeriesId,
      localFormat: localFormat,
      readerPadding: readerPadding,
    ),
  );

  final wasVisible = visibility.value;
  final subscription = ref.listenManual(readerSettingsPreviewProvider, (
    _,
    next,
  ) {
    route.barrierColor = next.scrim;
    visibility.value = next.chromeHidden ? false : wasVisible;
  });

  var dismissed = false;
  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    subscription.close();
    // Clear global drafts even after disposal so the next reader cannot inherit them.
    final brightnessDraft = readerBrightnessPreview.value;
    final colorDraft = readerColorFilterPreview.value;
    readerBrightnessPreview.value = null;
    readerColorFilterPreview.value = null;
    // Reader gone (e.g. volume-key chapter change) → ref is dead.
    if (!context.mounted) return;
    // Commit any slider draft interrupted by sheet dismissal.
    final model = ref.read(
      readerSettingsModelProvider(
        mangaId,
        localSeriesId: localSeriesId,
      ).notifier,
    );
    if (brightnessDraft != null) {
      model.setCustomBrightnessValue(brightnessDraft);
    }
    if (colorDraft != null) model.setColorFilterValue(colorDraft);
    visibility.value = wasVisible;
    ref.invalidate(readerSettingsPreviewProvider);
  }

  return navigator.push(route).whenComplete(dismiss);
}

class ReaderSettingsDialog extends HookConsumerWidget {
  const ReaderSettingsDialog({
    super.key,
    required this.mangaId,
    this.localSeriesId,
    this.localFormat,
    required this.readerPadding,
  });

  final int mangaId;
  final String? localSeriesId;
  final ReaderFormatMetadata? localFormat;

  /// Share the live padding notifier so slider changes update the open reader.
  final ValueNotifier<double> readerPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabController = useTabController(initialLength: 3);
    useEffect(() {
      void onTab() => ref
          .read(readerSettingsPreviewProvider.notifier)
          .onTabChanged(tabController.index);
      tabController.addListener(onTab);
      return () => tabController.removeListener(onTab);
    }, [tabController]);

    final labels = [
      context.l10n.readerMode,
      context.l10n.general,
      context.l10n.customFilter,
    ];
    final tabs = TabBar(
      controller: tabController,
      tabAlignment: TabAlignment.start,
      isScrollable: true,
      tabs: [for (final label in labels) Tab(text: label)],
    );

    return FractionallySizedBox(
      heightFactor: context.isLandscape ? 0.88 : 0.7,
      child: AppSheetSurface(
        child: Column(
          children: [
            AppSheetHeader(title: context.l10n.migrateReaderSettings),
            AnimatedBuilder(
              animation: tabController,
              builder: (context, _) => AppleGlassSegments(
                labels: labels,
                selectedIndex: tabController.index,
                onSelected: tabController.animateTo,
                fallback: tabs,
                scrollable: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TouchTabPager(
                controller: tabController,
                children: [
                  ReadingModeTab(
                    mangaId: mangaId,
                    localSeriesId: localSeriesId,
                    localFormat: localFormat,
                    readerPadding: readerPadding,
                  ),
                  GeneralTab(mangaId: mangaId, localSeriesId: localSeriesId),
                  CustomFilterTab(
                    mangaId: mangaId,
                    localSeriesId: localSeriesId,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
