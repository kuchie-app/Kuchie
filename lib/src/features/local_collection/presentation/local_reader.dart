import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../constants/enum.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/custom_circular_progress_indicator.dart';
import '../../../widgets/ios/apple_glass_capability.dart';
import '../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../widgets/popup_widgets/app_dialog.dart';
import '../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../widgets/server_image.dart';
import '../../../widgets/zoom/scroll_offset_to_scroll_controller.dart';
import '../../manga_book/presentation/reader/controller/auto_scroll_controller.dart';
import '../../manga_book/presentation/reader/controller/auto_webtoon.dart';
import '../../manga_book/presentation/reader/controller/display_cutout.dart';
import '../../manga_book/presentation/reader/controller/reader_settings_model.dart';
import '../../manga_book/presentation/reader/utils/reader_mode_kind.dart';
import '../../manga_book/presentation/reader/widgets/chrome/reader_bottom_controls.dart';
import '../../manga_book/presentation/reader/widgets/chrome/reader_chrome.dart';
import '../../manga_book/presentation/reader/widgets/chrome/reader_page_actions_sheet.dart';
import '../../manga_book/presentation/reader/widgets/chrome/reader_quick_settings_sheet.dart';
import '../../manga_book/presentation/reader/widgets/chrome/reader_top_bar.dart';
import '../../manga_book/presentation/reader/widgets/reader_edge_swipe_back.dart';
import '../../manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/infinity_continuous_config.dart';
import '../../manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/infinity_continuous_feedback.dart';
import '../../manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/measure_size.dart';
import '../../manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/strip_resize_correction.dart';
import '../../manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/tall_page_image.dart';
import '../../manga_book/presentation/reader/widgets/reader_mode/paged_display_window.dart';
import '../../manga_book/presentation/reader/widgets/reader_mode/paged_reader_viewport.dart';
import '../../manga_book/presentation/reader/widgets/reader_mode/paged_spread_mapping.dart';
import '../../manga_book/presentation/reader/widgets/reader_mode/reader_page_file.dart';
import '../../manga_book/presentation/reader/widgets/reader_mode/reader_zoom_view.dart';
import '../../manga_book/presentation/reader/widgets/reader_navigation_layout/reader_navigation_layout.dart';
import '../../manga_book/presentation/reader/widgets/reader_wrapper.dart';
import '../../settings/presentation/general/widgets/force_portrait_tile.dart';
import '../../settings/presentation/incognito/incognito_mode.dart';
import '../../settings/presentation/reader/widgets/reader_auto_webtoon_mode/reader_auto_webtoon_mode.dart';
import '../../settings/presentation/reader/widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import '../../settings/presentation/reader/widgets/reader_initial_overlay_tile/reader_initial_overlay_tile.dart';
import '../../settings/presentation/reader/widgets/reader_keep_screen_on_tile/reader_keep_screen_on_tile.dart';
import '../../settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import '../../settings/presentation/reader/widgets/reader_orientation/reader_orientation.dart';
import '../data/local_catalog.dart';
import '../data/local_preferences.dart';
import '../data/local_reading_stats.dart';
import 'local_ui.dart';

class LocalReaderChapterEntry {
  const LocalReaderChapterEntry({
    required this.id,
    required this.title,
    this.saved,
  });

  final String id;
  final String title;
  final LocalChapter? saved;
}

class LocalReaderChapterContent {
  const LocalReaderChapterContent({
    required this.chapter,
    this.ephemeral = false,
    this.preparePage,
  });

  final LocalChapter chapter;
  final bool ephemeral;
  final Future<File> Function(String uri)? preparePage;
}

class LocalReader extends ConsumerStatefulWidget {
  const LocalReader({
    super.key,
    required this.series,
    required this.chapter,
    required this.catalog,
    this.ephemeral = false,
    this.chapterEntries,
    this.loadChapter,
    this.preparePage,
    this.readerFormat,
  });

  final LocalSeries series;
  final LocalChapter chapter;
  final LocalCatalog catalog;
  final bool ephemeral;
  final List<LocalReaderChapterEntry>? chapterEntries;
  final Future<LocalReaderChapterContent> Function(String id)? loadChapter;
  final Future<File> Function(String uri)? preparePage;
  final ReaderFormatMetadata? readerFormat;

  @override
  ConsumerState<LocalReader> createState() => _LocalReaderState();
}

class _LocalReaderState extends ConsumerState<LocalReader> {
  final _paged = PagedReaderController();
  final _scroll = ItemScrollController();
  final _scrollOffset = ScrollOffsetController();
  late final _zoomScroll = ScrollOffsetToScrollController(
    scrollOffsetController: _scrollOffset,
  );
  final _positions = ItemPositionsListener.create();
  late final _resizeCorrection = StripResizeCorrection(
    itemScrollController: _scroll,
    scrollOffsetController: _scrollOffset,
    positionsListener: _positions,
  );
  final _wide = <int, bool>{};
  late LocalChapter _chapter = widget.chapter;
  late bool _ephemeral = widget.ephemeral;

