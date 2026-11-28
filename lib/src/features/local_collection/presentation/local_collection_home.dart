import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/navigation_bar_data.dart';
import '../../../constants/urls.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/compact_switch.dart';
import '../../../widgets/emoticons.dart';
import '../../../widgets/in_app_web_view.dart';
import '../../../widgets/ios/apple_glass_capability.dart';
import '../../../widgets/ios/apple_glass_floating_header.dart';
import '../../../widgets/ios/apple_glass_search.dart';
import '../../../widgets/ios/apple_glass_segments.dart';
import '../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../widgets/ios/apple_page_title.dart';
import '../../../widgets/kuchie_character_motion.dart';
import '../../../widgets/kuchie_motion_reveal.dart';
import '../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../widgets/scroll_bottom_inset.dart';
import '../../../widgets/shell/apple_liquid_glass_tab_bar.dart';
import '../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../widgets/shell/nav_tabs_preference.dart';
import '../../history/presentation/widgets/history_item_tile.dart';
import '../../manga_book/presentation/manga_details/widgets/chapter_list_tile.dart';
import '../../onboarding/data/collection_mode.dart';
import '../../onboarding/presentation/collection_mode_picker.dart';
import '../../security/security_settings_screen.dart';
import '../../settings/presentation/downloads/widgets/downloads_overview.dart';
import '../../settings/presentation/incognito/incognito_mode.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../../sync/controller/sync_controller.dart';
import '../../sync/controller/sync_scheduler.dart';
import '../../sync/domain/sync_status.dart';
import '../../sync/presentation/sync_settings_screen.dart';
import '../../sync/presentation/sync_status_icon.dart';
import '../data/local_backups.dart';
import '../data/local_catalog.dart';
import '../data/local_collection_providers.dart';
import '../data/local_collection_services.dart';
import '../data/local_download_queue.dart';
import '../data/local_history.dart';
import '../data/local_preferences.dart';
import '../data/local_reading_stats.dart';
import '../data/local_sources.dart';
import '../data/local_updates.dart';
import 'local_extension_browser.dart';
import 'local_library_options.dart';
import 'local_series_personal.dart';
import 'local_settings.dart';
import 'local_ui.dart';

const _sections = ['library', 'updates', 'browse', 'history', 'more'];

class LocalCollectionHome extends ConsumerStatefulWidget {
  const LocalCollectionHome({
    super.key,
    required this.onOpenServer,
    this.initialSection,
  });

  final void Function(String section) onOpenServer;
  final String? initialSection;

  @override
  ConsumerState<LocalCollectionHome> createState() =>
      _LocalCollectionHomeState();
}

class _LocalCollectionHomeState extends ConsumerState<LocalCollectionHome> {
  late int _tab = _initialTab;
  late bool _downloads = widget.initialSection == 'downloads';
  late Future<LocalCollectionServices> _services = ref.read(
    localCollectionServicesProvider.future,
  );
  Future<List<LocalSeries>>? _library;
  Future<List<LocalRemoteRead>>? _remoteReads;
  LocalCollectionServices? _bound;
  bool _importing = false;
  bool _showExtensions = false;
  bool _searching = false;

  /// When each series was last read online, for the Last read order.
  Map<String, DateTime> _lastOnlineRead = const {};
  int _categoryRevision = 0;
  bool _openingManga = false;
  final _query = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    unawaited(_applyDefaultTab());
    // Sync runs on its own from here: on opening, when the network comes
    // back and after reading. A finished cycle shows what it pulled.
    ref.read(syncSchedulerProvider).start();
    ref.listenManual(
      syncControllerProvider.select((overview) => overview.status),
      (previous, next) {
        if (previous is SyncInProgress && next is! SyncInProgress) _refresh();
      },
    );
    // History shows each title's reading time.
    unawaited(
      LocalReadingStats.instance.load().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  /// Opens on the tab chosen in General, unless a link asked for one.
  Future<void> _applyDefaultTab() async {
    final preferences = LocalPreferences.instance;
    await preferences.load();
    if (!mounted || widget.initialSection != null) return;
    final tab = switch (preferences.defaultTab.value) {
      LocalDefaultTab.lastOpened => preferences.lastTab,
      LocalDefaultTab.library => 0,
      LocalDefaultTab.updates => 1,
      LocalDefaultTab.browse => 2,
      LocalDefaultTab.history => 3,
      LocalDefaultTab.more => 4,
    };
    if (tab != _tab && tab >= 0 && tab < _sections.length) _select(tab);
  }

  void _loadReads(LocalCollectionServices services) {
    final reads = services.catalog.remoteHistory();
    _remoteReads = reads;
    unawaited(
      reads.then((list) {
        if (!mounted) return;
        final latest = <String, DateTime>{};
        // Newest first, so the first row per series is its last read.
        for (final read in list) {
          latest.putIfAbsent(read.seriesId, () => read.lastReadAt);
        }
        setState(() => _lastOnlineRead = latest);
      }, onError: (Object _) {}),
    );
  }

  int get _initialTab {
    if (widget.initialSection == 'downloads') return 4;
    return _sections
        .indexOf(widget.initialSection ?? '')
        .clamp(0, _sections.length - 1);
  }

  @override
  void didUpdateWidget(LocalCollectionHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSection != oldWidget.initialSection) {
      _tab = _initialTab;
      _downloads = widget.initialSection == 'downloads';
    }
  }

  @override
  void dispose() {
    _bound?.downloads.completed.removeListener(_refresh);
    _bound?.downloads.removeListener(_onQueue);
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _bind(LocalCollectionServices services) {
    if (identical(_bound, services)) return;
    _bound?.downloads.completed.removeListener(_refresh);
    _bound?.downloads.removeListener(_onQueue);
    _bound = services;
    services.downloads.addListener(_onQueue);
    // Lists read kept covers from memory; repaint once they are known.
    unawaited(
      services.catalog.loadKeptCovers().then((_) {
        if (mounted) setState(() {});
      }),
    );
    _library = services.catalog.list();
    _loadReads(services);
    services.downloads.completed.addListener(_refresh);
    unawaited(_warmUpRuntime(services));
    // Scheduled backups run when Kuchie opens, as iOS gives no timer.
    unawaited(
      LocalBackups.instance
          .runIfDue(services.catalog)
          .catchError((Object _) {}),
    );
  }

  /// Boots the extension runtime after launch and loads the extensions behind
  /// the latest History entries, as the server app keeps its server running.
  Future<void> _warmUpRuntime(LocalCollectionServices services) async {
    // Let the first screen settle before the interpreter competes for CPU.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    try {
      await services.sources.warmUpRuntime();
      final reads = await services.catalog.remoteHistory();
      await services.sources.preloadRuntimeSources([
        for (final read in reads.take(20)) ?read.source?.sourceId,
      ]);
    } on Exception {
      // Opening a source reports runtime problems.
    }
  }

  /// The Downloads toolbar shows Clear only while the queue has chapters.
  bool _queueHadItems = false;

  void _onQueue() {
    final has = _bound?.downloads.value.isNotEmpty ?? false;
    if (has != _queueHadItems && mounted) {
      setState(() => _queueHadItems = has);
    }
  }

  void _refresh() {
    final services = _bound;
    if (services != null && mounted) {
      setState(() {
        _library = services.catalog.list();
        _loadReads(services);
      });
    }
  }

