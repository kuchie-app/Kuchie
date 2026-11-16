import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/navigation_bar_data.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/ios/apple_glass_capability.dart';
import '../../../widgets/ios/apple_glass_floating_header.dart';
import '../../../widgets/ios/apple_glass_search.dart';
import '../../../widgets/ios/apple_glass_segments.dart';
import '../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../widgets/ios/apple_page_title.dart';
import '../../../widgets/kuchie_character_motion.dart';
import '../../../widgets/kuchie_motion_reveal.dart';
import '../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../widgets/shell/apple_liquid_glass_tab_bar.dart';
import '../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../onboarding/data/collection_mode.dart';
import '../../onboarding/presentation/collection_mode_picker.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../data/local_catalog.dart';
import '../data/local_collection_providers.dart';
import '../data/local_collection_services.dart';
import '../data/local_download_queue.dart';
import '../data/local_history.dart';
import '../data/local_sources.dart';
import '../data/local_updates.dart';
import 'local_extension_browser.dart';
import 'local_series_personal.dart';
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
  bool _reverseSort = false;
  int _categoryRevision = 0;
  bool _showSavedDownloads = false;
  bool _openingManga = false;
  final _query = TextEditingController();
  final _searchFocus = FocusNode();

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
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _bind(LocalCollectionServices services) {
    if (identical(_bound, services)) return;
    _bound?.downloads.completed.removeListener(_refresh);
    _bound = services;
    _library = services.catalog.list();
    _remoteReads = services.catalog.remoteHistory();
    services.downloads.completed.addListener(_refresh);
  }

  void _refresh() {
    final services = _bound;
    if (services != null && mounted) {
      setState(() {
        _library = services.catalog.list();
        _remoteReads = services.catalog.remoteHistory();
      });
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
      _remoteReads = services.catalog.remoteHistory();
    }
    _tab = index;
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
    return Scaffold(
      extendBody: supportsAppleGlass(context) && !_downloads,
      appBar: browse
          ? null
          : AppBar(
              centerTitle: _tab == 4 && !_downloads ? true : false,
              title: library
                  ? CollectionModePageTitle(
                      title,
                      mode: CollectionMode.local,
                      onPressed: _chooseMode,
                    )
                  : _tab == 4 && !_downloads
                  ? Text(title)
                  : ApplePageTitle(title),
              leading: _downloads
                  ? BackButton(
                      onPressed: () => setState(() => _downloads = false),
                    )
                  : null,
              bottom: _searching && (library || history)
                  ? _searchBar(
                      library ? l10n.searchLibraryHint : l10n.searchHistory,
                    )
                  : _downloads
                  ? _downloadsTabs()
                  : null,
              actions: [
                if (library || history) _searchButton(),
                if (library)
                  AppleGlassToolbarButton(
                    id: 'organize-library',
                    symbol: 'line.3.horizontal.decrease',
                    label: l10n.filter,
                    fallbackIcon: FluentIcons.filter_24_regular,
                    onPressed: null,
                    menu: [
                      AppleGlassToolbarMenuItem(
                        id: 'sort-ascending',
                        title: localText(context, 'Title A–Z', 'Judul A–Z'),
                        symbol: 'arrow.up',
                        fallbackIcon: Icons.arrow_upward,
                        selected: !_reverseSort,
                        onSelected: () => setState(() => _reverseSort = false),
                      ),
                      AppleGlassToolbarMenuItem(
                        id: 'sort-descending',
                        title: localText(context, 'Title Z–A', 'Judul Z–A'),
                        symbol: 'arrow.down',
                        fallbackIcon: Icons.arrow_downward,
                        selected: _reverseSort,
                        onSelected: () => setState(() => _reverseSort = true),
                      ),
                    ],
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
              onRestoreBackup: () => _restoreBackup(services.catalog),
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
          : supportsAppleGlass(context)
          ? AppleLiquidGlassTabBar(
              tabs: tabs,
              selectedIndex: _tab,
              downloadsPaused: false,
              extensionUpdates: 0,
              onDestinationSelected: _select,
            )
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _select,
              destinations: [
                for (final tab in tabs)
                  NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.activeIcon),
                    label: tab.label(context),
                  ),
              ],
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
    final matching =
        library
            .where((book) => book.title.toLowerCase().contains(query))
            .toList()
          ..sort((a, b) {
            final result = a.title.toLowerCase().compareTo(
              b.title.toLowerCase(),
            );
            return _reverseSort ? -result : result;
          });
    return _LocalBooks(
      books: matching,
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

  Future<void> _openMangaDetail(
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
    if (!mounted) return;
    if (selection case final current?) {
      await openLocalSourceManga(
        context,
        services,
        current.extension,
        current.manga,
      );
    } else if (reference == null || book.chapters.isNotEmpty) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _SeriesDetail(services: services, series: book),
        ),
      );
    } else {
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
    final visible = [
      for (final item in read)
        if (item.book.title.toLowerCase().contains(query) ||
            item.chapter.title.toLowerCase().contains(query))
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      itemCount: visible.length,
      // State.context, so the post-await failure check matches `mounted`.
      itemBuilder: (_, index) {
        final entry = visible[index];
        return _LocalHistoryRow(
          book: entry.book,
          chapter: entry.chapter,
          onOpen: () async {
            try {
              if (entry.saved) {
                await _openReader(context, services, entry.book, entry.chapter);
              } else {
                await openRemoteLocalChapter(
                  context,
                  services,
                  series: entry.book,
                  chapterId: entry.chapter.id,
                );
              }
            } catch (error) {
              if (mounted) localFailure(context, error);
            }
            _refresh();
          },
          onOpenManga: () => _openManga(services, entry.book),
        );
      },
    );
  }

  Widget _more(LocalCollectionServices services) => ListView(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
    children: [
      SettingsGroupRow(
        icon: Icons.swap_horiz_rounded,
        title: collectionModeTitle(context),
        subtitle: collectionModeLabel(context, CollectionMode.local),
        trailing: const Icon(FluentIcons.chevron_right_24_regular),
        onTap: _chooseMode,
      ),
      const Divider(height: 16),
      _moreRow(
        FluentIcons.tag_24_regular,
        localText(context, 'Categories', 'Kategori'),
        () => _addCategory(services.catalog),
      ),
      _moreRow(
        FluentIcons.arrow_download_24_regular,
        context.l10n.downloads,
        () => setState(() => _downloads = true),
      ),
      _moreRow(
        FluentIcons.history_24_regular,
        context.l10n.history,
        () => _select(3),
      ),
      _moreRow(
        FluentIcons.arrow_counterclockwise_24_regular,
        context.l10n.backup,
        () => _backup(services.catalog),
      ),
      const SizedBox(height: 16),
      _moreRow(
        FluentIcons.color_24_regular,
        context.l10n.appearance,
        () => context.push<void>(localAppearanceLocation),
      ),
      _moreRow(
        FluentIcons.book_open_24_regular,
        context.l10n.reader,
        () => context.push<void>(localReaderSettingsLocation),
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

  PreferredSizeWidget _downloadsTabs() {
    final l10n = context.l10n;
    final labels = [
      localText(context, 'Queue', 'Antrean'),
      l10n.downloadsOnDeviceTab,
    ];
    void select(int index) => setState(() => _showSavedDownloads = index == 1);
    return AppleGlassSegments(
      labels: labels,
      selectedIndex: _showSavedDownloads ? 1 : 0,
      onSelected: select,
      fallback: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: Center(
          child: SegmentedButton<int>(
            segments: [
              for (final (index, label) in labels.indexed)
                ButtonSegment(value: index, label: Text(label)),
            ],
            selected: {_showSavedDownloads ? 1 : 0},
            onSelectionChanged: (selection) => select(selection.first),
          ),
        ),
      ),
    );
  }

  Future<void> _backup(LocalCatalog catalog) async {
    final exporting = await showAppBottomSheet<bool>(
      context: context,
      isScrollControlled: false,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(
            title: localText(sheet, 'Local backup', 'Cadangan lokal'),
          ),
          ListTile(
            title: Text(
              localText(
                sheet,
                'Includes saved titles, categories, bookmarks, and reading progress. Keep chapter files separately.',
                'Cadangan berisi judul tersimpan, kategori, penanda, dan progres baca. Simpan file chapter secara terpisah.',
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(localText(sheet, 'Export backup', 'Ekspor cadangan')),
            onTap: () => Navigator.pop(sheet, true),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: Text(
              localText(sheet, 'Restore backup', 'Pulihkan cadangan'),
            ),
            onTap: () => Navigator.pop(sheet, false),
          ),
        ],
      ),
    );
    if (exporting == null || !mounted) return;
    if (!exporting) {
      await _restoreBackup(catalog);
      return;
    }
    try {
      final directory = await Directory.systemTemp.createTemp('kuchie-backup-');
      try {
        final file = File('${directory.path}/kuchie-local.json');
        await catalog.exportMetadata(file);
        final bytes = await file.readAsBytes();
        if (mounted) {
          await FilePicker.saveFile(
            fileName: 'kuchie-local.json',
            bytes: bytes,
            mimeType: 'application/json',
          );
        }
      } finally {
        await directory.delete(recursive: true);
      }
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Future<void> _restoreBackup(LocalCatalog catalog) async {
    try {
      final file = await FilePicker.pickFile();
      if (file?.path case final path? when mounted) {
        final result = await catalog.restoreMetadata(File(path));
        if (!mounted) return;
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localText(
                context,
                '${result.restored} restored, ${result.skipped} chapters skipped',
                '${result.restored} dipulihkan, ${result.skipped} chapter dilewati',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Widget _downloadsPage(LocalCollectionServices services) =>
      ValueListenableBuilder(
        valueListenable: services.downloads,
        builder: (context, jobs, _) => FutureBuilder<List<LocalSeries>>(
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
            final chapters = _showSavedDownloads
                ? [
                    for (final book in snapshot.requireData)
                      for (final chapter in book.chapters) (book, chapter),
                  ]
                : null;
            final total = chapters?.length ?? jobs.length;
            if (total == 0) {
              return _LocalEmpty(
                icon: Icons.download_for_offline_outlined,
                title: context.l10n.noDownloads,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
              itemCount: total,
              itemBuilder: (context, index) {
                if (chapters == null) {
                  return _QueueRow(queue: services.downloads, job: jobs[index]);
                }
                final (book, chapter) = chapters[index];
                return ListTile(
                  leading: const Icon(Icons.download_done_outlined),
                  title: Text(book.title),
                  subtitle: Text(chapter.title),
                  onTap: () async {
                    await _openReader(context, services, book, chapter);
                    _refresh();
                  },
                );
              },
            );
          },
        ),
      );
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
  });

  final List<LocalSeries> books;
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
  void didUpdateWidget(covariant _LocalBooks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.categoryRevision != oldWidget.categoryRevision ||
        widget.services != oldWidget.services) {
      _categories = widget.services.catalog.categories();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _categories,
    builder: (context, snapshot) {
      final categories = snapshot.data ?? const <String>[];
      final visible = [
        for (final book in widget.books)
          if (_category == null || book.categories.contains(_category)) book,
      ];
      final glass = supportsAppleGlass(context);
      final dockInset = glass ? 96.0 : 8.0;
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
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, dockInset),
                sliver: SliverGrid.builder(
                  gridDelegate:
                      MediaQuery.orientationOf(context) ==
                              Orientation.portrait &&
                          glass
                      ? const MangaCoverFixedCountGridDelegate(
                          crossAxisCount: 2,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        )
                      : const MangaCoverGridDelegate(minCrossAxisExtent: 158),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final book = visible[index];
                    final firstPage =
                        book.chapters.firstOrNull?.pages.firstOrNull;
                    final remoteCover = book.source?.cover;
                    // The tile decodes at its own size; nesting ResizeImage fails.
                    final pageImage = firstPage == null
                        ? null
                        : FileImage(firstPage);
                    final remoteImage = remoteCover == null
                        ? null
                        : NetworkImage(remoteCover.toString());
                    final unreadCount = book.chapters
                        .where((chapter) => chapter.lastReadAt == null)
                        .length;
                    return MangaCoverGridTile(
                      key: ValueKey(book.id),
                      titleOverride: book.title,
                      // Custom cover, then the source cover; the first saved
                      // page stands in offline or when a source has none.
                      coverImage: switch (book.customCover) {
                        final custom? => FileImage(custom),
                        null => remoteImage ?? pageImage,
                      },
                      fallbackCoverImage: pageImage,
                      badgeCountOverride: unreadCount,
                      showDarkOverlay: false,
                      outlineOnCovers: true,
                      borderRadius: glass
                          ? const BorderRadius.all(Radius.circular(18))
                          : null,
                      onPressed: () => widget.onOpen(book),
                    );
                  },
                ),
              ),
          ],
        ),
      );
      if (categories.isEmpty) return content;
      final labels = [
        '${context.l10n.all} (${widget.books.length})',
        for (final name in categories)
          '$name (${widget.books.where((book) => book.categories.contains(name)).length})',
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
    required this.onOpen,
    required this.onOpenManga,
  });

  final LocalSeries book;
  final LocalChapter chapter;
  final VoidCallback onOpen;
  final VoidCallback onOpenManga;

  @override
  Widget build(BuildContext context) {
    final cover =
        book.customCover ?? book.chapters.firstOrNull?.pages.firstOrNull;
    // Chapters read online have no saved pages to show.
    final remoteCover = book.source?.cover;
    final glass = supportsAppleGlass(context);
    final width = glass ? 84.0 : 56.0;
    final height = glass ? 122.0 : 80.0;
    final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context)).round();
    final placeholder = SizedBox(
      width: width,
      height: height,
      child: const Icon(Icons.book_outlined),
    );
    final readAt = chapter.lastReadAt;
    return Card(
      margin: EdgeInsets.symmetric(horizontal: glass ? 0 : 4, vertical: 4),
      color: glass ? Colors.transparent : null,
      elevation: glass ? 0 : null,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: glass ? const EdgeInsets.all(4) : const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: glass
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(glass ? 12 : 8),
                child: cover != null
                    ? Image.file(
                        cover,
                        width: width,
                        height: height,
                        cacheWidth: cacheWidth,
                        fit: BoxFit.cover,
                      )
                    : remoteCover != null
                    ? Image.network(
                        remoteCover.toString(),
                        width: width,
                        height: height,
                        cacheWidth: cacheWidth,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => placeholder,
                      )
                    : placeholder,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style:
                          (glass
                                  ? context.textTheme.titleMedium
                                  : context.textTheme.titleSmall)
                              ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (readAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatShortDate(readAt),
                      ),
                    ],
                  ],
                ),
              ),
              AppleGlassToolbarButton(
                id: 'history-options',
                symbol: 'ellipsis',
                label: context.l10n.more,
                fallbackIcon: Icons.more_horiz,
                onPressed: null,
                menu: [
                  AppleGlassToolbarMenuItem(
                    id: 'view-manga',
                    title: context.l10n.viewManga,
                    symbol: 'books.vertical',
                    fallbackIcon: Icons.book_outlined,
                    onSelected: onOpenManga,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
            ListTile(
              leading: Icon(
                chapter.bookmarked ? Icons.bookmark : Icons.menu_book_outlined,
              ),
              title: Text(chapter.title),
              subtitle: Text(
                localText(
                  context,
                  '${chapter.pages.length} pages',
                  '${chapter.pages.length} halaman',
                ),
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
  const _QueueRow({required this.queue, required this.job});

  final LocalDownloadQueue queue;
  final LocalDownload job;

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
      title: Text(request.title),
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

  Future<({List<LocalMangaUpdate> items, int failed})> _load() =>
      loadLocalUpdates(widget.services.sources, widget.library);

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
      return RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _updates = _load();
          });
          await _updates;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
          itemCount: updates.length + (failed == 0 ? 0 : 1),
          itemBuilder: (context, index) {
            if (index == updates.length) {
              return ListTile(
                title: Text(
                  localText(
                    context,
                    'Some titles could not be checked',
                    'Beberapa judul gagal diperiksa',
                  ),
                ),
                trailing: TextButton(
                  onPressed: () => setState(() => _updates = _load()),
                  child: Text(context.l10n.retry),
                ),
              );
            }
            final update = updates[index];
            return ListTile(
              title: Text(update.manga.title),
              subtitle: Text(
                localText(
                  context,
                  '${update.count} new chapters',
                  '${update.count} chapter baru',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openLocalSourceManga(
                context,
                widget.services,
                update.source,
                update.manga,
              ),
            );
          },
        ),
      );
    },
  );
}
