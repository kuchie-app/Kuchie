// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../constants/app_sizes.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../routes/router_config.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../utils/theme/brand.dart';
import '../../../../../../utils/theme/reader_overlay_colors.dart';
import '../../../../../../widgets/app_bottom_sheet.dart';
import '../../../../../../widgets/ios/apple_glass_capability.dart';
import '../../../../../../widgets/ios/apple_glass_surface.dart';
import '../../../../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../../../settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import '../../../../../settings/presentation/reader/widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../widgets/download_status_icon.dart';
import '../../../manga_details/controller/manga_details_controller.dart';
import '../../../manga_details/controller/scanlator_dedup.dart';
import '../../controller/reader_settings_model.dart';
import '../../utils/reader_mode_kind.dart';
import '../brand_page_seekbar.dart';
import '../reader_mode/infinity_continuous/measure_size.dart';
import 'apple_glass_reader_slider.dart';
import 'chapter_nav_buttons.dart';
import 'chrome_extents.dart';
import 'reader_bookmark_button.dart';

class ReaderBottomControls extends ConsumerWidget {
  const ReaderBottomControls({
    super.key,
    required this.chapter,
    required this.chapterPages,
    required this.readerScanlatorGroup,
    required this.currentIndex,
    required this.totalPageCount,
    required this.useBottomSeekBar,
    required this.scrollDirection,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.resolvedReaderMode,
    required this.reverseSeekBar,
    required this.onChanged,
    required this.onOpenSettings,
    required this.onOpenReaderMode,
    this.floating = false,
  });

  final ChapterDto chapter;
  final ChapterPagesDto chapterPages;
  final String readerScanlatorGroup;
  final int currentIndex;

  /// For infinity-scroll mode; null means use [chapterPages.chapter.pageCount].
  final int? totalPageCount;

  final bool useBottomSeekBar;
  final Axis scrollDirection;

  /// Null when there is no chapter that way; the button renders disabled.
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  final ReaderMode resolvedReaderMode;
  final bool reverseSeekBar;

  final ValueChanged<int> onChanged;

  final VoidCallback onOpenSettings;

  final VoidCallback onOpenReaderMode;
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ReaderBottomControlsView(
    settingsMangaId: chapter.mangaId,
    currentIndex: currentIndex,
    pageCount: totalPageCount ?? chapterPages.chapter.pageCount,
    useBottomSeekBar: useBottomSeekBar,
    scrollDirection: scrollDirection,
    onPreviousChapter: onPreviousChapter,
    onNextChapter: onNextChapter,
    resolvedReaderMode: resolvedReaderMode,
    reverseSeekBar: reverseSeekBar,
    onChanged: onChanged,
    onOpenSettings: onOpenSettings,
    onOpenReaderMode: onOpenReaderMode,
    onOpenChapters: () => showReaderChapterPicker(
      context: context,
      mangaId: chapter.mangaId,
      currentChapterId: chapter.id,
      readerScanlatorGroup: readerScanlatorGroup,
      transVertical: scrollDirection == Axis.vertical,
    ),
    bookmark: ReaderBookmarkButton(
      chapterId: chapter.id,
      fallbackIsBookmarked: chapter.user.isBookmarked,
      dark: true,
    ),
    floating: floating,
  );
}

/// The reader's bottom dock for every collection: chapter buttons, seek bar,
/// bookmark and the quick actions (chapters, mode, crop, page layout, offset,
/// settings). Settings resolve through [readerSettingsModelProvider], so the
/// server and the Local reader read and write the same keys.
class ReaderBottomControlsView extends ConsumerWidget {
  const ReaderBottomControlsView({
    super.key,
    required this.settingsMangaId,
    this.localSeriesId,
    required this.currentIndex,
    required this.pageCount,
    required this.useBottomSeekBar,
    required this.scrollDirection,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.resolvedReaderMode,
    required this.reverseSeekBar,
    required this.onChanged,
    required this.onOpenSettings,
    required this.onOpenReaderMode,
    required this.onOpenChapters,
    required this.bookmark,
    this.floating = false,
  });