  Future<void> _clearHistory() async {
    final services = _bound;
    if (services == null) return;
    if (!await localConfirm(
      context,
      localText(context, 'Clear history?', 'Hapus riwayat?'),
      localText(
        context,
        'Removes every entry from History. Saved chapters and reading progress stay.',
        'Menghapus semua entri dari Riwayat. Chapter tersimpan dan progres baca tetap ada.',
      ),
    )) {
      return;
    }
    try {
      await services.catalog.clearHistory();
      _refresh();
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Future<void> _chooseMode() async {
    final selected = await showCollectionModePicker(
      context,
      CollectionMode.local,
    );
    if (selected == CollectionMode.server && mounted) {
      widget.onOpenServer(_downloads ? 'downloads' : _sections[_tab]);
    }
  }

  Future<void> _import(LocalCatalog catalog) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      if (await _importManga(context, catalog) && mounted) {
        _refresh();
        _showImportSuccess(context);
      }
    } catch (error) {
      if (mounted) localFailure(context, error);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _select(int index) => setState(() {
    // Chapters read online in Browse never refresh this screen on their own.
    final services = _bound;
    if (index == 3 && services != null) {
      _library = services.catalog.list();
      _loadReads(services);
    }
    _tab = index;
    unawaited(LocalPreferences.instance.setLastTab(index));
    _downloads = false;
    _showExtensions = false;
    _searching = false;
    _query.clear();
  });

  void _toggleSearch() => setState(() {
    _searching = !_searching;
    if (!_searching) _query.clear();
  });

  PreferredSizeWidget _searchBar(String hint) => PreferredSize(
    preferredSize: const Size.fromHeight(52),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AppleGlassSearch(
        fallback: (context) => TextField(
          controller: _query,
          focusNode: _searchFocus,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: hint),
        ),
        native: (context) => AppleGlassSearchControl.field(
          controller: _query,
          focusNode: _searchFocus,
          placeholder: hint,
          label: context.l10n.search,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
      ),
    ),
  );

  Widget _searchButton() => AppleGlassToolbarButton(
    id: 'search',
    symbol: _searching ? 'xmark' : 'magnifyingglass',
    label: _searching ? context.l10n.close : context.l10n.search,
    fallbackIcon: _searching ? Icons.close : Icons.search,
    onPressed: _toggleSearch,
  );

  @override
  Widget build(BuildContext context) {
    final tabs = NavigationBarData.glassPhoneNavList;
    final browse = _tab == 2 && !_downloads;
    final library = _tab == 0 && !_downloads;
    final history = _tab == 3 && !_downloads;
    final updates = _tab == 1 && !_downloads;
    final l10n = context.l10n;
    final title = _downloads ? l10n.downloads : tabs[_tab].label(context);
    final queue = _bound?.downloads;
    return Scaffold(
      extendBody: supportsAppleGlass(context) && !_downloads,
      appBar: browse
          ? null
          : _downloads
          ? PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: detailNavigationBar(
                context,
                (leading) => _downloadsBar(leading, queue),
                back: detailBackButton(
                  () => setState(() => _downloads = false),
                ),
              ),
            )
          : AppBar(
              centerTitle: _tab == 4 ? true : false,
              title: library
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: CollectionModePageTitle(
                            title,
                            mode: CollectionMode.local,
                            onPressed: _chooseMode,
                          ),
                        ),
                        SyncStatusIcon(
                          onPressed: () => openSyncSettings(context),
                        ),
                      ],
                    )
                  : _tab == 4
                  ? Text(title)
                  : ApplePageTitle(title),
              bottom: _searching && (library || history)
                  ? _searchBar(
                      library ? l10n.searchLibraryHint : l10n.searchHistory,
                    )
                  : null,
              actions: [
                if (library || history) _searchButton(),
                if (history)
                  AppleGlassToolbarButton(
                    id: 'history-incognito',
                    symbol: ref.watch(incognitoModeProvider)
                        ? 'eyeglasses.slash'
                        : 'eyeglasses',
                    label: context.l10n.incognitoMode,
                    fallbackIcon: FluentIcons.incognito_24_regular,
                    color: ref.watch(incognitoModeProvider)
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    onPressed: () {
                      final on = !ref.read(incognitoModeProvider);
                      ref.read(incognitoModeProvider.notifier).set(on);
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              on
                                  ? localText(
                                      context,
                                      'Incognito mode on: reading is not saved to History',
                                      'Mode penyamaran aktif: bacaan tidak disimpan ke Riwayat',
                                    )
                                  : localText(
                                      context,
                                      'Incognito mode off',
                                      'Mode penyamaran nonaktif',
                                    ),
                            ),
                          ),
                        );
                    },
                  ),
                if (history)
                  AppleGlassToolbarButton(
                    id: 'clear-history',
                    symbol: 'trash',
                    label: localText(context, 'Clear history', 'Hapus riwayat'),
                    fallbackIcon: FluentIcons.delete_24_regular,
                    onPressed: _clearHistory,
                  ),
                if (library)
                  AppleGlassToolbarButton(
                    id: 'organize-library',
                    symbol: 'line.3.horizontal.decrease',
                    label: l10n.filter,
                    fallbackIcon: FluentIcons.filter_24_regular,
                    onPressed: () => showLocalLibraryOptions(context),
                  ),
                if (library)
                  AppleGlassToolbarButton(
                    id: 'update-overflow',
                    symbol: 'ellipsis',
                    label: l10n.more,
                    fallbackIcon: Icons.more_horiz,
                    onPressed: null,
                    menu: [
                      if (_bound case final services?) ...[
                        AppleGlassToolbarMenuItem(
                          id: 'local-file-import',
                          title: localText(
                            context,
                            'Import manga',
                            'Impor manga',
                          ),
                          symbol: 'folder.badge.plus',
                          fallbackIcon: Icons.create_new_folder_outlined,
                          onSelected: () => _import(services.catalog),
                        ),
                        AppleGlassToolbarMenuItem(
                          id: 'local-new-category',
                          title: localText(
                            context,
                            'New category',
                            'Kategori baru',
                          ),
                          symbol: 'plus',
                          fallbackIcon: Icons.add,
                          onSelected: () => _addCategory(services.catalog),
                        ),
                        AppleGlassToolbarMenuItem(
                          id: 'local-random-entry',
                          title: localText(
                            context,
                            'Open random entry',
                            'Buka judul acak',
                          ),
                          symbol: 'shuffle',
                          fallbackIcon: Icons.shuffle,
                          onSelected: () => _openRandom(services),
                        ),
                      ],
                    ],
                  ),
                if (updates)
                  AppleGlassToolbarButton(
                    id: 'refresh-updates',
                    symbol: 'arrow.clockwise',
                    label: l10n.refresh,
                    fallbackIcon: Icons.refresh,
                    onPressed: _refresh,
                  ),
              ],
            ),
      body: FutureBuilder<LocalCollectionServices>(
        future: _services,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() {
                  ref.invalidate(localCollectionServicesProvider);
                  _services = ref.read(localCollectionServicesProvider.future);
                }),
                child: Text(context.l10n.retry),
              ),
            );
          }
          final services = snapshot.data;
          if (services == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!identical(_bound, services)) {
            _bind(services);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
          if (_downloads) return _downloadsPage(services);
          if (browse) {
            return LocalExtensionBrowser(
              services: services,
              initialTab: _showExtensions ? 1 : 0,
              onImportManga: () => _import(services.catalog),
              onRestoreBackup: () =>
                  openLocalBackups(context, services, onRestored: _refresh),
            );
          }
          if (_tab == 4) return _more(services);
          return FutureBuilder<List<LocalSeries>>(
            future: _library,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: _refresh,
                    child: Text(context.l10n.retry),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final books = snapshot.requireData;
              return switch (_tab) {
                0 => _libraryPage(services, books),
                1 => _LocalUpdates(services: services, library: books),
                _ => _history(services, books),
              };
            },
          );
        },
      ),
      bottomNavigationBar: _downloads
          ? null
          : Consumer(
              builder: (context, ref, _) {
                // Order, visibility and labels from Customize tabs.
                final navTabs = ref.watch(navTabsProvider);
                final shown = navTabs.visibleLocal;
                final barTabs = [
                  for (final tab in shown)
                    navTabData(tab, labels: navTabs.labels),
                ];
                final selected = shown.indexWhere(
                  (tab) => tab.localSection == _tab,
                );
                final index = selected < 0 ? shown.length - 1 : selected;
                void onSelect(int i) => _select(shown[i].localSection!);
                return supportsAppleGlass(context)
                    ? AppleLiquidGlassTabBar(
                        tabs: barTabs,
                        selectedIndex: index,
                        downloadsPaused: false,
                        extensionUpdates: 0,
                        onDestinationSelected: onSelect,
                      )
                    : NavigationBar(
                        selectedIndex: index,
                        onDestinationSelected: onSelect,
                        labelBehavior: navTabs.labels
                            ? null
                            : NavigationDestinationLabelBehavior.alwaysHide,
                        destinations: [
                          for (final tab in barTabs)
                            NavigationDestination(
                              icon: Icon(tab.icon),
                              selectedIcon: Icon(tab.activeIcon),
                              label: tab.label(context),
                            ),
                        ],
                      );
              },
            ),
    );
  }

  Future<void> _addCategory(LocalCatalog catalog) async {
    final name = await localInput(
      context,
      localText(context, 'New category', 'Kategori baru'),
      localText(context, 'Name', 'Nama'),
    );
    if (name == null || !mounted) return;
    try {
      await catalog.createCategory(name);
      if (mounted) setState(() => _categoryRevision++);
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Widget _libraryPage(
    LocalCollectionServices services,
    List<LocalSeries> books,
  ) {
    final query = _query.text.trim().toLowerCase();
    final library = books.where((book) => book.inLibrary).toList();
    final matching = library
        .where((book) => book.title.toLowerCase().contains(query))
        .toList();
    final shelf = _LocalBooks(
      books: matching,
      lastOnlineRead: _lastOnlineRead,
      categoryRevision: _categoryRevision,
      services: services,
      empty: library.isNotEmpty
          ? _LocalEmpty(
              icon: Icons.search_off,
              title: context.l10n.noResultFound,
            )
          : _LocalEmpty(
              icon: Icons.auto_stories_outlined,
              illustration: const KuchieMotionReveal(
                child: KuchieCharacterMotion(
                  phase: KuchieCharacterPhase.empty,
                  width: 124,
                  play: false,
                ),
              ),
              title: localText(
                context,
                'Your local library is empty',
                'Perpustakaan lokal masih kosong',
              ),
              message: localText(
                context,
                'Import manga from Files or add a source to save chapters to this iPhone.',
                'Impor manga dari File atau tambah sumber untuk menyimpan chapter ke iPhone ini.',
              ),
              actions: [
                FilledButton.icon(
                  onPressed: _importing
                      ? null
                      : () => _import(services.catalog),
                  icon: _importing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(
                    localText(context, 'Import manga', 'Impor manga'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _tab = 2;
                    _showExtensions = true;
                  }),
                  child: Text(
                    localText(context, 'Add a source', 'Tambah sumber'),
                  ),
                ),
              ],
            ),
      onOpen: (book) => _openManga(services, book),
    );
    final sync = ref.watch(syncControllerProvider);
    if (sync.status is SyncOff) return shelf;
    // Pulling down syncs now, then shows what came in.
    return RefreshIndicator(
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.vertical,
      onRefresh: () async {
        await ref.read(syncControllerProvider.notifier).syncNow();
        _refresh();
      },
      child: shelf,
    );
  }

  Future<void> _openManga(
    LocalCollectionServices services,
    LocalSeries book,
  ) async {
    if (_openingManga) return;
    _openingManga = true;
    try {
      await _openMangaDetail(services, book);
    } catch (error) {
      if (mounted) localFailure(context, error);
    } finally {
      _openingManga = false;
    }
  }

  Future<void> _runQueue(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
    if (mounted) setState(() {});
  }

  Future<void> _openRandom(LocalCollectionServices services) async {
    final books = [
      for (final book in await (_library ?? Future.value(<LocalSeries>[])))
        if (book.inLibrary) book,
    ];
    if (books.isEmpty || !mounted) return;
    await _openManga(services, books[math.Random().nextInt(books.length)]);
  }

  Future<void> _openMangaDetail(
    LocalCollectionServices services,
    LocalSeries book,
  ) async {
    final page = await _pushMangaDetail(services, book);
    if (page != null) await page.closed;
    _refresh();
  }

  /// Pushes the manga page for [book] and returns at once, with a future
  /// that completes when the page closes; null when it cannot open.
  Future<({Future<void> closed})?> _pushMangaDetail(
    LocalCollectionServices services,
    LocalSeries book,
  ) async {
    final sources = services.sources;
    final reference = localSeriesReference(sources, book);
    ({LocalExtension extension, LocalSourceManga manga})? selection;
    if (reference != null) {
      try {
        selection = await sources.resolveSeries(reference, book.title);
      } on FormatException {
        // A changed source may no longer recognize the saved locator.
      } on StateError {
        // Downloaded pages remain available when the extension is disabled.
      }
    }
    if (!mounted) return null;
    if (selection case final current?) {
      return (
        closed: openLocalSourceManga(
          context,
          services,
          current.extension,
          current.manga,
        ),
      );
    }
    if (reference == null || book.chapters.isNotEmpty) {
      return (
        closed: Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => _SeriesDetail(services: services, series: book),
          ),
        ),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          localText(
            context,
            'Install or enable this extension in Browse to view the manga.',
            'Pasang atau aktifkan ekstensi ini di Jelajahi untuk membuka manga.',
          ),
        ),
      ),
    );
    return null;
  }

  /// Continues [entry] in the reader, above its manga page, so Back from the
  /// reader lands on the manga rather than History.
  Future<void> _resumeHistory(
    LocalCollectionServices services,
    ({LocalSeries book, LocalChapter chapter, bool saved}) entry,
  ) async {
    if (_openingManga) return;
    _openingManga = true;
    try {
      final page = await _pushMangaDetail(services, entry.book);
      if (page != null) unawaited(page.closed.whenComplete(_refresh));
      if (!mounted) return;
      if (entry.saved) {
        await _openReader(context, services, entry.book, entry.chapter);
      } else {
        // Reopening asks the source for its chapter list first, which can
        // take a while when the runtime is still starting.
        final opening = _showOpening(context);
        try {
          await openRemoteLocalChapter(
            context,
            services,
            series: entry.book,
            chapterId: entry.chapter.id,
            onReady: opening.remove,
          );
        } finally {
          if (opening.mounted) opening.remove();
        }
      }
    } catch (error) {
      if (mounted) localFailure(context, error);
    } finally {
      _openingManga = false;
    }
    _refresh();
  }

  Widget _history(LocalCollectionServices services, List<LocalSeries> books) =>
      FutureBuilder<List<LocalRemoteRead>>(
        future: _remoteReads,
        builder: (context, snapshot) => _historyList(
          services,
          books,
          snapshot.data ?? const <LocalRemoteRead>[],
        ),
      );

  Widget _historyList(
    LocalCollectionServices services,
    List<LocalSeries> books,
    List<LocalRemoteRead> remoteReads,
  ) {
    final read = mergeLocalHistory(books, remoteReads);
    final query = _query.text.trim().toLowerCase();
    // One row per series, its latest chapter, as in Mihon.
    final seen = <String>{};
    final visible = [
      for (final item in read)
        if ((item.book.title.toLowerCase().contains(query) ||
                item.chapter.title.toLowerCase().contains(query)) &&
            seen.add(item.book.id))
          item,
    ];
    if (visible.isEmpty) {
      return _LocalEmpty(
        icon: Icons.history,
        title: localText(
          context,
          'No reading history yet',
          'Belum ada riwayat baca',
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, scrollBottomInset(context)),
      itemCount: visible.length,
      // State.context, so the post-await failure check matches `mounted`.
      itemBuilder: (_, index) {
        final entry = visible[index];
        return _LocalHistoryRow(
          book: entry.book,
          chapter: entry.chapter,
          keptCover: services.catalog.keptCover(entry.book.id),
          onOpen: () => _resumeHistory(services, entry),
          onOpenManga: () => _openManga(services, entry.book),
          readingTime: LocalReadingStats.instance.timeFor(entry.book.id),
          onRemove: () async {
            if (!await localConfirm(
              context,
              localText(context, 'Remove from history?', 'Hapus dari riwayat?'),
              entry.book.title,
            )) {
              return;
            }
            try {
              await services.catalog.removeFromHistory(entry.book.id);
              _refresh();
            } catch (error) {
              if (mounted) localFailure(context, error);
            }
          },
        );
      },
    );
  }

  Widget _more(LocalCollectionServices services) => ListView(
    padding: EdgeInsets.fromLTRB(0, 8, 0, scrollBottomInset(context)),
    children: [
      SettingsGroupRow(
        icon: Icons.swap_horiz_rounded,
        title: collectionModeTitle(context),
        subtitle: collectionModeLabel(context, CollectionMode.local),
        trailing: const Icon(FluentIcons.chevron_right_24_regular),
        onTap: _chooseMode,
      ),
      const Divider(height: 16),
      Consumer(
        builder: (context, ref, _) {
          final incognito = ref.watch(incognitoModeProvider);
          return SettingsGroupRow(
            icon: FluentIcons.incognito_24_regular,
            title: context.l10n.incognitoMode,
            subtitle: context.l10n.incognitoModeDescription,
            trailing: CompactSwitch(
              value: incognito,
              onChanged: (value) =>
                  ref.read(incognitoModeProvider.notifier).set(value),
            ),
            onTap: () =>
                ref.read(incognitoModeProvider.notifier).set(!incognito),
          );
        },
      ),
      // The same flat list as Tachimanga's More tab.
      _moreRow(
        FluentIcons.options_24_regular,
        context.l10n.general,
        () => openLocalGeneralSettings(context, services),
      ),
      _moreRow(
        FluentIcons.color_24_regular,
        context.l10n.appearance,
        () => context.push<void>(localAppearanceLocation),
      ),
      _moreRow(
        FluentIcons.library_24_regular,
        context.l10n.library,
        () => openLocalLibrarySettings(
          context,
          onEditCategories: () => _addCategory(services.catalog),
        ),
      ),
      _moreRow(
        FluentIcons.book_open_24_regular,
        context.l10n.reader,
        () => context.push<void>(localReaderSettingsLocation),
      ),
      _moreRow(
        FluentIcons.puzzle_piece_24_regular,
        context.l10n.extensions,
        () => openLocalBrowseSettings(context, services),
      ),
      _moreRow(
        FluentIcons.arrow_counterclockwise_24_regular,
        localText(context, 'Backup & Restore', 'Backup & Pulihkan'),
        () => openLocalBackups(context, services, onRestored: _refresh),
      ),
      Consumer(
        builder: (context, ref, _) => SettingsGroupRow(
          icon: FluentIcons.arrow_sync_24_regular,
          title: localText(context, 'Sync', 'Sinkronisasi'),
          subtitle: syncSummary(context, ref.watch(syncControllerProvider)),
          trailing: const Icon(FluentIcons.chevron_right_24_regular),
          onTap: () => openSyncSettings(context),
        ),
      ),
      _moreRow(
        FluentIcons.shield_lock_24_regular,
        context.l10n.securityAndPrivacy,
        () => openSecuritySettings(context),
      ),
      _moreRow(
        FluentIcons.data_trending_24_regular,
        context.l10n.readingInsights,
        () => openLocalReadingInsights(context, services),
      ),
      _moreRow(
        FluentIcons.arrow_download_24_regular,
        context.l10n.downloads,
        () => setState(() => _downloads = true),
      ),
      const SizedBox(height: 16),
      _moreRow(
        FluentIcons.share_ios_24_regular,
        localText(context, 'Share', 'Bagikan'),
        () => SharePlus.instance.share(
          ShareParams(uri: Uri.parse(KuchieLinks.project), title: 'Kuchie'),
        ),
      ),
      _moreRow(
        FluentIcons.question_circle_24_regular,
        context.l10n.help,
        () => openInAppWebView(context, '${KuchieLinks.project}#readme'),
      ),
      _moreRow(
        FluentIcons.info_24_regular,
        context.l10n.about,
        () => openLocalAbout(context),
      ),
    ],
  );

  Widget _moreRow(IconData icon, String title, VoidCallback onTap) =>
      SettingsGroupRow(
        icon: icon,
        title: title,
        trailing: const Icon(FluentIcons.chevron_right_24_regular),
        onTap: onTap,
      );

  /// The Downloads bar: title centred, clear queue and settings on the right.
  AppBar _downloadsBar(Widget? leading, LocalDownloadQueue? queue) {
    final l10n = context.l10n;
    return AppBar(
      leading: leading,
      centerTitle: true,
      title: Text(l10n.downloads),
      actions: [
        if (queue != null && queue.value.isNotEmpty)
          AppleGlassToolbarButton(
            id: 'clear-downloads',
            symbol: 'trash',
            label: l10n.confirmClearQueueTitle,
            fallbackIcon: FluentIcons.delete_24_regular,
            onPressed: () async {
              if (await localConfirm(
                context,
                l10n.confirmClearQueueTitle,
                l10n.confirmClearQueueMessage,
              )) {
                await _runQueue(queue.clear);
              }
            },
          ),
        AppleGlassToolbarButton(
          id: 'download-settings',
          symbol: 'gearshape',
          label: localText(context, 'Download settings', 'Setelan unduhan'),
          fallbackIcon: FluentIcons.settings_24_regular,
          onPressed: () => openLocalDownloadSettings(context),
        ),
      ],
    );
  }

  /// Opens the titles saved on this iPhone, newest download first.
  Future<void> _openRecentlyDownloaded(LocalCollectionServices services) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RecentlyDownloadedPage(
          load: () async => [
            for (final entry in await localSavedTitlesNewestFirst(
              services.catalog,
            ))
              (
                cover: _LocalCover(
                  services: services,
                  seriesId: entry.book.id,
                  book: entry.book,
                ),
                title: entry.book.title,
                chapters: entry.book.chapters.length,
                downloadedAt: entry.savedAt,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        _SeriesDetail(services: services, series: entry.book),
                  ),
                ),
                onLongPress: () => _deleteDownloads(services, entry.book),
              ),
          ],
        ),
      ),
    );
    _refresh();
  }

  Future<void> _chooseConcurrency() async {
    final preferences = LocalPreferences.instance;
    await preferences.load();
    if (!mounted) return;
    final chosen = await pickDownloadConcurrency(
      context,
      current: preferences.downloadConcurrency.value,
      max: LocalDownloadQueue.maxConcurrency,
      note: localText(
        context,
        'Some sources slow down or block many requests at once.',
        'Beberapa sumber melambat atau memblokir terlalu banyak permintaan '
            'sekaligus.',
      ),
    );
    if (chosen != null) await preferences.setDownloadConcurrency(chosen);
  }

  Widget _downloadsPage(LocalCollectionServices services) {
    final queue = services.downloads;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecentlyDownloadedRow(onTap: () => _openRecentlyDownloaded(services)),
        ListenableBuilder(
          listenable: Listenable.merge([
            queue,
            LocalPreferences.instance.downloadConcurrency,
          ]),
          builder: (context, _) => DownloadsQueueActions(
            running: queue.running,
            onToggle: queue.value.isEmpty
                ? null
                : () => _runQueue(
                    queue.running ? queue.pauseAll : queue.resumeAll,
                  ),
            concurrency: LocalPreferences.instance.downloadConcurrency.value,
            onConcurrency: _chooseConcurrency,
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: queue,
            builder: (context, jobs, _) => FutureBuilder<List<LocalSeries>>(
              future: _library,
              builder: (context, snapshot) {
                if (jobs.isEmpty) {
                  return Emoticons(title: context.l10n.noDownloads);
                }
                final byId = {
                  for (final book in snapshot.data ?? const <LocalSeries>[])
                    book.id: book,
                };
                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    scrollBottomInset(context),
                  ),
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return _QueueRow(
                      services: services,
                      queue: queue,
                      job: job,
                      book: byId[job.request.seriesId],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Deletes every saved chapter of [book] from this iPhone.
  Future<bool> _deleteDownloads(
    LocalCollectionServices services,
    LocalSeries book,
  ) async {
    unawaited(HapticFeedback.mediumImpact());
    if (!await localConfirm(
          context,
          localText(context, 'Delete all downloads?', 'Hapus semua unduhan?'),
          localText(
            context,
            '${book.chapters.length} chapters of ${book.title} will be '
                'removed from this iPhone.',
            '${book.chapters.length} chapter ${book.title} akan dihapus dari '
                'iPhone ini.',
          ),
        ) ||
        !mounted) {
      return false;
    }
    try {
      for (final chapter in book.chapters) {
        await services.catalog.removeChapter(book.id, chapter.id);
      }
    } catch (error) {
      if (mounted) localFailure(context, error);
      return false;
    } finally {
      _refresh();
    }
    return true;
  }
}

/// A title's cover: the reader's own, the saved source cover, the first
/// saved page, then the source's link.
class _LocalCover extends StatelessWidget {
  const _LocalCover({
    required this.services,
    required this.seriesId,
    this.book,
    this.remote,
  });

  final LocalCollectionServices services;
  final String seriesId;
  final LocalSeries? book;
  final Uri? remote;

  static const _width = 44.0;
  static const _height = 62.0;

  @override
  Widget build(BuildContext context) {
    final file =
        book?.customCover ??
        services.catalog.keptCover(seriesId) ??
        book?.chapters.firstOrNull?.pages.firstOrNull;
    final link = remote ?? book?.source?.cover;
    final cacheWidth = (_width * MediaQuery.devicePixelRatioOf(context))
        .round();
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.book_outlined),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _width,
        height: _height,
        child: file != null
            ? Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                errorBuilder: (_, _, _) => placeholder,
              )
            : link != null
            ? Image.network(
                link.toString(),
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                errorBuilder: (_, _, _) => placeholder,
              )
            : placeholder,
      ),
    );
  }
}