  /// Saved chapters read to the end, removed when the reader closes if
  /// Delete after reading is on.
  final _readToDelete = <String>{};
  late final ReaderFormatMetadata _format =
      widget.readerFormat ??
      (
        genres: widget.series.source?.genres ?? const [],
        sourceName: widget.series.source?.sourceName,
      );
  late Future<File> Function(String uri)? _preparePage = widget.preparePage;
  late List<String> _pages = _chapter.pages
      .map((page) => page.uri.toString())
      .toList();
  late int _index = _chapter.progress.clamp(0, _pages.length - 1);
  late final _pageIndex = ValueNotifier(_index);
  final _dimensions = TallPageDimensionCache();
  final _measuredSizes = <String, Size>{};
  final _retryCount = ValueNotifier(0);
  int _chapterRequest = 0;
  String? _loadingChapter;
  bool _pickingChapter = false;
  bool _rebuildSpreadScheduled = false;
  late bool _bookmarked = _chapter.bookmarked;
  PagedDisplayWindow? _window;
  ({bool doublePages, bool split, bool invert, bool offset})? _windowLayout;
  VoidCallback? _clearOrientation;
  late final _utilsExpanded = ValueNotifier(false);
  late final _readerPadding = ValueNotifier(_settings.sidePadding);
  late final AppLifecycleListener _lifecycle;
  Timer? _autoScrollTimer;
  bool _wakeLock = false;
  bool _showingPageActions = false;
  bool _stripInMotion = false;
  bool _tapArrestsFling = false;
  late final _visibility = ValueNotifier(
    ref.read(readerInitialOverlayProvider).ifNull(),
  );
  bool _restore = true;
  bool _continuous = false;
  bool _finished = false;
  bool _pending = false;
  bool _incognito = false;

  /// Time on screen since the reader opened or came back to the front.
  final _reading = Stopwatch()..start();

  void _recordReading() {
    final elapsed = _reading.elapsed;
    _reading.reset();
    if (_incognito) return;
    unawaited(
      LocalReadingStats.instance.add(
        widget.series.id,
        widget.series.title,
        elapsed,
      ),
    );
  }

  bool _opened = false;
  Timer? _saveTimer;

  ReaderSettingsModelProvider get _settingsProvider =>
      readerSettingsModelProvider(0, localSeriesId: widget.series.id);

  ReaderSettingsState get _settings => ref.read(_settingsProvider);

  List<LocalReaderChapterEntry> get _entries =>
      widget.chapterEntries ??
      [
        for (final chapter in widget.series.chapters)
          LocalReaderChapterEntry(
            id: chapter.id,
            title: chapter.title,
            saved: chapter,
          ),
      ];