  /// Server manga id, or 0 with [localSeriesId] for an on-device series.
  final int settingsMangaId;
  final String? localSeriesId;
  final int currentIndex;
  final int pageCount;
  final bool useBottomSeekBar;
  final Axis scrollDirection;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final ReaderMode resolvedReaderMode;
  final bool reverseSeekBar;
  final ValueChanged<int> onChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenReaderMode;
  final VoidCallback onOpenChapters;
  final Widget bookmark;
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPagedMode = isPagedReaderMode(resolvedReaderMode);
    final pageLayout = ref.watch(pageLayoutKeyProvider) ?? PageLayout.automatic;
    final dualPageSplitPaged = ref.watch(dualPageSplitPagedProvider).ifNull();
    final settingsProvider = readerSettingsModelProvider(
      settingsMangaId,
      localSeriesId: localSeriesId,
    );
    final settingsModel = ref.watch(settingsProvider);
    final offsetDoublePages = settingsModel.offsetDoublePages;
    final cropBorders = isPagedMode
        ? ref.watch(cropBordersProvider).ifNull()
        : ref.watch(cropBordersWebtoonProvider).ifNull();

    void toggleCropBorders() {
      if (isPagedMode) {
        ref.read(cropBordersProvider.notifier).update(!cropBorders);
      } else {
        ref.read(cropBordersWebtoonProvider.notifier).update(!cropBorders);
      }
    }

    void togglePageLayout() {
      final next = pageLayout == PageLayout.doublePages
          ? PageLayout.singlePage
          : PageLayout.doublePages;
      ref.read(pageLayoutKeyProvider.notifier).update(next);
    }

    final isLandscape = context.width > context.height;
    final wantDouble = pageLayout.showsDoublePages(
      horizontal: scrollDirection == Axis.horizontal,
      landscape: isLandscape,
      trueDualPageSpread: settingsModel.trueDualPageSpread,
    );
    final l10n = context.l10n;
    final actions = [
      AppleGlassToolbarAction(
        id: 'reader-chapters',
        symbol: 'list.number',
        label: l10n.includeChapters,
        fallbackIcon: FluentIcons.text_number_list_ltr_24_regular,
        onPressed: onOpenChapters,
      ),
      AppleGlassToolbarAction(
        id: 'reader-mode',
        symbol: switch (resolvedReaderMode) {
          ReaderMode.webtoon || ReaderMode.continuousVertical => 'globe',
          _ => 'book',
        },
        label: l10n.readerMode,
        fallbackIcon: _readerModeIcon(resolvedReaderMode),
        onPressed: onOpenReaderMode,
      ),
      AppleGlassToolbarAction(
        id: 'reader-crop',
        symbol: cropBorders ? 'crop' : 'arrow.up.left.and.arrow.down.right',
        label: l10n.cropBorders,
        fallbackIcon: cropBorders
            ? FluentIcons.crop_24_regular
            : FluentIcons.full_screen_maximize_24_regular,
        onPressed: toggleCropBorders,
      ),
      if (isPagedMode && !dualPageSplitPaged)
        AppleGlassToolbarAction(
          id: 'reader-page-layout',
          symbol: switch (pageLayout) {
            PageLayout.singlePage => 'doc',
            PageLayout.doublePages => 'book',
            PageLayout.automatic => 'rectangle.expand.vertical',
          },
          label: l10n.pageLayout,
          fallbackIcon: _pageLayoutIcon(pageLayout),
          onPressed: togglePageLayout,
        ),
      if (isPagedMode && wantDouble && !dualPageSplitPaged)
        AppleGlassToolbarAction(
          id: 'reader-offset-pages',
          symbol: 'arrow.left.arrow.right',
          label: l10n.offsetDoublePages,
          color: offsetDoublePages ? context.theme.colorScheme.primary : null,
          fallbackIcon: offsetDoublePages
              ? FluentIcons.arrow_swap_24_filled
              : FluentIcons.arrow_swap_24_regular,
          onPressed: () => ref
              .read(settingsProvider.notifier)
              .setOffsetDoublePages(!offsetDoublePages),
        ),
      AppleGlassToolbarAction(
        id: 'reader-settings',
        symbol: 'gearshape',
        label: l10n.settings,
        fallbackIcon: FluentIcons.settings_24_regular,
        onPressed: onOpenSettings,
      ),
    ];