/// A centered spinner over the page that blocks taps until removed.
OverlayEntry _showOpening(BuildContext context) {
  final entry = OverlayEntry(
    builder: (context) => ColoredBox(
      color: Theme.of(context).colorScheme.scrim.withValues(alpha: .26),
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  localText(context, 'Opening chapter…', 'Membuka chapter…'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return entry;
}

Future<bool> _importManga(
  BuildContext context,
  LocalCatalog catalog, {
  String? seriesId,
}) async {
  // The Darwin picker imports both types as copies, so Files providers retain
  // ownership of the originals and no security-scoped bookmark is needed.
  final paths = await FilePicker.pickFileAndDirectoryPaths();
  if (paths.isEmpty || !context.mounted) return false;
  for (final path in paths) {
    if (await FileSystemEntity.type(path) == FileSystemEntityType.directory) {
      await catalog.importFolder(Directory(path), seriesId: seriesId);
    } else {
      await catalog.importArchive(File(path), seriesId: seriesId);
    }
  }
  return true;
}

void _showImportSuccess(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(localText(context, 'Import complete.', 'Impor selesai.')),
    ),
    snackBarAnimationStyle: context.snackBarMotionStyle,
  );
}

Future<void> _openReader(
  BuildContext context,
  LocalCollectionServices services,
  LocalSeries series,
  LocalChapter chapter,
) => openSavedLocalChapter(context, services, series, chapter);

class _LocalEmpty extends StatelessWidget {
  const _LocalEmpty({
    required this.icon,
    required this.title,
    this.message,
    this.actions = const [],
    this.illustration,
  });

  final IconData icon;
  final Widget? illustration;
  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          illustration ??
              Icon(
                icon,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.textTheme.titleLarge,
          ),
          if (message case final text?) ...[
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
          ],
          if (actions.isNotEmpty) const SizedBox(height: 20),
          ...actions,
        ],
      ),
    ),
  );
}