  @override
  void initState() {
    super.initState();
    unawaited(LocalPreferences.instance.load());
    _positions.itemPositions.addListener(_positionChanged);
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _pause();
        _recordReading();
        _reading.stop();
      },
      onShow: _reading.start,
    );
    ref.listenManual(_settingsProvider, (previous, next) {
      if (previous?.readerOrientation != next.readerOrientation) {
        _applyOrientation(next.readerOrientation);
      }
      if (previous?.drawUnderCutout != next.drawUnderCutout) {
        unawaited(setDrawUnderCutout(next.drawUnderCutout));
      }
    }, fireImmediately: true);
    ref.listenManual(keepScreenOnProvider, (_, next) {
      final keepScreenOn = next ?? false;
      if (keepScreenOn == _wakeLock) return;
      _wakeLock = keepScreenOn;
      WakelockPlus.toggle(enable: keepScreenOn).ignore();
    }, fireImmediately: true);
    _prefetch(_index);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_positionChanged);
    _resizeCorrection.dispose();
    _saveTimer?.cancel();
    _save();
    _recordReading();
    for (final chapterId in _readToDelete) {
      unawaited(
        widget.catalog
            .removeChapter(widget.series.id, chapterId)
            .catchError((Object _) {}),
      );
    }
    _autoScrollTimer?.cancel();
    _clearOrientation?.call();
    unawaited(setDrawUnderCutout(false));
    if (_wakeLock) WakelockPlus.disable().ignore();
    _lifecycle.dispose();
    _readerPadding.dispose();
    _utilsExpanded.dispose();
    _visibility.dispose();
    _pageIndex.dispose();
    _retryCount.dispose();
    _zoomScroll.dispose();
    super.dispose();
  }

  void _applyOrientation(ReaderOrientation orientation) {
    final lock = orientation.deviceOrientations;
    if (lock == null) {
      _clearOrientation?.call();
      _clearOrientation = null;
      return;
    }
    final forcePortrait = ref.read(forcePortraitProvider).ifNull();
    _clearOrientation ??= () => applyForcePortrait(forcePortrait);
    unawaited(SystemChrome.setPreferredOrientations(lock));
  }

  void _pause() {
    _save();
    ref.read(autoScrollActiveProvider.notifier).stop();
  }

  ReaderMode _resolvedMode(
    ReaderMode perSeries,
    ReaderMode? configured, {
    required bool auto,
  }) =>
      sessionAutoReaderMode(
        enabled: auto,
        seriesMode: perSeries,
        genres: _format.genres,
        sourceName: _format.sourceName,
      ) ??
      switch ((perSeries, configured)) {
        (final mode, _) when mode != ReaderMode.defaultReader => mode,
        (_, final mode?) when mode != ReaderMode.defaultReader => mode,
        // Matches the app-wide default (DBKeys.readerMode).
        _ => ReaderMode.webtoon,
      };

  void _updateAutoScroll() {
    final mode = _resolvedMode(
      _settings.readerMode,
      ref.read(readerModeKeyProvider),
      auto: ref.read(autoWebtoonModeProvider).ifNull(true),
    );
    _autoScrollTimer?.cancel();
    if (!ref.read(autoScrollActiveProvider)) return;
    final isVerticalStrip =
        mode == ReaderMode.webtoon || mode == ReaderMode.continuousVertical;
    final seconds = isVerticalStrip
        ? _settings.autoScrollIntervalSeconds
        : _settings.autoAdvanceIntervalSeconds;
    _autoScrollTimer = Timer.periodic(Duration(seconds: seconds), (timer) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (_index >= _pages.length - 1) {
        ref.read(autoScrollActiveProvider.notifier).stop();
        return;
      }
      if (!_continuous) {
        _paged.next();
      } else if (_scroll.isAttached) {
        final target = _index + 1;
        if (isVerticalStrip) {
          final distance =
              _scrollOffset.position.viewportDimension *
              _settings.readerScrollAmount.fraction;
          final duration = !_settings.smoothAutoScroll || context.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220);
          if (duration == Duration.zero) {
            final position = _scrollOffset.position;
            position.jumpTo(
              (position.pixels + distance).clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
            );
          } else {
            unawaited(
              _scrollOffset.animateScroll(offset: distance, duration: duration),
            );
          }
        } else if (_settings.smoothAutoScroll && !context.reduceMotion) {
          unawaited(
            _scroll.scrollTo(
              index: target,
              duration: const Duration(milliseconds: 220),
            ),
          );
        } else {
          _seek(target);
        }
      }
    });
  }

  void _save() {
    if (!_pending || _incognito) return;
    _pending = false;
    unawaited(_writeProgress(_chapter, _index, ephemeral: _ephemeral));
  }

  // Chapters read online have no saved pages, so they go to History only.
  Future<void> _writeProgress(
    LocalChapter chapter,
    int index, {
    required bool ephemeral,
  }) async {
    try {
      if (ephemeral) {
        await widget.catalog.recordRemoteRead(
          series: widget.series,
          chapterId: chapter.id,
          chapterTitle: chapter.title,
          progress: index,
        );
      } else {
        await widget.catalog.setProgress(widget.series.id, chapter.id, index);
      }
    } catch (_) {
      if (mounted) _showStorageError();
    }
  }

  // Reaching the end marker completes the chapter, saved or read online.
  Future<void> _markRead(String chapterId) async {
    try {
      await widget.catalog.setChapterMarks(widget.series.id, [
        chapterId,
      ], read: true);
    } catch (_) {
      if (mounted) _showStorageError();
    }
  }

  void _showStorageError() => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.l10n.errorSomethingWentWrong)));

  void _onPage(int raw) {
    if (!mounted || raw < 0 || raw > _pages.length) return;
    if (raw == _pages.length) {
      if (!_finished) {
        setState(() => _finished = true);
        if (!_incognito) unawaited(_markRead(_chapter.id));
        if (!_ephemeral && LocalPreferences.instance.deleteAfterReading.value) {
          _readToDelete.add(_chapter.id);
        }
      }
      return;
    }
    if (_restore) {
      _restore = false;
      if (raw == _index) return;
    }
    if (_index == raw && !_finished) return;
    _index = raw;
    _finished = false;
    _pageIndex.value = raw;
    _prefetch(raw);
    if (_incognito) return;
    _pending = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 550), _save);
  }

  static const _prefetchAhead = 4;

  /// Online chapters download a page only when asked. Ask a few pages ahead so
  /// a fast fling lands on measured pages instead of placeholders that then
  /// grow and shove the strip. prepare() dedupes, so the page widget reuses it.
  void _prefetch(int from) {
    final prepare = _preparePage;
    if (prepare == null) return;
    final pages = _pages;
    for (
      var i = from + 1;
      i <= from + _prefetchAhead && i < pages.length;
      i++
    ) {
      unawaited(prepare(pages[i]).then<void>((_) {}, onError: (_) {}));
    }
  }

  void _positionChanged() {
    if (!_continuous || !mounted) return;
    var visible = -1;
    for (final item in _positions.itemPositions.value) {
      if (item.itemTrailingEdge > 0 &&
          item.itemLeadingEdge < .42 &&
          item.index > visible) {
        visible = item.index;
      }
    }
    if (visible >= 0) _onPage(visible);
  }

  void _seek(int page) {
    final target = page.clamp(0, _pages.length - 1);
    if (_continuous) {
      if (_scroll.isAttached) _scroll.jumpTo(index: target);
    } else {
      _paged.jumpToRaw(target);
    }
    _onPage(target);
  }

  /// Tap-zone navigation in the strip: scroll by the configured share of the
  /// viewport, the same amount the server reader uses.
  void _scrollViewport({required bool forward}) {
    if (!_scroll.isAttached) return;
    final position = _scrollOffset.position;
    final offset =
        position.viewportDimension *
        _settings.readerScrollAmount.fraction *
        (forward ? 1 : -1);
    final target = (position.pixels + offset).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (_settings.animatePageTransitions && !context.reduceMotion) {
      unawaited(
        _scrollOffset.animateScroll(
          offset: target - position.pixels,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    } else {
      position.jumpTo(target);
    }
  }

  void _openChapter(LocalReaderChapterEntry entry) {
    if (entry.id == _chapter.id || entry.id == _loadingChapter) return;
    if (entry.saved case final chapter?) {
      ++_chapterRequest;
      _showChapter(LocalReaderChapterContent(chapter: chapter));
    } else if (widget.loadChapter case final load?) {
      final request = ++_chapterRequest;
      setState(() => _loadingChapter = entry.id);
      unawaited(() async {
        try {
          final content = await load(entry.id);
          if (mounted && request == _chapterRequest) _showChapter(content);
        } catch (error) {
          if (!mounted || request != _chapterRequest) return;
          setState(() => _loadingChapter = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${entry.title}: ${localErrorMessage(context, error)}',
              ),
              action: SnackBarAction(
                label: context.l10n.retry,
                onPressed: () => _openChapter(entry),
              ),
            ),
          );
        }
      }());
    }
  }

  void _showChapter(LocalReaderChapterContent content) {
    final chapter = content.chapter;
    if (chapter.id == _chapter.id || chapter.pages.isEmpty) return;
    _saveTimer?.cancel();
    _save();
    setState(() {
      _chapter = chapter;
      _ephemeral = content.ephemeral;
      _preparePage = content.preparePage;
      _loadingChapter = null;
      _opened = false;
      _pages = chapter.pages.map((page) => page.uri.toString()).toList();
      _index = chapter.progress.clamp(0, _pages.length - 1);
      _bookmarked = chapter.bookmarked;
      _window = null;
      _wide.clear();
      _measuredSizes.clear();
      _restore = true;
      _finished = false;
    });
    _pageIndex.value = _index;
    _prefetch(_index);
  }

  Future<void> _bookmark() async {
    final chapter = _chapter;
    final next = !_bookmarked;
    try {
      await widget.catalog.setBookmark(widget.series.id, chapter.id, next);
      if (mounted && chapter.id == _chapter.id) {
        setState(() => _bookmarked = next);
      }
    } catch (_) {
      if (mounted) _showStorageError();
    }
  }

  void _toggleOverlay() => _visibility.value = !_visibility.value;

  /// A tap that stops a fling only stops it, like the server reader.
  void _onStripTap() {
    if (_tapArrestsFling) return;
    _toggleOverlay();
  }

  Future<void> _pickChapter() async {
    if (_pickingChapter) return;
    _pickingChapter = true;
    final chapters = _entries;
    try {
      final selected = supportsAppleGlass(context)
          ? await showFloatingReaderChapterPicker<LocalReaderChapterEntry>(
              context: context,
              builder: (_) => _chapterPickerList(chapters, floating: true),
            )
          : await showAppBottomSheet<LocalReaderChapterEntry>(
              context: context,
              builder: (context) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.46,
                minChildSize: 0.26,
                maxChildSize: 0.82,
                builder: (context, controller) => Column(
                  children: [
                    AppSheetHeader(
                      title: context.l10n.noOfChapters(chapters.length),
                    ),
                    Expanded(
                      child: _chapterPickerList(
                        chapters,
                        floating: false,
                        controller: controller,
                      ),
                    ),
                  ],
                ),
              ),
            );
      if (mounted && selected != null) _openChapter(selected);
    } finally {
      _pickingChapter = false;
    }
  }

  Widget _chapterPickerList(
    List<LocalReaderChapterEntry> chapters, {
    required bool floating,
    ScrollController? controller,
  }) {
    return ReaderChapterPickerList(
      count: chapters.length,
      currentIndex: chapters.indexWhere((chapter) => chapter.id == _chapter.id),
      floating: floating,
      controller: controller,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final current = chapter.id == _chapter.id;
        final saved = chapter.saved;
        final progress = current ? _index : saved?.progress ?? 0;
        return ReaderChapterPickerRow(
          title: chapter.title,
          subtitle: progress > 0 ? context.l10n.page(progress + 1) : null,
          current: current,
          complete:
              saved?.lastReadAt != null &&
              saved!.progress >= saved.pages.length - 1,
          floating: floating,
          onSelected: () => Navigator.of(context).pop(chapter),
        );
      },
    );
  }

  Future<void> _pickMode() => showAppDialog<void>(
    context: context,
    builder: (dialogContext) => RadioListPopup<ReaderMode>(
      optionList: ReaderMode.displayOrder,
      separatorBefore: ReaderMode.continuousHorizontalLTR,
      getOptionTitle: (mode) => mode.toLocale(dialogContext),
      value: _settings.readerMode,
      title: dialogContext.l10n.readerMode,
      onChange: (mode) {
        Navigator.pop(dialogContext);
        if (!mounted) return;
        unawaited(ref.read(_settingsProvider.notifier).setReaderMode(mode));
      },
    ),
  );

  void _openSettings() {
    _readerPadding.value = _settings.sidePadding;
    unawaited(
      showReaderQuickSettings(
        context: context,
        ref: ref,
        mangaId: 0,
        localSeriesId: widget.series.id,
        localFormat: _format,
        visibility: _visibility,
        readerPadding: _readerPadding,
      ),
    );
  }

  Future<void> _openPageActions() async {
    if (_showingPageActions ||
        _finished ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _showingPageActions = true;
    try {
      final windowChapter = _window?.chapterById(1);
      final mapping = windowChapter?.mapping;
      final spread = _continuous || mapping == null
          ? null
          : mapping.entries[mapping.rawToDisplay(_index)];
      await showReaderImageActionsSheet(
        context: context,
        ref: ref,
        pages: _pages,
        pageIndex: _index,
        spreadPageIndexes: switch (spread) {
          SpreadEntry(first: final first, second: final second?) => [
            first.raw,
            second.raw,
          ],
          _ => null,
        },
        preparePage: _preparePage,
      );
    } finally {
      _showingPageActions = false;
    }
  }

  void _retryPages() {
    _retryCount.value++;
    unawaited(retryFailedReaderPages(ref));
  }

  Widget _bookmarkButton(BuildContext context, {required bool floating}) =>
      _ephemeral
      ? const SizedBox(width: 48)
      : AppleGlassToolbarButton(
          id: 'reader-bookmark',
          symbol: _bookmarked ? 'bookmark.fill' : 'bookmark',
          label: _bookmarked
              ? context.l10n.removeBookmark
              : context.l10n.bookmark,
          fallbackIcon: _bookmarked
              ? FluentIcons.bookmark_24_filled
              : FluentIcons.bookmark_24_regular,
          onPressed: _bookmark,
          dark: floating ? true : null,
        );

  PagedDisplayWindow _makeWindow(
    ({bool doublePages, bool split, bool invert, bool offset}) layout,
  ) => buildPagedDisplayWindow(
    chapters: [
      WindowChapter(
        chapterId: 1,
        chapterName: _chapter.title,
        pages: _pages,
        mapping: buildSpreadMapping(
          pageCount: _pages.length,
          doublePages: layout.doublePages,
          splitWide: layout.split,
          splitInvert: layout.invert,
          offsetDoublePages: layout.offset,
          isWide: (raw) => _wide[raw] ?? false,
        ),
      ),
    ],
    forceTransition: false,
    trailingTransition: true,
  );

  @override
  Widget build(BuildContext context) {
    _incognito = ref.watch(incognitoModeProvider);
    if (!_incognito && !_opened) {
      _opened = true;
      final chapter = _chapter;
      final page = _index;
      final ephemeral = _ephemeral;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_incognito) {
          unawaited(_writeProgress(chapter, page, ephemeral: ephemeral));
        }
      });
    }
    final settings = ref.watch(_settingsProvider);
    final mode = _resolvedMode(
      settings.readerMode,
      ref.watch(readerModeKeyProvider),
      auto: ref.watch(autoWebtoonModeProvider).ifNull(true),
    );
    final horizontal =
        mode != ReaderMode.webtoon &&
        mode != ReaderMode.continuousVertical &&
        mode != ReaderMode.singleVertical;
    final reversed = isRTLReaderMode(mode);
    _continuous = !isPagedReaderMode(mode);
    ref.listen(autoScrollActiveProvider, (_, _) => _updateAutoScroll());
    ref.listen(autoWebtoonModeProvider, (_, _) => _updateAutoScroll());
    ref.listen(readerModeKeyProvider, (_, _) => _updateAutoScroll());
    ref.listen(
      _settingsProvider.select(
        (state) => (
          state.autoScrollIntervalSeconds,
          state.autoAdvanceIntervalSeconds,
          state.readerMode,
        ),
      ),
      (_, _) => _updateAutoScroll(),
    );
    final chapters = _entries;
    final chapterIndex = chapters.indexWhere((item) => item.id == _chapter.id);
    final next = chapterIndex >= 0 && chapterIndex + 1 < chapters.length
        ? chapters[chapterIndex + 1]
        : null;
    final previous = chapterIndex > 0 ? chapters[chapterIndex - 1] : null;
    final previousChapter = previous == null
        ? null
        : () => _openChapter(previous);
    final nextChapter = next == null ? null : () => _openChapter(next);
    final alwaysShow = settings.alwaysShowChapterTransition;
    final edge = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InfinityContinuousChapterSeparator(
            chapterName: _chapter.title,
            isChapterStart: false,
            alwaysShow: alwaysShow,
          ),
          if (next != null)
            TextButton(onPressed: nextChapter, child: Text(next.title)),
        ],
      ),
    );
    final key = ValueKey((_chapter.id, mode));
    final pages = _pages;
    final preparePage = _preparePage;
    final Widget content;
    if (_continuous) {
      final scrollAxis = horizontal ? Axis.horizontal : Axis.vertical;
      final strip = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onStripTap,
        onLongPress: settings.readWithLongTap ? _openPageActions : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            final dpr = MediaQuery.devicePixelRatioOf(context);
            final originalSize =
                settings.webtoonScaleType == WebtoonScaleType.originalSize;
            final stripWidth = horizontal || originalSize
                ? screenWidth
                : math.min(
                    settings.webtoonScaleType.maxContentWidth(
                      screenWidth,
                      screenHeight,
                    ),
                    settings.longStripWidthLimitUsePixels
                        ? settings.longStripWidthLimitPx
                              .clamp(200, 2000)
                              .toDouble()
                        : screenWidth *
                              settings.longStripWidthLimitPercent.clamp(
                                10,
                                100,
                              ) /
                              100,
                  );
            final list = ScrollablePositionedList.builder(
              key: key,
              itemCount: pages.length + 1,
              // Same page window as the server reader: decode a viewport ahead
              // so fast flings don't land on blank placeholders.
              cacheExtent: defaultTargetPlatform == TargetPlatform.iOS
                  ? (horizontal ? screenWidth : screenHeight)
                  : null,
              minCacheExtent: horizontal
                  ? screenWidth *
                        InfinityContinuousConfig.horizontalCacheMultiplier
                  : screenHeight *
                        InfinityContinuousConfig.verticalCacheMultiplier,
              initialScrollIndex: _index,
              itemScrollController: _scroll,
              scrollOffsetController: _scrollOffset,
              itemPositionsListener: _positions,
              scrollDirection: scrollAxis,
              reverse: reversed,
              itemBuilder: (context, page) {
                if (page == pages.length) {
                  return horizontal
                      ? SizedBox(width: constraints.maxWidth, child: edge)
                      : edge;
                }
                return MeasureSize(
                  key: ValueKey(('measure', pages[page])),
                  // A page above the visible ones that grows from its
                  // placeholder must not shove the strip or stop a fling.
                  onResize: (oldSize, newSize) => _resizeCorrection.onResize(
                    page,
                    horizontal
                        ? newSize.width - oldSize.width
                        : newSize.height - oldSize.height,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: mode == ReaderMode.continuousVertical
                          ? kLongStripPageGap
                          : 0,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: horizontal ? screenWidth : stripWidth,
                        child: _LocalStripPage(
                          key: ValueKey(pages[page]),
                          url: pages[page],
                          prepare: preparePage,
                          dimensions: _dimensions,
                          measuredSizes: _measuredSizes,
                          retryCount: _retryCount,
                          width: horizontal ? screenWidth : stripWidth,
                          height: screenHeight,
                          horizontal: horizontal,
                          originalSize: originalSize,
                          cropBorders: settings.cropBordersWebtoon,
                          dpr: dpr,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
            return Listener(
              onPointerDown: (_) => _tapArrestsFling = _stripInMotion,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.depth != 0) return false;
                  if (notification is ScrollStartNotification) {
                    _stripInMotion = true;
                  } else if (notification is ScrollEndNotification) {
                    _stripInMotion = false;
                  }
                  return false;
                },
                child: ReaderHideMenuOnUserScroll(
                  onHide: () {
                    if (_visibility.value) _visibility.value = false;
                  },
                  child: _resizeCorrection.wrap(list),
                ),
              ),
            );
          },
        ),
      );
      content =
          (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.android) &&
              (settings.longStripPinchToZoom ||
                  settings.longStripDoubleTapToZoom)
          ? ReaderZoomView(
              key: key,
              controller: _zoomScroll,
              scrollAxis: scrollAxis,
              reverse: reversed,
              maxScale: InfinityContinuousConfig.maxZoomScale,
              minScale: settings.longStripDisableZoomOut ? 1 : 0.5,
              pinchEnabled: settings.longStripPinchToZoom,
              doubleTapToZoom: settings.longStripDoubleTapToZoom,
              child: strip,
            )
          : strip;
    } else {
      final layout = (
        doublePages: settings.pageLayout.showsDoublePages(
          horizontal: horizontal,
          landscape: context.isLandscape,
          trueDualPageSpread: settings.trueDualPageSpread,
        ),
        split: settings.dualPageSplitPaged && horizontal,
        invert: settings.dualPageInvertPaged,
        offset: settings.offsetDoublePages,
      );
      if (_window == null || _windowLayout != layout) {
        _window = _makeWindow(layout);
        _windowLayout = layout;
      }
      final window = _window!;
      final navigationLayout = effectiveNavigationLayout(
        ref,
        mode: mode,
        seriesOverride: settings.navigationLayout,
      );
      final pageViewport = MediaQuery.sizeOf(context);
      final (pageFit, pageSize) = settings.imageScaleType.pagedFit(
        pageViewport.width,
        pageViewport.height,
      );
      content = ReaderInputScope(
        callbacks: ReaderInputCallbacks(
          onTap: _toggleOverlay,
          onLongPressStart: settings.readWithLongTap
              ? (_) => unawaited(_openPageActions())
              : null,
          onNext: _paged.next,
          onPrevious: _paged.previous,
          onNextBoundary: () => false,
          onPreviousBoundary: () => false,
          navigationLayout: navigationLayout,
          tapInvert: effectiveTapInvert(
            ref,
            mode: mode,
            layout: navigationLayout,
            seriesOverride: settings.tapInvert == TapInvert.none
                ? null
                : settings.tapInvert,
          ),
          smallerTapZones: settings.smallerTapZones,
        ),
        child: PagedReaderViewport(
          key: key,
          controller: _paged,
          window: window,
          initialDisplayIndex: window.chapterRawToDisplay(1, _index),
          axis: horizontal ? Axis.horizontal : Axis.vertical,
          reverse: reversed,
          animateTransitions:
              settings.animatePageTransitions && !context.reduceMotion,
          pageFit: pageFit,
          pageSize: pageSize,
          pagesAtNaturalSize: settings.imageScaleType.pagesAtNaturalSize,
          mouseScrollSpeed: 1,
          centerMargin: settings.centerMarginType,
          rotateWide: settings.rotateWidePages,
          rotateWideInvert: settings.rotateWideInvert,
          reversePair: settings.invertDoublePages != reversed,
          offsetDoublePages: settings.offsetDoublePages,
          cropBorders: settings.cropBorders,
          preparePage: preparePage,
          retryCount: _retryCount,
          constrainLocalDecode: true,
          onPageWide: (_, raw, wide) {
            if (!identical(pages, _pages)) return;
            if ((_wide[raw] ?? false) == wide) return;
            _wide[raw] = wide;
            if ((!layout.doublePages && !layout.split) ||
                _rebuildSpreadScheduled) {
              return;
            }
            _rebuildSpreadScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _rebuildSpreadScheduled = false;
              if (mounted &&
                  _windowLayout == layout &&
                  identical(pages, _pages)) {
                setState(() => _window = null);
              }
            });
          },
          onChapterPageChanged: (_, raw) => _onPage(raw),
          transitionBuilder: (_) => edge,
          pinchEnabled: settings.pagedPinchToZoom,
          doubleTapToZoom: settings.pagedDoubleTapToZoom,
          disableZoomIn: settings.disableZoomIn,
          disableZoomOut: settings.pagedDisableZoomOut,
          navigateToPan: settings.navigateToPan,
        ),
      );
    }
    final zonesLayout = effectiveNavigationLayout(
      ref,
      mode: mode,
      seriesOverride: settings.navigationLayout,
    );
    final zonesInvert = effectiveTapInvert(
      ref,
      mode: mode,
      layout: zonesLayout,
      seriesOverride: settings.tapInvert == TapInvert.none
          ? null
          : settings.tapInvert,
    );
    final pageContent = Stack(
      fit: StackFit.expand,
      children: [
        content,
        IgnorePointer(
          ignoring: !_continuous,
          child: ReaderNavigationLayoutWidget(
            navigationLayout: zonesLayout,
            tapInvert: zonesInvert,
            onNext: _continuous
                ? () => _scrollViewport(forward: true)
                : _paged.next,
            onPrevious: _continuous
                ? () => _scrollViewport(forward: false)
                : _paged.previous,
          ),
        ),
      ],
    );
    final size = MediaQuery.sizeOf(context);
    final landscapePhone = size.shortestSide < 600 && size.width > size.height;
    final showSideSeekBar =
        !horizontal &&
        !usesHorizontalReaderSeekbar(context, ref) &&
        (!landscapePhone || settings.landscapeVerticalSeekbar);
    void goBack() => Navigator.of(context).pop();

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
          );
        }
      },
      child: Scaffold(
        backgroundColor: settings.backgroundColor.color(context),
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _readerPadding,
              child: ReaderEdgeSwipeBack(child: pageContent),
              builder: (context, padding, child) => Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal ? 0 : size.width * padding,
                  vertical: horizontal ? size.height * padding : 0,
                ),
                child: child,
              ),
            ),
            ValueListenableBuilder<int>(
              valueListenable: _pageIndex,
              builder: (context, pageIndex, _) => ReaderChromeView(
                currentIndex: pageIndex,
                pageCount: _pages.length,
                visibility: _visibility,
                utilsBarExpanded: _utilsExpanded,
                useBottomSeekBar: !showSideSeekBar,
                showSideSeekBar: showSideSeekBar,
                scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
                onPreviousChapter: previousChapter,
                onNextChapter: nextChapter,
                resolvedReaderMode: mode,
                autoScrollSupported: true,
                // Page 1 sits at the left in every reading direction.
                reverseSeekBar: false,
                onChanged: _seek,
                onOpenSettings: _openSettings,
                onOpenReaderMode: _pickMode,
                topBar: (floating, onToggleAutoScroll, autoScrollLabel) =>
                    ReaderTopBarView(
                      seriesTitle: widget.series.title,
                      chapterTitle: _chapter.title,
                      onBack: goBack,
                      onRetry: _retryPages,
                      floating: floating,
                      bookmark: _bookmarkButton(context, floating: false),
                      onOpenReaderMode: floating ? _pickMode : null,
                      onOpenChapters: floating ? _pickChapter : null,
                      onToggleAutoScrollControls: onToggleAutoScroll,
                      autoScrollLabel: autoScrollLabel,
                    ),
                bottomBar: (floating) => ReaderBottomControlsView(
                  settingsMangaId: 0,
                  localSeriesId: widget.series.id,
                  currentIndex: pageIndex,
                  pageCount: _pages.length,
                  useBottomSeekBar: !showSideSeekBar,
                  scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
                  onPreviousChapter: previousChapter,
                  onNextChapter: nextChapter,
                  resolvedReaderMode: mode,
                  reverseSeekBar: false,
                  onChanged: _seek,
                  onOpenSettings: _openSettings,
                  onOpenReaderMode: _pickMode,
                  onOpenChapters: _pickChapter,
                  bookmark: _bookmarkButton(context, floating: floating),
                  floating: floating,
                ),
              ),
            ),
            if (_loadingChapter != null)
              Positioned(
                top: MediaQuery.viewPaddingOf(context).top + 57,
                left: 16,
                right: 16,
                child: const IgnorePointer(child: LinearProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocalStripPage extends StatefulWidget {
  const _LocalStripPage({
    super.key,
    required this.url,
    required this.prepare,
    required this.dimensions,
    required this.measuredSizes,
    required this.retryCount,
    required this.width,
    required this.height,
    required this.horizontal,
    required this.originalSize,
    required this.cropBorders,
    required this.dpr,
  });

  final String url;
  final Future<File> Function(String uri)? prepare;
  final TallPageDimensionCache dimensions;
  final Map<String, Size> measuredSizes;
  final ValueListenable<int> retryCount;
  final double width;
  final double height;
  final bool horizontal;
  final bool originalSize;
  final bool cropBorders;
  final double dpr;

  @override
  State<_LocalStripPage> createState() => _LocalStripPageState();
}

class _LocalStripPageState extends State<_LocalStripPage> {
  late Future<Size> _size = _readSize();

  Future<Size> _readSize() async {
    final url = widget.url;
    final cached = widget.measuredSizes[url];
    if (cached != null) return cached;
    final file = await widget.prepare?.call(url);
    final path = file?.path ?? Uri.parse(url).toFilePath();
    final size = await widget.dimensions.read(url, path);
    if (mounted && widget.url == url) widget.measuredSizes[url] = size;
    return size;
  }

  @override
  void initState() {
    super.initState();
    widget.retryCount.addListener(_retry);
  }

  @override
  void didUpdateWidget(_LocalStripPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retryCount != widget.retryCount) {
      oldWidget.retryCount.removeListener(_retry);
      widget.retryCount.addListener(_retry);
    }
  }

  void _retry() => setState(() => _size = _readSize());

  @override
  void dispose() {
    widget.retryCount.removeListener(_retry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Size>(
    future: _size,
    builder: (context, snapshot) {
      final intrinsic = snapshot.data ?? widget.measuredSizes[widget.url];
      final ratio = intrinsic == null || intrinsic.isEmpty
          ? 2 / 3
          : intrinsic.aspectRatio;
      final crossExtent = widget.horizontal ? widget.height : widget.width;
      final naturalExtent = widget.horizontal
          ? intrinsic?.height
          : intrinsic?.width;
      final cross = widget.originalSize && naturalExtent != null
          ? math.min(naturalExtent, crossExtent)
          : crossExtent;
      final size = widget.horizontal
          ? Size(cross * ratio, cross)
          : Size(cross, cross / ratio);
      return SizedBox.fromSize(
        size: size,
        child: snapshot.connectionState != ConnectionState.done
            ? const Center(child: CenterKuchieShimmerIndicator())
            : snapshot.hasError
            ? readerPageRetry(context, _retry)
            : ServerImage(
                imageUrl: widget.url,
                fit: BoxFit.contain,
                cropBorders: widget.cropBorders,
                memCacheWidth: widget.horizontal || widget.originalSize
                    ? null
                    : (cross * widget.dpr).round().clamp(1, 1 << 20),
                memCacheHeight: !widget.horizontal || widget.originalSize
                    ? null
                    : (cross * widget.dpr).round().clamp(1, 1 << 20),
              ),
      );
    },
  );
}