    return ReaderBottomDock(
      currentIndex: currentIndex,
      pageCount: pageCount,
      useBottomSeekBar: useBottomSeekBar,
      floating: floating,
      resolvedReaderMode: resolvedReaderMode,
      reverseSeekBar: reverseSeekBar,
      onChanged: onChanged,
      onNextChapter: onNextChapter,
      onPreviousChapter: onPreviousChapter,
      onOpenSettings: onOpenSettings,
      bookmark: bookmark,
      actions: actions,
    );
  }
}

class ReaderBottomDock extends ConsumerWidget {
  const ReaderBottomDock({
    super.key,
    required this.currentIndex,
    required this.pageCount,
    required this.useBottomSeekBar,
    required this.floating,
    required this.resolvedReaderMode,
    required this.reverseSeekBar,
    required this.onChanged,
    required this.onNextChapter,
    required this.onPreviousChapter,
    required this.onOpenSettings,
    required this.bookmark,
    required this.actions,
  });

  final int currentIndex;
  final int pageCount;
  final bool useBottomSeekBar;
  final bool floating;
  final ReaderMode resolvedReaderMode;
  final bool reverseSeekBar;
  final ValueChanged<int> onChanged;
  final VoidCallback? onNextChapter;
  final VoidCallback? onPreviousChapter;
  final VoidCallback onOpenSettings;
  final Widget bookmark;
  final List<AppleGlassToolbarAction> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemBottomInset = MediaQuery.viewPaddingOf(context).bottom;
    // The chapter buttons follow the seek bar: previous on the side where
    // the bar starts.
    final isRtl = reverseSeekBar;
    final l10n = context.l10n;
    final navSurface = readerNavSurface(context.theme.colorScheme);
    final chapterButtons = chapterNavCallbacks(
      isRtl: isRtl,
      onPreviousChapter: onPreviousChapter,
      onNextChapter: onNextChapter,
    );
    final chapterSeek = Row(
      textDirection: floating ? TextDirection.ltr : null,
      children: [
        AppleGlassToolbarButton(
          id: 'reader-chapter-leading',
          symbol: floating ? 'chevron.left' : 'backward.end.fill',
          label: isRtl
              ? l10n.hotkeyReaderNextChapter
              : l10n.hotkeyReaderPrevChapter,
          onPressed: chapterButtons.leading,
          dark: floating ? true : null,
          fallback: Card(
            shape: const CircleBorder(),
            elevation: 0,
            color: navSurface,
            child: IconButton(
              onPressed: chapterButtons.leading,
              icon: const Icon(FluentIcons.previous_24_filled),
            ),
          ),
        ),
        Expanded(
          child: floating
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AppleGlassReaderSlider(
                    currentIndex: currentIndex,
                    pageCount: pageCount,
                    reversed: reverseSeekBar,
                    onChanged: onChanged,
                    fallback: _FloatingPageSeekBar(
                      currentIndex: currentIndex,
                      pageCount: pageCount,
                      reversed: reverseSeekBar,
                      onChanged: onChanged,
                    ),
                  ),
                )
              : BrandPageSeekBar(
                  currentValue: currentIndex,
                  maxValue: pageCount,
                  onChanged: onChanged,
                  inverted: reverseSeekBar,
                  capsuleColor: navSurface,
                ),
        ),
        AppleGlassToolbarButton(
          id: 'reader-chapter-trailing',
          symbol: floating ? 'chevron.right' : 'forward.end.fill',
          label: isRtl
              ? l10n.hotkeyReaderPrevChapter
              : l10n.hotkeyReaderNextChapter,
          onPressed: chapterButtons.trailing,
          dark: floating ? true : null,
          fallback: Card(
            shape: const CircleBorder(),
            elevation: 0,
            color: navSurface,
            child: IconButton(
              onPressed: chapterButtons.trailing,
              icon: const Icon(FluentIcons.next_24_filled),
            ),
          ),
        ),
      ],
    );

    return MeasureSize(
      onChange: (size) {
        if (!context.mounted) return;
        final current = ref.read(chromeExtentsProvider);
        final next = ChromeExtents(
          topInset: current.topInset,
          bottomInset: size.height,
        );
        ref.read(chromeExtentsProvider.notifier).update(next);
      },
      child: ExcludeFocus(
        child: floating
            ? Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, systemBottomInset + 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        bookmark,
                        AppleGlassToolbarButton(
                          id: 'reader-settings',
                          symbol: 'gearshape',
                          label: l10n.settings,
                          fallbackIcon: FluentIcons.settings_24_regular,
                          onPressed: onOpenSettings,
                          dark: true,
                        ),
                      ],
                    ),
                    if (useBottomSeekBar) ...[const Gap(6), chapterSeek],
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (useBottomSeekBar) ...[chapterSeek, const Gap(8)],
                  Card(
                    color: navSurface,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding:
                          KEdgeInsets.h16.size +
                          EdgeInsets.only(bottom: systemBottomInset),
                      child: Center(
                        child: AppleGlassToolbar(
                          actions: actions,
                          fallback: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (final action in actions)
                                IconButton(
                                  icon: Icon(action.fallbackIcon),
                                  tooltip: action.label,
                                  onPressed: action.onPressed,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _FloatingPageSeekBar extends StatelessWidget {
  const _FloatingPageSeekBar({
    required this.currentIndex,
    required this.pageCount,
    required this.reversed,
    required this.onChanged,
  });

  final int currentIndex;
  final int pageCount;
  final bool reversed;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (pageCount < 1) return const SizedBox.shrink();
    final lastIndex = pageCount - 1;
    final current = currentIndex.clamp(0, lastIndex);
    final position = reversed ? lastIndex - current : current;
    const numberStyle = TextStyle(
      color: OnImage.text,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: ReaderOverlayColors.seekBarSurface,
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              Text('${reversed ? pageCount : current + 1}', style: numberStyle),
              Expanded(
                child: Semantics(
                  label: context.l10n.page(current + 1),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: CupertinoSlider(
                      value: position.toDouble(),
                      max: (lastIndex > 0 ? lastIndex : 1).toDouble(),
                      activeColor: ReaderOverlayColors.seekBarAccent,
                      onChanged: lastIndex == 0
                          ? null
                          : (value) {
                              final index = value.round();
                              onChanged(reversed ? lastIndex - index : index);
                            },
                    ),
                  ),
                ),
              ),
              Text('${reversed ? current + 1 : pageCount}', style: numberStyle),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _readerModeIcon(ReaderMode mode) => switch (mode) {
  ReaderMode.webtoon ||
  ReaderMode.continuousVertical => FluentIcons.globe_24_regular,
  ReaderMode.singleHorizontalLTR ||
  ReaderMode.singleHorizontalRTL ||
  ReaderMode.singleVertical ||
  ReaderMode.continuousHorizontalLTR ||
  ReaderMode.continuousHorizontalRTL => FluentIcons.book_open_24_regular,
  ReaderMode.defaultReader => FluentIcons.book_open_24_regular,
};

IconData _pageLayoutIcon(PageLayout pageLayout) => switch (pageLayout) {
  PageLayout.singlePage => FluentIcons.document_one_page_24_regular,
  PageLayout.doublePages => FluentIcons.book_open_24_regular,
  PageLayout.automatic => FluentIcons.arrow_autofit_content_24_regular,
};

Future<void> showReaderChapterPicker({
  required BuildContext context,
  required int mangaId,
  required int currentChapterId,
  required String readerScanlatorGroup,
  required bool transVertical,
  bool floating = false,
}) {
  final readerContext = context;
  Widget chapterList(ScrollController? scrollController) => Consumer(
    builder: (context, ref, _) {
      // Keep the open chapter visible even if it is outside the scanlator filter.
      final chapters = ref.watch(
        mangaChapterListWithFilterProvider(
          mangaId: mangaId,
          keepChapterId: currentChapterId,
          readerScanlatorGroup: readerScanlatorGroup,
        ),
      );
      return chapters.showUiWhenData(
        context,
        (items) => _ReaderChapterSheet(
          chapters: items ?? const [],
          currentChapterId: currentChapterId,
          mangaId: mangaId,
          readerContext: readerContext,
          scrollController: scrollController,
          transVertical: transVertical,
          floating: floating,
          refreshChapters: () async {
            final reload = ref.refresh(
              mangaChapterListProvider(mangaId: mangaId).future,
            );
            await reload;
          },
        ),
      );
    },
  );
  if (floating) {
    return showFloatingReaderChapterPicker<void>(
      context: context,
      builder: (_) => chapterList(null),
    );
  }
  return showAppBottomSheet<void>(
    context: context,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.46,
      minChildSize: 0.26,
      maxChildSize: 0.82,
      builder: (context, scrollController) => chapterList(scrollController),
    ),
  );
}

Future<T?> showFloatingReaderChapterPicker<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final glass = supportsAppleGlass(context);
  final dim = context.reduceMotion
      ? Duration.zero
      : const Duration(milliseconds: 180);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: dim,
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (context, _, _) => SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 5, left: 20, right: 20),
          child: LayoutBuilder(
            builder: (context, constraints) => ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 286,
                maxWidth: 286,
                maxHeight: constraints.maxHeight * .67,
              ),
              child: Theme(
                data: ThemeData.dark(useMaterial3: true),
                child: glass
                    ? AppleGlassSurface(
                        child: Material(
                          color: ReaderOverlayColors.chapterPickerGlassTint,
                          borderRadius: BorderRadius.circular(
                            AppleGlassSurface.radius,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: builder(context),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Material(
                            color: ReaderOverlayColors.chapterPickerSurface,
                            child: builder(context),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReaderChapterSheet extends StatelessWidget {
  const _ReaderChapterSheet({
    required this.chapters,
    required this.currentChapterId,
    required this.mangaId,
    required this.readerContext,
    required this.scrollController,
    required this.transVertical,
    required this.refreshChapters,
    required this.floating,
  });

  final List<ChapterDto> chapters;
  final int currentChapterId;
  final int mangaId;
  final BuildContext readerContext;
  final ScrollController? scrollController;
  final bool transVertical;
  final Future<void> Function() refreshChapters;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    Widget chapterRow(BuildContext context, int index) {
      final chapter = chapters[index];
      final isCurrent = chapter.id == currentChapterId;
      final lastPageRead = chapter.user.lastPageRead.getValueOnNullOrNegative();
      final scanlator = chapter.scanlator.isNotBlank
          ? chapter.scanlator!
          : context.l10n.unknownScanlator;
      final trailing = IconButtonTheme(
        data: IconButtonThemeData(
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size.square(36)),
            fixedSize: const WidgetStatePropertyAll(Size.square(36)),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: SizedBox(
          width: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DownloadStatusIcon(
                updateData: refreshChapters,
                chapter: chapter,
                mangaId: mangaId,
                isDownloaded: chapter.user.isDownloaded.ifNull(),
              ),
            ],
          ),
        ),
      );
      void openChapter() {
        Navigator.of(context).pop();
        if (isCurrent) return;
        if (!readerContext.mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!readerContext.mounted) return;
          ReaderRoute(
            mangaId: mangaId,
            chapterId: chapter.id,
            readerScanlatorGroup: scanlatorGroupOf(chapter),
            showReaderLayoutAnimation: true,
            transVertical: transVertical,
          ).pushReplacement(readerContext);
        });
      }

      return ReaderChapterPickerRow(
        title: chapter.name,
        subtitle: [
          scanlator,
          if (lastPageRead > 0) context.l10n.page(lastPageRead + 1),
        ].join(' • '),
        current: isCurrent,
        complete: chapter.user.isRead.ifNull(),
        floating: floating,
        onSelected: openChapter,
        trailing: trailing,
      );
    }

    final pickerList = ReaderChapterPickerList(
      count: chapters.length,
      currentIndex: chapters.indexWhere(
        (chapter) => chapter.id == currentChapterId,
      ),
      floating: floating,
      controller: scrollController,
      itemBuilder: chapterRow,
    );
    if (floating) return pickerList;

    return Column(
      children: [
        AppSheetHeader(title: context.l10n.noOfChapters(chapters.length)),
        Expanded(child: pickerList),
      ],
    );
  }
}

class ReaderChapterPickerRow extends StatelessWidget {
  const ReaderChapterPickerRow({
    super.key,
    required this.title,
    required this.current,
    required this.complete,
    required this.floating,
    required this.onSelected,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final bool current;
  final bool complete;
  final bool floating;
  final VoidCallback onSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final leading = Icon(
      floating && current
          ? FluentIcons.checkmark_24_regular
          : complete
          ? FluentIcons.checkmark_circle_24_regular
          : FluentIcons.circle_24_regular,
      size: 20,
    );
    final titleWidget = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final subtitleWidget = subtitle == null
        ? null
        : Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodySmall,
          );
    if (floating) {
      return Ink(
        color: current ? ReaderOverlayColors.selectedChapterFill : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  selected: current,
                  button: true,
                  child: InkWell(
                    onTap: onSelected,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        8,
                        0,
                        8,
                      ),
                      child: Row(
                        children: [
                          ExcludeSemantics(child: leading),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [titleWidget, ?subtitleWidget],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      );
    }
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
      minLeadingWidth: 24,
      minVerticalPadding: 0,
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      selected: current,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.55),
      selectedColor: colorScheme.onPrimaryContainer,
      leading: leading,
      title: titleWidget,
      subtitle: subtitleWidget,
      trailing: trailing,
      onTap: onSelected,
    );
  }
}

class ReaderChapterPickerList extends StatelessWidget {
  const ReaderChapterPickerList({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.floating,
    required this.itemBuilder,
    this.controller,
  });

  final int count;
  final int currentIndex;
  final bool floating;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    if (floating) {
      if (count == 0) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Text(
            context.l10n.noChaptersFound,
            textAlign: TextAlign.center,
          ),
        );
      }
      if (count <= 5) {
        return ListView.builder(
          primary: false,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: count,
          itemBuilder: itemBuilder,
        );
      }
      // Anchor near the bottom when there are too few later chapters to fill
      // the viewport below the current one.
      final reverse = currentIndex >= count - 5;
      int chapterIndex(int index) => reverse ? count - 1 - index : index;
      final first = (chapterIndex(currentIndex) - 1).clamp(0, count - 1);
      const center = ValueKey('reader-chapter-picker-center');
      return CustomScrollView(
        center: center,
        primary: false,
        reverse: reverse,
        scrollCacheExtent: const ScrollCacheExtent.pixels(112),
        semanticChildCount: count,
        slivers: [
          if (first > 0)
            SliverPadding(
              padding: const EdgeInsets.only(top: 8),
              sliver: SliverList.builder(
                itemCount: first,
                addSemanticIndexes: false,
                itemBuilder: (context, index) {
                  final chapter = chapterIndex(first - index - 1);
                  return IndexedSemantics(
                    index: chapter,
                    child: itemBuilder(context, chapter),
                  );
                },
              ),
            ),
          SliverPadding(
            key: center,
            padding: EdgeInsets.only(top: first == 0 ? 8 : 0, bottom: 8),
            sliver: SliverList.builder(
              itemCount: count - first,
              addSemanticIndexes: false,
              itemBuilder: (context, index) {
                final chapter = chapterIndex(first + index);
                return IndexedSemantics(
                  index: chapter,
                  child: itemBuilder(context, chapter),
                );
              },
            ),
          ),
        ],
      );
    }

    if (count == 0) return Center(child: Text(context.l10n.noChaptersFound));
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: count,
      itemBuilder: itemBuilder,
    );
  }
}