class _LocalBooks extends StatefulWidget {
  const _LocalBooks({
    required this.books,
    required this.services,
    required this.categoryRevision,
    required this.empty,
    required this.onOpen,
    this.lastOnlineRead = const {},
  });

  final List<LocalSeries> books;
  final Map<String, DateTime> lastOnlineRead;
  final LocalCollectionServices services;
  final int categoryRevision;
  final Widget empty;
  final ValueChanged<LocalSeries> onOpen;

  @override
  State<_LocalBooks> createState() => _LocalBooksState();
}

class _LocalBooksState extends State<_LocalBooks> {
  String? _category;
  late Future<List<String>> _categories = widget.services.catalog.categories();

  @override
  void initState() {
    super.initState();
    unawaited(LocalPreferences.instance.load());
  }

  @override
  void didUpdateWidget(covariant _LocalBooks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.categoryRevision != oldWidget.categoryRevision ||
        widget.services != oldWidget.services) {
      _categories = widget.services.catalog.categories();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LocalPreferences.instance.library,
    builder: (context, _) => _build(context),
  );

  int _unread(LocalSeries book) =>
      book.chapters.where((chapter) => chapter.lastReadAt == null).length;

  /// Custom cover, then the kept source cover, the source link, and the first
  /// saved page offline or when a source has none.
  ImageProvider? _cover(LocalSeries book) {
    if (book.customCover case final custom?) return FileImage(custom);
    if (widget.services.catalog.keptCover(book.id) case final kept?) {
      return FileImage(kept);
    }
    if (book.source?.cover case final remote?) {
      return NetworkImage(remote.toString());
    }
    final firstPage = book.chapters.firstOrNull?.pages.firstOrNull;
    return firstPage == null ? null : FileImage(firstPage);
  }

  /// The library after the Filter and Sort choices.
  List<LocalSeries> _arranged() {
    final preferences = LocalPreferences.instance;
    // Worked out once per title, not on every comparison while sorting.
    final unreadCounts = <String, int>{};
    final lastReads = <String, DateTime?>{};
    int unread(LocalSeries book) => unreadCounts[book.id] ??= _unread(book);
    DateTime? lastRead(LocalSeries book) {
      if (lastReads.containsKey(book.id)) return lastReads[book.id];
      DateTime? latest = widget.lastOnlineRead[book.id];
      for (final chapter in book.chapters) {
        final at = chapter.lastReadAt;
        if (at != null && (latest == null || at.isAfter(latest))) latest = at;
      }
      return lastReads[book.id] = latest;
    }

    final books = [
      for (final book in widget.books)
        if ((!preferences.filterUnread.value || unread(book) > 0) &&
            (!preferences.filterDownloaded.value || book.chapters.isNotEmpty))
          book,
    ];
    int byTitle(LocalSeries a, LocalSeries b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase());
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final compare = switch (preferences.sort.value) {
      LocalLibrarySort.alphabetical => byTitle,
      // Most recent, most unread and longest first, like Tachimanga.
      LocalLibrarySort.lastRead =>
        (LocalSeries a, LocalSeries b) =>
            (lastRead(b) ?? epoch).compareTo(lastRead(a) ?? epoch),
      LocalLibrarySort.unread => (LocalSeries a, LocalSeries b) => unread(
        b,
      ).compareTo(unread(a)),
      LocalLibrarySort.totalChapters =>
        (LocalSeries a, LocalSeries b) =>
            b.chapters.length.compareTo(a.chapters.length),
    };
    books.sort((a, b) {
      final result = compare(a, b);
      return result != 0 ? result : byTitle(a, b);
    });
    return preferences.sortDescending.value ? books.reversed.toList() : books;
  }

  Widget _build(BuildContext context) => FutureBuilder<List<String>>(
    future: _categories,
    builder: (context, snapshot) {
      final categories = snapshot.data ?? const <String>[];
      final preferences = LocalPreferences.instance;
      final visible = [
        for (final book in _arranged())
          if (_category == null || book.categories.contains(_category)) book,
      ];
      final glass = supportsAppleGlass(context);
      // Clears the floating tab bar and the home indicator on every phone.
      final dockInset = scrollBottomInset(context, extra: 8);
      final content = Builder(
        builder: (context) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: AppleGlassFloatingHeader.insetOf(context),
              ),
            ),
            if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _category == null
                    ? widget.empty
                    : _LocalEmpty(
                        icon: Icons.folder_open_outlined,
                        title: localText(
                          context,
                          'No manga in this category',
                          'Belum ada manga di kategori ini',
                        ),
                      ),
              )
            else if (preferences.display.value == LocalLibraryDisplay.list)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, dockInset),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final book = visible[index];
                    final unread = _unread(book);
                    return ListTile(
                      key: ValueKey(book.id),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 62,
                          child: switch (_cover(book)) {
                            // Decoded at row size, not the source's full size.
                            final image? => Image(
                              image: ResizeImage.resizeIfNeeded(
                                (44 * MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                                null,
                                image,
                              ),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.book_outlined),
                            ),
                            null => const Icon(Icons.book_outlined),
                          },
                        ),
                      ),
                      title: Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          ?book.source?.sourceName,
                          if (book.chapters.isNotEmpty)
                            localText(
                              context,
                              '${book.chapters.length} saved',
                              '${book.chapters.length} tersimpan',
                            ),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: preferences.unreadBadges.value && unread > 0
                          ? _CountPill(
                              count: unread,
                              color: Theme.of(context).colorScheme.primary,
                              onColor: Theme.of(context).colorScheme.onPrimary,
                            )
                          : null,
                      onTap: () => widget.onOpen(book),
                    );
                  },
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, dockInset),
                sliver: SliverGrid.builder(
                  gridDelegate:
                      MediaQuery.orientationOf(context) == Orientation.portrait
                      ? MangaCoverFixedCountGridDelegate(
                          crossAxisCount: preferences.gridColumns.value,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        )
                      : const MangaCoverGridDelegate(minCrossAxisExtent: 158),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final book = visible[index];
                    final firstPage =
                        book.chapters.firstOrNull?.pages.firstOrNull;
                    final pageImage = firstPage == null
                        ? null
                        : FileImage(firstPage);
                    final saved = book.chapters.length;
                    return Stack(
                      key: ValueKey(book.id),
                      fit: StackFit.expand,
                      children: [
                        MangaCoverGridTile(
                          titleOverride: book.title,
                          coverImage: _cover(book),
                          fallbackCoverImage: pageImage,
                          badgeCountOverride: preferences.unreadBadges.value
                              ? _unread(book)
                              : 0,
                          showDarkOverlay: false,
                          outlineOnCovers: true,
                          borderRadius: glass
                              ? const BorderRadius.all(Radius.circular(18))
                              : null,
                          onPressed: () => widget.onOpen(book),
                        ),
                        // Saved chapters, beside the unread count as in
                        // Tachimanga.
                        if (preferences.downloadedBadges.value && saved > 0)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IgnorePointer(
                              child: _CountPill(
                                count: saved,
                                color: Theme.of(context).colorScheme.tertiary,
                                onColor: Theme.of(
                                  context,
                                ).colorScheme.onTertiary,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      );
      if (categories.isEmpty) return content;
      String label(String name, int count) =>
          preferences.categoryCounts.value ? '$name ($count)' : name;
      final labels = [
        label(context.l10n.all, widget.books.length),
        for (final name in categories)
          label(
            name,
            widget.books.where((book) => book.categories.contains(name)).length,
          ),
      ];
      final track = AppleGlassSegments(
        labels: labels,
        selectedIndex: categories.indexOf(_category ?? '') + 1,
        onSelected: (index) => setState(() {
          _category = index == 0 ? null : categories[index - 1];
        }),
        scrollable: true,
        fallback: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              spacing: 8,
              children: [
                for (final (index, label) in labels.indexed)
                  ChoiceChip(
                    label: Text(label),
                    selected: index == categories.indexOf(_category ?? '') + 1,
                    onSelected: (_) => setState(() {
                      _category = index == 0 ? null : categories[index - 1];
                    }),
                  ),
              ],
            ),
          ),
        ),
      );
      if (!AppleGlassFloatingHeader.enabled(context)) {
        return Column(
          children: [
            track,
            Expanded(child: content),
          ],
        );
      }
      return AppleGlassFloatingHeader.overlay(header: track, child: content);
    },
  );
}

class _LocalHistoryRow extends StatelessWidget {
  const _LocalHistoryRow({
    required this.book,
    required this.chapter,
    required this.keptCover,
    required this.onOpen,
    required this.onOpenManga,
    required this.onRemove,
    this.readingTime = Duration.zero,
  });

  final VoidCallback onRemove;

  /// Time spent reading this series.
  final Duration readingTime;
  final LocalSeries book;
  final LocalChapter chapter;

  /// The source cover saved on this iPhone, when there is one.
  final File? keptCover;
  final VoidCallback onOpen;
  final VoidCallback onOpenManga;

  Future<void> _actions(BuildContext context) async {
    unawaited(HapticFeedback.selectionClick());
    final choice = await showAppBottomSheet<String>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(title: book.title),
          ListTile(
            leading: const Icon(FluentIcons.book_open_24_regular),
            title: Text(sheet.l10n.viewManga),
            onTap: () => Navigator.pop(sheet, 'manga'),
          ),
          ListTile(
            leading: const Icon(FluentIcons.play_24_regular),
            title: Text(localText(sheet, 'Continue reading', 'Lanjut baca')),
            onTap: () => Navigator.pop(sheet, 'read'),
          ),
          ListTile(
            leading: const Icon(FluentIcons.delete_24_regular),
            title: Text(
              localText(sheet, 'Remove from history', 'Hapus dari riwayat'),
            ),
            onTap: () => Navigator.pop(sheet, 'remove'),
          ),
          SizedBox(height: MediaQuery.paddingOf(sheet).bottom),
        ],
      ),
    );
    switch (choice) {
      case 'manga':
        onOpenManga();
      case 'read':
        onOpen();
      case 'remove':
        onRemove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cover =
        book.customCover ??
        keptCover ??
        book.chapters.firstOrNull?.pages.firstOrNull;
    // Chapters read online have no saved pages to show.
    final remoteCover = book.source?.cover;
    return HistoryRowView(
      cover: (size) {
        final cacheWidth = (size.width * MediaQuery.devicePixelRatioOf(context))
            .round();
        final placeholder = SizedBox.fromSize(
          size: size,
          child: const Icon(Icons.book_outlined),
        );
        return cover != null
            ? Image.file(
                cover,
                width: size.width,
                height: size.height,
                cacheWidth: cacheWidth,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              )
            : remoteCover != null
            ? Image.network(
                remoteCover.toString(),
                width: size.width,
                height: size.height,
                cacheWidth: cacheWidth,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              )
            : placeholder;
      },
      seriesTitle: book.title,
      chapterTitle: chapter.title,
      readAt: chapter.lastReadAt,
      readingTime: readingTime,
      // Like Tachimanga: the row opens the series; resuming is in the sheet.
      onTap: onOpenManga,
      onLongPress: () => _actions(context),
      onRemove: onRemove,
    );
  }
}

class _SeriesDetail extends StatefulWidget {
  const _SeriesDetail({required this.services, required this.series});

  final LocalCollectionServices services;
  final LocalSeries series;

  @override
  State<_SeriesDetail> createState() => _SeriesDetailState();
}

class _SeriesDetailState extends State<_SeriesDetail> {
  late LocalSeries _series = widget.series;
  bool _busy = false;
  LocalCatalog get _catalog => widget.services.catalog;

  Future<void> _refresh() async {
    final current = await _catalog.find(_series.id);
    if (!mounted) return;
    if (current == null) {
      Navigator.pop(context);
    } else {
      setState(() => _series = current);
    }
  }

  Future<void> _modify(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      await _refresh();
    } catch (error) {
      if (mounted) localFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final name = await localInput(
      context,
      localText(context, 'Rename manga', 'Ubah judul manga'),
      localText(context, 'Title', 'Judul'),
      initial: _series.title,
    );
    if (name != null && mounted) {
      await _modify(() => _catalog.renameSeries(_series.id, name));
    }
  }

  Future<void> _editCover() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    final path = picked?.path;
    if (path == null || !mounted) return;
    await _modify(() => _catalog.setCover(_series.id, File(path)));
  }

  Future<void> _categoryPicker() async {
    final changed = await showLocalCategoryPicker(
      context,
      _catalog,
      seriesId: _series.id,
      current: _series.categories,
    );
    if (changed && mounted) await _refresh();
  }

  Future<void> _read(LocalChapter chapter) async {
    await _openReader(context, widget.services, _series, chapter);
    if (mounted) await _refresh();
  }

  Future<void> _importChapter() => _modify(() async {
    final imported = await _importManga(
      context,
      _catalog,
      seriesId: _series.id,
    );
    if (imported && mounted) _showImportSuccess(context);
  });

  @override
  Widget build(BuildContext context) {
    final cover =
        _series.customCover ?? _series.chapters.firstOrNull?.pages.firstOrNull;
    final reading = [..._series.chapters]
      ..sort((a, b) {
        final left = a.lastReadAt?.millisecondsSinceEpoch ?? 0;
        final right = b.lastReadAt?.millisecondsSinceEpoch ?? 0;
        return right.compareTo(left);
      });
    final chapter = reading.firstOrNull;
    return Scaffold(
      appBar: detailNavigationAppBar(
        context,
        title: const SizedBox.shrink(),
        actions: [
          AppleGlassToolbar(
            joined: true,
            actions: [
              AppleGlassToolbarAction(
                id: 'local-import-chapter',
                symbol: 'square.and.arrow.down',
                label: localText(context, 'Import chapter', 'Impor chapter'),
                fallbackIcon: Icons.playlist_add_rounded,
                onPressed: _busy ? null : _importChapter,
              ),
              AppleGlassToolbarAction(
                id: 'local-series-options',
                symbol: 'ellipsis',
                label: context.l10n.more,
                fallbackIcon: Icons.more_horiz,
                onPressed: null,
                menu: [
                  AppleGlassToolbarMenuItem(
                    id: 'rename',
                    title: localText(
                      context,
                      'Rename manga',
                      'Ubah judul manga',
                    ),
                    symbol: 'pencil',
                    fallbackIcon: Icons.edit_outlined,
                    onSelected: _rename,
                  ),
                  AppleGlassToolbarMenuItem(
                    id: 'categories',
                    title: localText(context, 'Categories', 'Kategori'),
                    symbol: 'folder',
                    fallbackIcon: Icons.folder_outlined,
                    onSelected: _categoryPicker,
                  ),
                  AppleGlassToolbarMenuItem(
                    id: 'edit-cover',
                    title: context.l10n.editCover,
                    symbol: 'photo',
                    fallbackIcon: Icons.image_outlined,
                    onSelected: _editCover,
                  ),
                  if (_series.customCover != null)
                    AppleGlassToolbarMenuItem(
                      id: 'reset-cover',
                      title: localText(
                        context,
                        'Use first page',
                        'Pakai halaman pertama',
                      ),
                      symbol: 'arrow.uturn.backward',
                      fallbackIcon: Icons.undo,
                      onSelected: () =>
                          _modify(() => _catalog.setCover(_series.id, null)),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          if (_busy) const LinearProgressIndicator(),
          LocalMangaHero(
            title: _series.title,
            source: context.l10n.downloadsOnDeviceTab,
            cover: cover == null ? null : FileImage(cover),
          ),
          LocalSeriesPersonal(
            catalog: _catalog,
            seriesId: _series.id,
            categories: _series.categories,
            onCategoriesChanged: _refresh,
          ),
          if (chapter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: FilledButton(
                onPressed: () => _read(chapter),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(
                  chapter.lastReadAt == null
                      ? chapter.title
                      : '${context.l10n.resume} ${chapter.title}',
                ),
              ),
            ),
          ListTile(
            title: Text(context.l10n.noOfChapters(_series.chapters.length)),
          ),
          for (final chapter in _series.chapters)
            ChapterRowView(
              key: ValueKey('saved-chapter-${chapter.id}'),
              title: chapter.title,
              isRead:
                  chapter.lastReadAt != null &&
                  chapter.progress >= chapter.pages.length - 1,
              isBookmarked: chapter.bookmarked,
              lastPageRead: chapter.progress,
              isSelected: false,
              date: chapter.lastReadAt == null
                  ? null
                  : MaterialLocalizations.of(
                      context,
                    ).formatShortDate(chapter.lastReadAt!),
              extra: localText(
                context,
                '${chapter.pages.length} pages',
                '${chapter.pages.length} halaman',
              ),
              onTap: () => _read(chapter),
              trailing: IconButton(
                tooltip: localText(context, 'Delete chapter', 'Hapus chapter'),
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy
                    ? null
                    : () async {
                        if (await localConfirm(
                              context,
                              localText(
                                context,
                                'Delete from this iPhone?',
                                'Hapus dari iPhone ini?',
                              ),
                              chapter.title,
                            ) &&
                            mounted) {
                          await _modify(
                            () =>
                                _catalog.removeChapter(_series.id, chapter.id),
                          );
                        }
                      },
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.services,
    required this.queue,
    required this.job,
    this.book,
  });

  final LocalCollectionServices services;
  final LocalDownloadQueue queue;
  final LocalDownload job;

  /// The title in this iPhone's catalog, for its custom cover.
  final LocalSeries? book;

  @override
  Widget build(BuildContext context) {
    final request = job.request;
    final active =
        job.state == LocalDownloadState.queued ||
        job.state == LocalDownloadState.downloading;
    final status = switch (job.state) {
      LocalDownloadState.queued => localText(
        context,
        'Queued',
        'Dalam antrean',
      ),
      LocalDownloadState.downloading => localText(
        context,
        'Downloading',
        'Mengunduh',
      ),
      LocalDownloadState.paused => localText(context, 'Paused', 'Dijeda'),
      LocalDownloadState.failed => localText(context, 'Failed', 'Gagal'),
    };
    Future<void> action(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (error) {
        if (context.mounted) localFailure(context, error);
      }
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: _LocalCover(
        services: services,
        seriesId: request.seriesId,
        book: book,
        remote: request.source?.cover,
      ),
      title: Text(request.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            job.pageCount == 0
                ? '${request.chapterTitle} · $status'
                : '${request.chapterTitle} · $status · ${job.done}/${job.pageCount}',
          ),
          if (active)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: job.pageCount == 0 ? null : job.done / job.pageCount,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: active
                ? localText(context, 'Pause', 'Jeda')
                : localText(context, 'Resume', 'Lanjutkan'),
            icon: Icon(active ? Icons.pause : Icons.play_arrow),
            onPressed: () => action(
              () => active
                  ? queue.pause(request.seriesId, request.chapterId)
                  : queue.resume(request.seriesId, request.chapterId),
            ),
          ),
          IconButton(
            tooltip: localText(context, 'Remove download', 'Hapus unduhan'),
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (await localConfirm(
                    context,
                    localText(
                      context,
                      'Remove from queue?',
                      'Hapus dari antrean?',
                    ),
                    request.chapterTitle,
                  ) &&
                  context.mounted) {
                await action(
                  () => queue.remove(request.seriesId, request.chapterId),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _LocalUpdates extends StatefulWidget {
  const _LocalUpdates({required this.services, required this.library});

  final LocalCollectionServices services;
  final List<LocalSeries> library;

  @override
  State<_LocalUpdates> createState() => _LocalUpdatesState();
}

class _LocalUpdatesState extends State<_LocalUpdates> {
  late var _updates = _load();

  static const _baseline = PreferencesUpdateBaseline();

  Future<({List<LocalMangaUpdate> items, int failed})> _load() =>
      loadLocalUpdates(
        widget.services.sources,
        widget.library,
        baseline: _baseline,
        readChapters: (seriesId) async => {
          for (final MapEntry(:key, :value)
              in (await widget.services.catalog.chapterMarks(seriesId)).entries)
            if (value.read) key,
        },
      );

  @override
  void didUpdateWidget(_LocalUpdates oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.library != oldWidget.library) _updates = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _updates,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(() {
              _updates = _load();
            }),
            child: Text(context.l10n.retry),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final (items: updates, :failed) = snapshot.requireData;
      if (updates.isEmpty) {
        return _LocalEmpty(
          icon: Icons.bolt_outlined,
          title: failed == 0
              ? localText(
                  context,
                  'No new local chapters',
                  'Belum ada chapter lokal baru',
                )
              : localText(
                  context,
                  'Could not check updates',
                  'Pembaruan gagal diperiksa',
                ),
          message: failed == 0
              ? localText(
                  context,
                  'For manga from Files, add chapters from its Library page.',
                  'Untuk manga dari File, tambahkan chapter dari halaman judul di Perpustakaan.',
                )
              : null,
          actions: [
            TextButton(
              onPressed: () => setState(() {
                _updates = _load();
              }),
              child: Text(context.l10n.refresh),
            ),
          ],
        );
      }
      // Tachimanga's Updates: a summary banner, then every new chapter.
      final rows = [
        for (final update in updates)
          for (final chapter in update.newChapters) (update, chapter),
      ];
      return RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _updates = _load();
          });
          await _updates;
        },
        child: ListView.builder(
          padding: EdgeInsets.only(bottom: scrollBottomInset(context)),
          itemCount: rows.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _UpdateSummaryBanner(
                updates: updates,
                failed: failed,
                onRetry: () => setState(() => _updates = _load()),
              );
            }
            if (index == 1) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  DateGroupKeys.today.toLocale(context),
                  style: context.textTheme.titleSmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            final (update, chapter) = rows[index - 2];
            return _UpdateChapterRow(
              key: ValueKey('${update.seriesId}/${chapter.id}'),
              services: widget.services,
              update: update,
              chapter: chapter,
              onOpen: () async {
                // Opening the title marks its new chapters as seen.
                await _baseline.write(update.seriesId, update.chapterIds);
                if (!context.mounted) return;
                await openLocalSourceManga(
                  context,
                  widget.services,
                  update.source,
                  update.manga,
                );
                if (mounted) setState(() => _updates = _load());
              },
            );
          },
        ),
      );
    },
  );
}

/// "Update completed. N titles, M chapters, F failed", with the summary.
class _UpdateSummaryBanner extends StatelessWidget {
  const _UpdateSummaryBanner({
    required this.updates,
    required this.failed,
    required this.onRetry,
  });

  final List<LocalMangaUpdate> updates;
  final int failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final chapters = updates.fold<int>(0, (sum, u) => sum + u.count);
    final cs = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          leading: Icon(
            failed == 0
                ? FluentIcons.checkmark_circle_24_regular
                : FluentIcons.warning_24_regular,
            color: failed == 0 ? cs.primary : cs.error,
          ),
          title: Text(
            localText(context, 'Update completed', 'Pembaruan selesai'),
          ),
          subtitle: Text(
            localText(
              context,
              '${updates.length} titles · $chapters new chapters · $failed failed',
              '${updates.length} judul · $chapters chapter baru · $failed gagal',
            ),
          ),
          trailing: IconButton(
            tooltip: localText(context, 'Summary', 'Ringkasan'),
            icon: const Icon(FluentIcons.info_24_regular),
            onPressed: () => showAppBottomSheet<void>(
              context: context,
              builder: (sheet) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: .6,
                builder: (sheet, controller) => ListView(
                  controller: controller,
                  children: [
                    AppSheetHeader(
                      title: localText(
                        sheet,
                        'Updates summary',
                        'Ringkasan pembaruan',
                      ),
                    ),
                    ExpansionTile(
                      initiallyExpanded: true,
                      leading: const Icon(
                        FluentIcons.checkmark_circle_24_regular,
                      ),
                      title: Text(
                        localText(
                          sheet,
                          'Completed (${updates.length})',
                          'Selesai (${updates.length})',
                        ),
                      ),
                      children: [
                        for (final update in updates)
                          ListTile(
                            dense: true,
                            title: Text(update.manga.title),
                            trailing: Text('+${update.count}'),
                          ),
                      ],
                    ),
                    ListTile(
                      leading: const Icon(FluentIcons.warning_24_regular),
                      title: Text(
                        localText(sheet, 'Failed ($failed)', 'Gagal ($failed)'),
                      ),
                      trailing: failed == 0
                          ? null
                          : TextButton(
                              onPressed: () {
                                Navigator.pop(sheet);
                                onRetry();
                              },
                              child: Text(sheet.l10n.retry),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One new chapter: cover, title, chapter and a save button.
class _UpdateChapterRow extends StatefulWidget {
  const _UpdateChapterRow({
    super.key,
    required this.services,
    required this.update,
    required this.chapter,
    required this.onOpen,
  });

  final LocalCollectionServices services;
  final LocalMangaUpdate update;
  final LocalSourceChapter chapter;
  final VoidCallback onOpen;

  @override
  State<_UpdateChapterRow> createState() => _UpdateChapterRowState();
}

class _UpdateChapterRowState extends State<_UpdateChapterRow> {
  bool _queued = false;

  Future<void> _save() async {
    if (_queued) return;
    setState(() => _queued = true);
    try {
      await enqueueLocalChapterDownload(
        widget.services,
        widget.update.source,
        widget.update.manga,
        widget.update.seriesId,
        widget.chapter,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _queued = false);
        localFailure(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    final kept = widget.services.catalog.keptCover(update.seriesId);
    final cover = update.manga.cover;
    final cacheWidth = (40 * MediaQuery.devicePixelRatioOf(context)).round();
    return ListTile(
      onTap: widget.onOpen,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 40,
          height: 40,
          child: kept != null
              ? Image.file(kept, fit: BoxFit.cover, cacheWidth: cacheWidth)
              : cover != null
              ? Image.network(
                  cover.toString(),
                  headers: update.manga.coverHeaders,
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
                  errorBuilder: (_, _, _) => const Icon(Icons.book_outlined),
                )
              : const Icon(Icons.book_outlined),
        ),
      ),
      title: Text(
        update.manga.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        widget.chapter.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: localText(context, 'Save to device', 'Simpan ke perangkat'),
        onPressed: _queued ? null : _save,
        icon: Icon(
          _queued
              ? FluentIcons.arrow_download_24_filled
              : FluentIcons.arrow_circle_down_24_regular,
        ),
      ),
    );
  }
}

/// A small rounded count, as on Tachimanga's library covers.
class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.count,
    required this.color,
    required this.onColor,
  });

  final int count;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: onColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
