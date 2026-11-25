import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../constants/language_list.dart';
import '../../../routes/reader_swipe_back_route.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/hooks/paging_controller_hook.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/custom_circular_progress_indicator.dart';
import '../../../widgets/desktop/desktop_top_bar.dart';
import '../../../widgets/emoticons.dart';
import '../../../widgets/in_app_web_view.dart';
import '../../../widgets/ios/apple_glass_capability.dart';
import '../../../widgets/ios/apple_glass_floating_header.dart';
import '../../../widgets/ios/apple_glass_popover.dart';
import '../../../widgets/ios/apple_glass_segments.dart';
import '../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../widgets/ios/apple_page_title.dart';
import '../../../widgets/ios/collapsing_title_scaffold.dart';
import '../../../widgets/kuchie_character_motion.dart';
import '../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import '../../../widgets/manga_cover/list/manga_cover_list_tile.dart';
import '../../../widgets/paging_footer.dart';
import '../../../widgets/popup_widgets/app_dialog.dart';
import '../../../widgets/pull_refresh_indicator.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/selection_action_bar.dart';
import '../../../widgets/server_image.dart';
import '../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../widgets/touch_tab_pager.dart';
import '../../browse_center/domain/filter/filter_model.dart';
import '../../browse_center/presentation/browse/browse_no_search_results.dart';
import '../../browse_center/presentation/extension/widgets/extension_catalog_tile.dart';
import '../../browse_center/presentation/extension/widgets/extension_info_content.dart';
import '../../browse_center/presentation/source/widgets/source_list_tile.dart';
import '../../browse_center/presentation/source_manga_list/widgets/source_manga_filter.dart';
import '../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../manga_book/presentation/manga_details/widgets/add_to_library_category.dart';
import '../../manga_book/presentation/manga_details/widgets/chapter_check_status.dart';
import '../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart'
    show ChapterMenuRow, menuAnchorForPoint;
import '../../manga_book/presentation/manga_details/widgets/chapter_grid_tile.dart';
import '../../manga_book/presentation/manga_details/widgets/chapter_list_mode_toggle.dart';
import '../../manga_book/presentation/manga_details/widgets/chapter_list_tile.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_action_button.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_cover_hero.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_description.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_details_app_bar.dart';
import '../../manga_book/presentation/reader/controller/auto_webtoon.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../data/local_browse_preferences.dart';
import '../data/local_catalog.dart';
import '../data/local_collection_services.dart';
import '../data/local_download_queue.dart';
import '../data/local_mihon_runtime.dart';
import '../data/local_network_settings.dart';
import '../data/local_sources.dart';
import '../data/package_catalog_index.dart';
import 'local_reader.dart';
import 'local_series_personal.dart';
import 'local_source_settings.dart';
import 'local_ui.dart';

typedef _SourceLists = ({
  List<LocalSourceRepository> repositories,
  List<LocalExtension> extensions,
  List<LocalExtension> sources,
});

const _coverRadius = BorderRadius.all(Radius.circular(18));

String _languageName(String code) => languageMap[code]?.displayName ?? code;

class LocalExtensionBrowser extends StatefulWidget {
  const LocalExtensionBrowser({
    super.key,
    required this.services,
    this.initialTab = 0,
    this.onImportManga,
    this.onRestoreBackup,
  });

  final LocalCollectionServices services;
  final int initialTab;
  final VoidCallback? onImportManga;
  final VoidCallback? onRestoreBackup;

  @override
  State<LocalExtensionBrowser> createState() => _LocalExtensionBrowserState();
}

class _LocalExtensionBrowserState extends State<LocalExtensionBrowser>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab,
  )..addListener(_tabChanged);
  late Future<_SourceLists> _lists = _load();
  _SourceLists? _loaded;
  String? _busyExtension;
  bool _searchSources = false;
  String _sourceQuery = '';
  String _extensionQuery = '';
  Set<String>? _languages;
  String? _lastUsed;
  final _pinned = <String>{};

  LocalSources get _sources => widget.services.sources;

  @override
  void initState() {
    super.initState();
    LocalBrowsePreferences.instance.showNsfw.addListener(_nsfwChanged);
    unawaited(LocalBrowsePreferences.instance.load());
    unawaited(_loadSourcePreferences());
    // Browse leads to installing or opening an extension; boot the runtime
    // now so neither waits for it.
    unawaited(_sources.warmUpRuntime(onlyIfInstalled: false));
  }

  Future<void> _loadSourcePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('localLastSource') case final lastUsed?) {
      unawaited(_sources.preloadRuntimeSources([lastUsed], limit: 1));
    }
    if (!mounted) return;
    setState(() {
      _pinned.addAll(prefs.getStringList('localPinnedSources') ?? const []);
      _lastUsed ??= prefs.getString('localLastSource');
      _languages ??= prefs.getStringList('localBrowseLanguages')?.toSet();
    });
  }

  @override
  void dispose() {
    LocalBrowsePreferences.instance.showNsfw.removeListener(_nsfwChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _tabChanged() => setState(() {});

  void _nsfwChanged() {
    if (mounted) setState(() {});
  }

  Future<_SourceLists> _load() async => (
    repositories: await _sources.repositories(),
    extensions: await _sources.extensions(),
    sources: await _sources.sources(),
  );

  void _reload() {
    final lists = _load();
    setState(() {
      _lists = lists;
    });
  }

  Future<void> _refresh() async {
    _reload();
    try {
      await _lists;
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Future<void> _perform(String id, Future<void> Function() action) async {
    if (_busyExtension != null) return;
    setState(() => _busyExtension = id);
    try {
      await action();
      if (mounted) _reload();
    } catch (error) {
      if (kDebugMode) {
        final detail = switch (error) {
          MihonRuntimeException() => '${error.message} (${error.statusCode})',
          FormatException() => error.message,
          HttpException() => error.message,
          _ => error.runtimeType.toString(),
        };
        debugPrint('Kuchie extension operation failed: $detail');
      }
      if (mounted) localFailure(context, error);
    } finally {
      if (mounted) setState(() => _busyExtension = null);
    }
  }

  Future<void> _openStores() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _LocalExtensionStores(sources: _sources),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _languages = null;
        _extensionQuery = '';
      });
      await prefs.remove('localBrowseLanguages');
    }
    if (mounted) await _refresh();
  }

  Future<void> _importFile() => _perform('import', () async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file?.path case final path?) await _sources.importFile(File(path));
  });

  void _openSource(LocalExtension extension, {bool latest = false}) {
    setState(() => _lastUsed = extension.id);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString('localLastSource', extension.id),
      ),
    );
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _LocalSourcePage(
            services: widget.services,
            extension: extension,
            latest: latest,
          ),
        ),
      ),
    );
  }

  /// Store packages newer than what is installed, honouring the 18+ choice.
  // Grouping the whole store is not free; recount only when it changes.
  (_SourceLists, bool, List<LocalSourcePackage>)? _pendingCache;

  List<LocalSourcePackage> _pendingUpdates(_SourceLists data) {
    final nsfw = LocalBrowsePreferences.instance.showNsfw.value;
    if (_pendingCache case (
      final cached,
      final cachedNsfw,
      final list,
    ) when identical(cached, data) && cachedNsfw == nsfw) {
      return list;
    }
    final list = [
      for (final package
          in _indexFor(data)
              .group(
                installed: {
                  for (final extension in data.extensions)
                    extension.packageId: extension.version,
                },
                query: '',
                languageAllowed: null,
              )
              .updates)
        if (nsfw || !package.isNsfw) package,
    ];
    _pendingCache = (data, nsfw, list);
    return list;
  }

  /// Updates every extension at once, as Tachimanga's Update All does. One
  /// that needs the reader to trust a new signer is left for a single update.
  Future<void> _updateAll(List<LocalSourcePackage> packages) async {
    // Starts right away, like Tachimanga; the snackbar reports the result.
    if (packages.isEmpty || _busyExtension != null) return;
    var updated = 0;
    final skipped = <String>[];
    await _perform('update-all', () async {
      for (final package in packages) {
        try {
          await _sources.install(package);
          updated++;
        } on LocalSourceUntrustedException {
          skipped.add(package.name);
        } on Exception {
          skipped.add(package.name);
        }
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped.isEmpty
              ? localText(
                  context,
                  '$updated extensions updated',
                  '$updated ekstensi diperbarui',
                )
              : localText(
                  context,
                  '$updated updated. Update ${skipped.join(', ')} on its own.',
                  '$updated diperbarui. Perbarui ${skipped.join(', ')} satu per satu.',
                ),
        ),
      ),
    );
  }

  Future<void> _install(
    LocalSourcePackage package, {
    required bool update,
  }) async {
    // No confirmation: a tap on Install or Update installs. Only an APK
    // whose signer differs from its store's key still asks (below).
    LocalExtension? installed;
    await _perform(package.id, () async {
      try {
        installed = await _sources.install(package);
      } on LocalSourceUntrustedException catch (error) {
        // Mihon's "untrusted extension": the APK verifies, but its signer
        // is not the store's key. Install only if the reader trusts it.
        if (!mounted || !await _trustSigner(package, error.signer)) return;
        installed = await _sources.install(package, trustSigner: error.signer);
      }
    });
    if (installed case final extension? when mounted) {
      await _announceInstalled(extension, update: update);
    }
  }

  /// Confirms the install and offers to open the new source right away.
  Future<void> _announceInstalled(
    LocalExtension extension, {
    required bool update,
  }) async {
    final sources = (await _sources.sources())
        .where(
          (source) => source.packageId == extension.packageId && source.enabled,
        )
        .toList();
    if (!mounted) return;
    final languages = _languages;
    final preferred =
        sources
            .where((source) => languages?.contains(source.language) ?? true)
            .firstOrNull ??
        sources.firstOrNull;
    final name = extension.packageName;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            update
                ? localText(context, '$name updated', '$name diperbarui')
                : localText(context, '$name installed', '$name terpasang'),
          ),
          action: preferred == null
              ? null
              : SnackBarAction(
                  label: localText(context, 'Open', 'Buka'),
                  onPressed: () => _openSource(preferred),
                ),
        ),
      );
  }

  Future<bool> _trustSigner(LocalSourcePackage package, String signer) =>
      localConfirm(
        context,
        localText(context, 'Untrusted extension', 'Ekstensi tidak tepercaya'),
        localText(
          context,
          '${package.name} ${package.version} is not signed by the key '
              '${package.repository.host} publishes. Install it only if you '
              'trust its author.\n\nSigner: ${_groupHex(signer)}',
          '${package.name} ${package.version} tidak ditandatangani dengan '
              'kunci yang diterbitkan ${package.repository.host}. Pasang '
              'hanya jika Anda memercayai pembuatnya.\n\nPenanda tangan: '
              '${_groupHex(signer)}',
        ),
      );

  static String _groupHex(String hex) => [
    for (var i = 0; i < hex.length; i += 4)
      hex.substring(i, (i + 4).clamp(0, hex.length)),
  ].join(' ');

  Future<void> _uninstall(LocalExtension extension) async {
    if (await localConfirm(
          context,
          context.l10n.uninstall,
          context.l10n.confirmUninstallMessage,
        ) &&
        mounted) {
      await _perform(
        extension.packageId,
        () => _sources.uninstall(extension.packageId),
      );
    }
  }

  Future<void> _showLanguages() async {
    final data = _loaded;
    if (data == null) return;
    final available = {
      for (final extension in data.sources) extension.language,
      for (final repository in data.repositories)
        for (final package in repository.packages) package.language,
    }.toList()..sort((a, b) => _languageName(a).compareTo(_languageName(b)));
    final selected = {...(_languages ?? available.toSet())};
    final result = await showAppDialog<(Set<String>?,)>(
      context: context,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheetState) => AppDialogPanel(
          title: context.l10n.languages,
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final language in available)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_languageName(language)),
                    value: selected.contains(language),
                    onChanged: (value) => setSheetState(() {
                      if (value) {
                        selected.add(language);
                      } else {
                        selected.remove(language);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, (null,)),
              child: Text(context.l10n.reset),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (selected,)),
              child: Text(context.l10n.ok),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final languages = result.$1;
    setState(() => _languages = languages);
    final prefs = await SharedPreferences.getInstance();
    if (languages == null) {
      await prefs.remove('localBrowseLanguages');
    } else {
      await prefs.setStringList('localBrowseLanguages', languages.toList());
    }
  }

  bool _matches(String name, String language, String query) =>
      (_languages?.contains(language) ?? true) &&
      name.toLowerCase().contains(query.trim().toLowerCase());

  /// The reader's own language first, then multi-language sources, then the
  /// rest by name, as in Mihon.
  List<String> _sortedLanguages(Iterable<String> languages) {
    final own = Localizations.localeOf(context).languageCode;
    int rank(String language) => language == own
        ? 0
        : language.startsWith('$own-')
        ? 1
        : language == 'all' || language == 'multi'
        ? 2
        : 3;
    return languages.toList()..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0
          ? byRank
          : _languageName(
              a,
            ).toLowerCase().compareTo(_languageName(b).toLowerCase());
    });
  }

  void _goToTab(int index) => _tabs.animateTo(
    index,
    duration: context.reduceMotion ? Duration.zero : kTabScrollDuration,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final index = _tabs.index;
    // The number of pending updates on the Extensions tab, as in Tachimanga.
    final pending = switch (_loaded) {
      final data? => _pendingUpdates(data).length,
      null => 0,
    };
    final labels = [
      l10n.sources,
      pending == 0 ? l10n.extensions : '${l10n.extensions} $pending',
      l10n.migrate,
    ];
    final fallback = TabBar(
      controller: _tabs,
      dividerColor: Colors.transparent,
      isScrollable: true,
      tabs: [for (final label in labels) Tab(text: label)],
    );
    final glass = context.windowSizeClass == WindowSizeClass.compact;
    final PreferredSizeWidget header = glass
        ? AppleGlassSegments(
            labels: labels,
            selectedIndex: index,
            onSelected: _goToTab,
            // Follows the pages while they are swiped.
            position: _tabs.animation,
            fallback: fallback,
          )
        : fallback;
    return Scaffold(
      appBar: AppBar(
        title: ApplePageTitle(l10n.browse),
        automaticallyImplyLeading: false,
        actions: [
          if (index == 0)
            AppleGlassToolbarButton(
              id: 'search',
              symbol: 'magnifyingglass',
              label: l10n.search,
              onPressed: () => setState(() => _searchSources = !_searchSources),
              fallbackIcon: FluentIcons.search_24_regular,
            ),
          if (index == 1) ...[
            AppleGlassToolbarButton(
              id: 'extension-stores',
              symbol: 'puzzlepiece.extension',
              label: l10n.extensionStores,
              onPressed: _openStores,
              fallbackIcon: FluentIcons.puzzle_piece_24_regular,
            ),
            AppleGlassToolbarButton(
              id: 'install-extension',
              symbol: 'plus',
              label: l10n.install,
              onPressed: _busyExtension == null ? _importFile : null,
              fallbackIcon: FluentIcons.add_24_regular,
            ),
          ],
          if (index != 2)
            AppleGlassToolbar(
              joined: true,
              actions: [
                if (index == 0)
                  AppleGlassToolbarAction(
                    id: 'filter-sources',
                    symbol: 'line.3.horizontal.decrease',
                    label: l10n.filterSources,
                    onPressed: _showLanguages,
                    fallbackIcon: FluentIcons.filter_24_regular,
                  ),
                AppleGlassToolbarAction(
                  id: 'languages',
                  symbol: 'translate',
                  label: l10n.languages,
                  onPressed: _showLanguages,
                  fallbackIcon: FluentIcons.translate_24_regular,
                ),
              ],
            ),
        ],
        bottom: AppleGlassFloatingHeader.enabled(context) ? null : header,
      ),
      body: Builder(
        builder: (context) {
          final pager = TouchTabPager(
            controller: _tabs,
            children: [
              _catalog(_sourceList),
              _catalog(_extensionList),
              _LocalMigratePage(
                services: widget.services,
                onImportManga: widget.onImportManga,
                onRestoreBackup: widget.onRestoreBackup,
              ),
            ],
          );
          return AppleGlassFloatingHeader.enabled(context)
              ? AppleGlassFloatingHeader.overlay(header: header, child: pager)
              : pager;
        },
      ),
    );
  }

  Widget _catalog(Widget Function(BuildContext, _SourceLists) builder) =>
      FutureBuilder<_SourceLists>(
        future: _lists,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Emoticons(
              illustration: KuchieCharacterPhase.fetchFailed,
              title: localText(
                context,
                'Could not load extensions',
                'Ekstensi gagal dimuat',
              ),
              subTitle: localErrorMessage(context, snapshot.error!),
              button: TextButton(
                onPressed: _reload,
                child: Text(context.l10n.retry),
              ),
            );
          }
          final data = snapshot.data ?? _loaded;
          if (data == null) return const CenterKuchieShimmerIndicator();
          _loaded = data;
          return builder(context, data);
        },
      );

  Widget _extensionIcon(Uri? icon) => ClipRRect(
    borderRadius: KBorderRadius.r8.radius,
    child: SizedBox.square(
      dimension: 48,
      child: icon == null
          ? const Icon(FluentIcons.puzzle_piece_24_regular, size: 28)
          : ServerImage(imageUrl: icon.toString(), size: const Size.square(48)),
    ),
  );

  List<Widget> _section<T>(
    String title,
    List<T> entries,
    Widget Function(T) buildTile, {
    Widget? action,
  }) => [
    if (entries.isNotEmpty) ...[
      SliverToBoxAdapter(
        child: ListTile(title: Text(title), trailing: action),
      ),
      SliverList.builder(
        itemCount: entries.length,
        itemBuilder: (_, index) => buildTile(entries[index]),
      ),
    ],
  ];

  Widget _scroll(BuildContext context, List<Widget> slivers, {Widget? search}) {
    final inset = AppleGlassFloatingHeader.insetOf(context);
    return RefreshIndicator(
      edgeOffset: inset,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: inset)),
          if (search != null)
            SliverToBoxAdapter(
              child: Padding(padding: KEdgeInsets.h16v4.size, child: search),
            ),
          ...slivers,
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
          ),
        ],
      ),
    );
  }

  Widget _sourceList(BuildContext context, _SourceLists data) {
    final visible = data.sources
        .where(
          (extension) =>
              extension.enabled &&
              (LocalBrowsePreferences.instance.showNsfw.value ||
                  !extension.isNsfw) &&
              _matches(extension.name, extension.language, _sourceQuery),
        )
        .toList();
    final lastUsed = visible
        .where((extension) => extension.id == _lastUsed)
        .toList();
    final pinned = visible
        .where((extension) => _pinned.contains(extension.id))
        .toList();
    final remaining = <String, List<LocalExtension>>{};
    for (final extension in visible) {
      if (extension.id == _lastUsed || _pinned.contains(extension.id)) continue;
      (remaining[extension.language] ??= []).add(extension);
    }
    Widget tile(LocalExtension extension) => SourceListTileView(
      name: extension.name,
      language: _languageName(extension.language),
      icon: SourceListTileView.iconFor(extension.icon),
      onOpen: () => _openSource(extension),
      onOpenLatest: extension.supportsLatest
          ? () => _openSource(extension, latest: true)
          : null,
      // A source's own settings, one tap away as in Tachimanga.
      onOpenSettings: extension.canHaveSettings
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocalSourceSettingsScreen(
                  sources: _sources,
                  extension: extension,
                ),
              ),
            )
          : null,
      pin: SourcePinButton(
        pinned: _pinned.contains(extension.id),
        onPressed: () async {
          setState(() {
            if (!_pinned.remove(extension.id)) _pinned.add(extension.id);
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('localPinnedSources', _pinned.toList());
        },
      ),
    );
    return _scroll(
      context,
      [
        ..._section(languageMap['pinned']?.displayName ?? '', pinned, tile),
        ..._section(languageMap['lastUsed']?.displayName ?? '', lastUsed, tile),
        for (final language in _sortedLanguages(remaining.keys))
          ..._section(
            _languageName(language),
            remaining[language]!..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            ),
            tile,
          ),
        if (visible.isEmpty)
          // Emoticons sizes with a LayoutBuilder, which cannot report intrinsics.
          SliverFillRemaining(
            child: _sourceQuery.isNotEmpty
                ? const BrowseNoSearchResults()
                : Emoticons(
                    title: context.l10n.noSourcesFound,
                    button: TextButton(
                      onPressed: () => _goToTab(1),
                      child: Text(context.l10n.extensions),
                    ),
                  ),
          ),
      ],
      search: _searchSources
          ? SearchField(
              key: const ValueKey('local.source-search'),
              initialText: _sourceQuery,
              labelText: context.l10n.searchSourcesHint,
              onChanged: (value) => setState(() => _sourceQuery = value ?? ''),
              onClose: () => setState(() => _searchSources = false),
            )
          : null,
    );
  }

  // Rebuilt only when the stores reload; see [PackageCatalogIndex].
  PackageCatalogIndex<LocalSourcePackage>? _catalogIndex;
  List<LocalSourceRepository>? _indexedRepositories;

  PackageCatalogIndex<LocalSourcePackage> _indexFor(_SourceLists data) {
    if (!identical(_indexedRepositories, data.repositories)) {
      _indexedRepositories = data.repositories;
      _catalogIndex = PackageCatalogIndex(
        [for (final repository in data.repositories) ...repository.packages],
        id: (package) => package.id,
        name: (package) => package.name,
        version: (package) => package.version,
        language: (package) => package.language,
      );
    }
    return _catalogIndex!;
  }

  Widget _extensionList(BuildContext context, _SourceLists data) {
    final installed = {
      for (final extension in data.extensions) extension.packageId: extension,
    };
    final available = _indexFor(data);
    final grouped = available.group(
      installed: {
        for (final extension in data.extensions)
          extension.packageId: extension.version,
      },
      query: _extensionQuery,
      languageAllowed: _languages?.contains,
    );
    final nsfw = LocalBrowsePreferences.instance.showNsfw.value;
    final updates = [
      for (final package in grouped.updates)
        if (nsfw || !package.isNsfw) package,
    ];
    final packages = <String, List<LocalSourcePackage>>{
      for (final entry in grouped.byLanguage.entries)
        if ([
              for (final package in entry.value)
                if (nsfw || !package.isNsfw) package,
            ]
            case final shown when shown.isNotEmpty)
          entry.key: shown,
    };
    final updatedIds = {for (final package in updates) package.id};
    final installedList = data.extensions
        .where(
          (extension) =>
              !updatedIds.contains(extension.packageId) &&
              (nsfw || !extension.isNsfw) &&
              _matches(
                extension.packageName,
                extension.packageLanguage,
                _extensionQuery,
              ),
        )
        .toList();
    Widget packageTile(LocalSourcePackage package) {
      final update = installed.containsKey(package.id);
      final label = update ? context.l10n.update : context.l10n.install;
      final VoidCallback? install = _busyExtension == null
          ? () => _install(package, update: update)
          : null;
      return ExtensionCatalogTile(
        onTap: () => _showExtensionInfo(data, package: package),
        icon: _extensionIcon(package.icon),
        name: package.name,
        language: _languageName(package.language),
        version: package.version,
        restricted: package.isNsfw,
        trailing: _busyExtension == package.id
            ? Semantics(
                label: context.l10n.processing,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : TextButton(onPressed: install, child: Text(label)),
      );
    }

    Widget extensionTile(LocalExtension extension) => ExtensionCatalogTile(
      onTap: () => _showExtensionInfo(data, extension: extension),
      icon: _extensionIcon(extension.icon),
      name: extension.packageName,
      language: _languageName(extension.packageLanguage),
      version: extension.version,
      restricted: extension.isNsfw,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _busyExtension == null
                ? () => _uninstall(extension)
                : null,
            child: Text(
              _busyExtension == extension.packageId
                  ? context.l10n.uninstalling
                  : context.l10n.uninstall,
            ),
          ),
          IconButton(
            tooltip: context.l10n.reinstall,
            icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
            onPressed: switch (available[extension.packageId]) {
              final package? when _busyExtension == null => () => _install(
                package,
                update: false,
              ),
              _ => null,
            },
          ),
        ],
      ),
    );
    return _scroll(
      context,
      [
        ..._section(
          languageMap['update']?.displayName ?? '',
          updates,
          packageTile,
          action: updates.length > 1
              ? TextButton(
                  onPressed: _busyExtension == null
                      ? () => _updateAll(updates)
                      : null,
                  child: Text(
                    _busyExtension == 'update-all'
                        ? context.l10n.processing
                        : localText(context, 'Update all', 'Perbarui semua'),
                  ),
                )
              : null,
        ),
        ..._section(
          languageMap['installed']?.displayName ?? '',
          installedList,
          extensionTile,
        ),
        for (final language in packages.keys.toList()..sort())
          ..._section(
            _languageName(language),
            packages[language]!,
            packageTile,
          ),
        if (installedList.isEmpty && updates.isEmpty && packages.isEmpty)
          // Emoticons sizes with a LayoutBuilder, which cannot report intrinsics.
          SliverFillRemaining(
            child: _extensionQuery.isNotEmpty
                ? const BrowseNoSearchResults()
                : Emoticons(
                    title: context.l10n.extensionListEmpty,
                    button: TextButton(
                      key: const ValueKey('local.add-extension'),
                      onPressed: _openStores,
                      child: Text(context.l10n.extensionStores),
                    ),
                  ),
          ),
      ],
      search: SearchField(
        key: const ValueKey('local.extension-search'),
        initialText: _extensionQuery,
        autofocus: false,
        labelText: context.l10n.searchForExtensions,
        onChanged: (value) => setState(() => _extensionQuery = value ?? ''),
      ),
    );
  }

  Future<void> _showExtensionInfo(
    _SourceLists data, {
    LocalSourcePackage? package,
    LocalExtension? extension,
  }) async {
    final id = package?.id ?? extension!.packageId;
    final repoUrl = package?.repository ?? extension?.repository;
    final store = data.repositories
        .where((repository) => repository.url == repoUrl)
        .firstOrNull
        ?.name;
    final name = package?.name ?? extension!.packageName;
    final language = package?.language ?? extension!.packageLanguage;
    final version = package?.version ?? extension!.version;
    final icon = package?.icon ?? extension?.icon;
    final restricted = package?.isNsfw ?? extension!.isNsfw;
    final preferred = Localizations.localeOf(context).languageCode;
    final sourceVariants = data.sources.where(
      (source) => source.packageId == id,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (detail) => Scaffold(
          appBar: AppBar(
            title: Text(detail.l10n.extensionInfo),
            leading: detailNavigationBackButton(detail),
          ),
          body: ExtensionInfoContent(
            name: name,
            language: _languageName(language),
            version: version,
            restricted: restricted,
            icon: _extensionIcon(icon),
            store: store ?? repoUrl?.host,
            actions: TextButton(
              onPressed: () {
                Navigator.pop(detail);
                if (package != null) {
                  unawaited(_install(package, update: false));
                } else {
                  unawaited(_uninstall(extension!));
                }
              },
              child: Text(
                package != null ? detail.l10n.install : detail.l10n.uninstall,
              ),
            ),
            sources: Column(
              children: [
                for (final source in [
                  ...sourceVariants.where(
                    (source) => source.language == preferred,
                  ),
                  ...sourceVariants.where(
                    (source) => source.language != preferred,
                  ),
                ])
                  ListTile(
                    leading: _extensionIcon(source.icon),
                    title: Text(source.name),
                    subtitle: Text(_languageName(source.language)),
                    onTap: source.enabled ? () => _openSource(source) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (source.enabled && source.supportsLatest)
                          TextButton(
                            onPressed: () => _openSource(source, latest: true),
                            child: Text(detail.l10n.latest),
                          ),
                        IconButton(
                          tooltip: source.enabled
                              ? localText(detail, 'Disable', 'Nonaktifkan')
                              : localText(detail, 'Enable', 'Aktifkan'),
                          icon: Icon(
                            source.enabled
                                ? FluentIcons.eye_off_24_regular
                                : FluentIcons.eye_24_regular,
                          ),
                          onPressed: () {
                            Navigator.pop(detail);
                            unawaited(
                              _perform(
                                id,
                                () => _sources.setEnabled(id, !source.enabled),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Migrate, as in the server collection: the sources your library series
/// come from with a count each; a source lists its series, and each series
/// can be shown or migrated to another source.
class _LocalMigratePage extends StatefulWidget {
  const _LocalMigratePage({
    required this.services,
    this.onImportManga,
    this.onRestoreBackup,
  });

  final LocalCollectionServices services;
  final VoidCallback? onImportManga;
  final VoidCallback? onRestoreBackup;

  @override
  State<_LocalMigratePage> createState() => _LocalMigratePageState();
}

typedef _MigrateGroup = ({
  String sourceId,
  LocalExtension? extension,
  String name,
  List<LocalSeries> series,
});

class _LocalMigratePageState extends State<_LocalMigratePage> {
  late Future<List<_MigrateGroup>> _groups = _load();

  Future<List<_MigrateGroup>> _load() async {
    final (library, extensions) = await (
      widget.services.catalog.list(),
      widget.services.sources.sources(),
    ).wait;
    final byId = {for (final extension in extensions) extension.id: extension};
    final grouped = <String, List<LocalSeries>>{};
    for (final series in library) {
      final source = series.source;
      if (!series.inLibrary || source == null) continue;
      (grouped[source.sourceId] ??= []).add(series);
    }
    final groups = [
      for (final MapEntry(key: id, value: series) in grouped.entries)
        (
          sourceId: id,
          extension: byId[id],
          name: byId[id]?.name ?? series.first.source?.sourceName ?? id,
          series: series..sort((a, b) => a.title.compareTo(b.title)),
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return groups;
  }

  Future<void> _refresh() async {
    setState(() => _groups = _load());
    await _groups;
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    edgeOffset: AppleGlassFloatingHeader.insetOf(context),
    onRefresh: _refresh,
    child: FutureBuilder<List<_MigrateGroup>>(
      future: _groups,
      builder: (context, snapshot) {
        final groups = snapshot.data ?? const [];
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: AppleGlassFloatingHeader.insetOf(context) + 8,
            bottom: MediaQuery.paddingOf(context).bottom + 16,
          ),
          children: [
            for (final group in groups)
              ListTile(
                leading: ClipRRect(
                  borderRadius: KBorderRadius.r8.radius,
                  child: SourceListTileView.iconFor(group.extension?.icon),
                ),
                title: Text(
                  group.name,
                  style: supportsAppleGlass(context)
                      ? context.textTheme.titleMedium
                      : null,
                ),
                subtitle: Text(
                  group.extension == null
                      ? localText(context, 'Not installed', 'Tidak terpasang')
                      : _languageName(group.extension!.language),
                ),
                trailing: _CountBadge(count: group.series.length),
                onTap: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => _LocalMigrateSeriesPage(
                        services: widget.services,
                        group: group,
                      ),
                    ),
                  );
                  if (mounted) unawaited(_refresh());
                },
              ),
            if (snapshot.hasData && groups.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    localText(
                      context,
                      'Series you add to the library from a source show up here.',
                      'Seri dari source yang Anda tambahkan ke pustaka muncul di sini.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if (widget.onImportManga != null || widget.onRestoreBackup != null)
              const Divider(height: 24),
            if (widget.onImportManga != null)
              ListTile(
                leading: const Icon(FluentIcons.folder_open_24_regular),
                title: Text(localText(context, 'Import manga', 'Impor manga')),
                subtitle: const Text('CBZ, ZIP'),
                onTap: widget.onImportManga,
              ),
            if (widget.onRestoreBackup != null)
              ListTile(
                leading: const Icon(
                  FluentIcons.arrow_counterclockwise_24_regular,
                ),
                title: Text(
                  localText(
                    context,
                    'Restore local backup',
                    'Pulihkan cadangan lokal',
                  ),
                ),
                onTap: widget.onRestoreBackup,
              ),
          ],
        );
      },
    ),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: context.textTheme.labelLarge?.copyWith(
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// The library series of one source, each with Show entry and Migrate.
class _LocalMigrateSeriesPage extends StatelessWidget {
  const _LocalMigrateSeriesPage({required this.services, required this.group});

  final LocalCollectionServices services;
  final _MigrateGroup group;

  Future<void> _show(BuildContext context, LocalSeries series) async {
    final reference = localSeriesReference(services.sources, series);
    if (reference == null) return;
    try {
      final found = await services.sources.resolveSeries(
        reference,
        series.title,
      );
      if (!context.mounted) return;
      await openLocalSourceManga(
        context,
        services,
        found.extension,
        found.manga,
      );
    } catch (error) {
      if (context.mounted) localFailure(context, error);
    }
  }

  /// Picks another source and searches it for this title, where the series
  /// can be added to the library in its new home.
  Future<void> _migrate(BuildContext context, LocalSeries series) async {
    final targets = [
      for (final extension in await services.sources.sources())
        if (extension.enabled && extension.id != group.sourceId) extension,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!context.mounted) return;
    final target = await showAppBottomSheet<LocalExtension>(
      context: context,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (sheet, controller) => Column(
          children: [
            AppSheetHeader(title: sheet.l10n.migrate),
            Expanded(
              child: ListView(
                controller: controller,
                children: [
                  for (final extension in targets)
                    ListTile(
                      leading: ClipRRect(
                        borderRadius: KBorderRadius.r8.radius,
                        child: SourceListTileView.iconFor(extension.icon),
                      ),
                      title: Text(extension.name),
                      subtitle: Text(extension.language.toUpperCase()),
                      onTap: () => Navigator.pop(sheet, extension),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _LocalSourcePage(
          services: services,
          extension: target,
          initialQuery: series.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: detailNavigationAppBar(context, title: Text(group.name)),
    body: ListView.builder(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      itemCount: group.series.length,
      itemBuilder: (context, index) {
        final series = group.series[index];
        final kept = services.catalog.keptCover(series.id);
        final cover = series.customCover ?? kept;
        final remote = series.source?.cover;
        return MangaCoverListTile(
          key: ValueKey(series.id),
          titleOverride: series.title,
          coverImage: cover != null
              ? FileImage(cover)
              : remote == null
              ? null
              : NetworkImage(remote.toString()),
          showBadges: false,
          onPressed: () => _show(context, series),
          trailing: PopupMenuButton<String>(
            icon: const Icon(FluentIcons.more_horizontal_24_regular),
            onSelected: (action) => switch (action) {
              'show' => _show(context, series),
              _ => _migrate(context, series),
            },
            itemBuilder: (menu) => [
              PopupMenuItem(
                value: 'show',
                child: Text(menu.l10n.actionShowEntry),
              ),
              PopupMenuItem(value: 'migrate', child: Text(menu.l10n.migrate)),
            ],
          ),
        );
      },
    ),
  );
}

/// Opens the extension store list; true when stores were added or removed.
Future<bool?> openLocalExtensionStores(
  BuildContext context,
  LocalSources sources,
) => Navigator.of(context).push<bool>(
  MaterialPageRoute(builder: (_) => _LocalExtensionStores(sources: sources)),
);

class _LocalExtensionStores extends StatefulWidget {
  const _LocalExtensionStores({required this.sources});
  final LocalSources sources;

  @override
  State<_LocalExtensionStores> createState() => _LocalExtensionStoresState();
}

class _LocalExtensionStoresState extends State<_LocalExtensionStores> {
  late Future<List<LocalSourceRepository>> _stores = widget.sources
      .repositories();
  bool _storesChanged = false;

  void _reload() {
    final stores = widget.sources.repositories();
    setState(() {
      _stores = stores;
    });
  }

  Future<void> _action(Future<void> Function() change) async {
    try {
      await change();
      if (mounted) _reload();
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Future<void> _refresh() async {
    final stores = await _stores;
    final retired = <String>[];
    await _action(() async {
      for (final store in stores) {
        try {
          await widget.sources.refreshRepository(store.url);
        } on LocalSourceRetiredStoreException {
          retired.add(store.name);
        }
      }
    });
    if (retired.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localText(
              context,
              '${retired.join(', ')} no longer publishes extensions. '
                  'Remove it and add Keiyoushi instead.',
              '${retired.join(', ')} sudah tidak menerbitkan ekstensi. '
                  'Hapus store ini dan tambahkan Keiyoushi.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _add() async {
    final existing = await _stores;
    if (!mounted) return;
    final added = await showAppDialog<bool>(
      context: context,
      builder: (_) => _LocalAddExtensionStoreDialog(
        sources: widget.sources,
        existingUrls: {for (final store in existing) store.url},
      ),
    );
    if (mounted && added == true) {
      _storesChanged = true;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: AppleGlassToolbarButton(
          id: 'back',
          symbol: 'chevron.backward',
          label: MaterialLocalizations.of(context).backButtonTooltip,
          fallbackIcon: FluentIcons.chevron_left_24_regular,
          onPressed: () => Navigator.pop(context, _storesChanged),
        ),
        title: Text(
          l10n.extensionStores,
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: AppleGlassToolbar(
              joined: true,
              actions: [
                AppleGlassToolbarAction(
                  id: 'refresh-extension-stores',
                  symbol: 'arrow.clockwise',
                  label: l10n.refresh,
                  onPressed: _refresh,
                  fallbackIcon: FluentIcons.arrow_clockwise_24_regular,
                ),
                AppleGlassToolbarAction(
                  id: 'add-extension-store',
                  symbol: 'plus',
                  label: l10n.addExtensionStore,
                  onPressed: _add,
                  fallbackIcon: FluentIcons.add_24_regular,
                ),
              ],
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<LocalSourceRepository>>(
        future: _stores,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Emoticons(
              illustration: KuchieCharacterPhase.fetchFailed,
              button: TextButton(onPressed: _reload, child: Text(l10n.retry)),
            );
          }
          final stores = snapshot.data;
          if (stores == null) return const CenterKuchieShimmerIndicator();
          if (stores.isEmpty) {
            return Emoticons(
              title: l10n.extensionStoresEmpty,
              button: TextButton.icon(
                onPressed: _add,
                icon: const Icon(FluentIcons.add_24_regular),
                label: Text(l10n.addExtensionStore),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: settingsPagePadding(context, KEdgeInsets.a8.size),
              children: [
                SettingsGroupCard(
                  children: [
                    for (final store in stores)
                      ListTile(
                        leading: const Icon(
                          FluentIcons.puzzle_piece_24_regular,
                          size: 48,
                        ),
                        title: Text(store.name),
                        subtitle: Text(store.url.host),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).copyButtonLabel,
                              icon: const Icon(FluentIcons.copy_24_regular),
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: store.url.toString()),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.removeExtensionStore,
                              icon: const Icon(FluentIcons.delete_24_regular),
                              onPressed: () async {
                                if (await localConfirm(
                                      context,
                                      l10n.removeExtensionStore,
                                      l10n.removeExtensionStoreBody(
                                        store.name,
                                        store.url.toString(),
                                      ),
                                    ) &&
                                    context.mounted) {
                                  await _action(() async {
                                    await widget.sources.removeRepository(
                                      store.url,
                                    );
                                    _storesChanged = true;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LocalAddExtensionStoreDialog extends StatefulWidget {
  const _LocalAddExtensionStoreDialog({
    required this.sources,
    required this.existingUrls,
  });

  final LocalSources sources;
  final Set<Uri> existingUrls;

  @override
  State<_LocalAddExtensionStoreDialog> createState() =>
      _LocalAddExtensionStoreDialogState();
}

class _LocalAddExtensionStoreDialogState
    extends State<_LocalAddExtensionStoreDialog> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  /// Offers Keiyoushi after a retired store that moved there.
  bool _suggestKeiyoushi = false;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = Uri.tryParse(_input.text.trim());
    if (_busy || url == null || !url.hasAuthority) {
      setState(
        () => _error = localText(
          context,
          'Enter a repository URL',
          'Masukkan URL repositori',
        ),
      );
      return;
    }
    if (widget.existingUrls.contains(url)) {
      setState(() => _error = context.l10n.extensionStoreAlreadyExists);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _suggestKeiyoushi = false;
    });
    try {
      await widget.sources.addRepository(url);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (kDebugMode) debugPrint('Kuchie extension store failed: $error');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _suggestKeiyoushi =
            error is LocalSourceRetiredStoreException &&
            error.movedToKeiyoushi &&
            !widget.existingUrls.contains(LocalSources.keiyoushiIndex);
        _error = switch (error) {
          LocalSourceRetiredStoreException(
            :final storeName,
            :final movedToKeiyoushi,
          ) =>
            movedToKeiyoushi
                ? localText(
                    context,
                    '$storeName no longer publishes extensions. They moved '
                        'to Keiyoushi, so add that store instead.',
                    '$storeName sudah tidak menerbitkan ekstensi. Ekstensinya '
                        'pindah ke Keiyoushi, jadi tambahkan store itu.',
                  )
                : localText(
                    context,
                    '$storeName no longer publishes extensions.',
                    '$storeName sudah tidak menerbitkan ekstensi.',
                  ),
          LocalSourceSecurityException(insecureUrl: true) =>
            localSecurityMessage(context, error),
          LocalSourceSecurityException() => localText(
            context,
            'This repository failed a security check and was not added.',
            'Repositori ini gagal pemeriksaan keamanan dan tidak ditambahkan.',
          ),
          FormatException() => localText(
            context,
            'This repository has no compatible iOS extensions.',
            'Repositori ini tidak memiliki ekstensi iOS yang kompatibel.',
          ),
          _ => localText(
            context,
            'Could not load the repository. Try again.',
            'Repositori tidak dapat dimuat. Silakan coba lagi.',
          ),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) => AppDialogPanel(
    title: context.l10n.addExtensionStore,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _input,
          focusNode: _focus,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: context.l10n.storeIndexUrl,
            errorText: _error,
            errorMaxLines: 4,
          ),
        ),
        if (_suggestKeiyoushi && !_busy)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              icon: const Icon(FluentIcons.add_24_regular),
              label: Text(
                localText(context, 'Add Keiyoushi', 'Tambahkan Keiyoushi'),
              ),
              onPressed: () {
                _input.text = LocalSources.keiyoushiIndex.toString();
                _submit();
              },
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
      FilledButton(
        onPressed: !_busy && _input.text.trim().isNotEmpty ? _submit : null,
        child: Text(_busy ? context.l10n.processing : context.l10n.add),
      ),
    ],
  );
}

class _LocalSourcePage extends StatefulWidget {
  const _LocalSourcePage({
    required this.services,
    required this.extension,
    this.latest = false,
    this.initialQuery,
  });

  final LocalCollectionServices services;
  final LocalExtension extension;
  final bool latest;

  /// Opens straight on the results for this search.
  final String? initialQuery;

  @override
  State<_LocalSourcePage> createState() => _LocalSourcePageState();
}

enum _SourceTab { popular, latest, results }

class _LocalSourcePageState extends State<_LocalSourcePage> {
  late _SourceTab _tab = widget.initialQuery != null
      ? _SourceTab.results
      : widget.latest
      ? _SourceTab.latest
      : _SourceTab.popular;
  late final _paging = ServerPagingController<LocalSourceManga>(
    firstPageKey: 1,
    fetchPage: _loadPage,
  );
  bool _showSearch = false;
  bool _showList = false;
  bool _showingSavedResults = false;
  int _requestGeneration = 0;
  late String _query = widget.initialQuery ?? '';

  /// The extension's own filters, loaded when Filter is first opened, and
  /// the reader's applied changes to them.
  List<Filter>? _filters;
  List<FilterChange> _filterChanges = const [];
  bool _loadingFilters = false;

  /// Series ids of this source's titles in the library, for the badge.
  Set<String> _inLibrary = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadLibrary());
  }

  Future<void> _loadLibrary() async {
    try {
      final books = await widget.services.catalog.list();
      if (!mounted) return;
      setState(() {
        _inLibrary = {
          for (final book in books)
            if (book.inLibrary) book.id,
        };
      });
    } catch (_) {
      // The badge is a hint; browsing works without it.
    }
  }

  String _seriesIdOf(LocalSourceManga manga) =>
      localSourceSeriesId(widget.extension, manga.id);

  /// Long press, as in Mihon: add to or remove from the library, with Undo.
  Future<void> _toggleLibrary(LocalSourceManga manga) async {
    final seriesId = _seriesIdOf(manga);
    final add = !_inLibrary.contains(seriesId);
    final catalog = widget.services.catalog;
    final reference = widget.services.sources.seriesReference(
      manga,
      sourceName: widget.extension.name,
    );
    Future<void> apply(bool inLibrary) async {
      await catalog.setInLibrary(
        seriesId: seriesId,
        title: manga.title,
        inLibrary: inLibrary,
        source: reference,
      );
      if (!mounted) return;
      setState(() {
        _inLibrary = inLibrary
            ? {..._inLibrary, seriesId}
            : ({..._inLibrary}..remove(seriesId));
      });
    }

    unawaited(HapticFeedback.mediumImpact());
    try {
      await apply(add);
      if (add) {
        unawaited(keepLocalSourceCover(widget.services, seriesId, manga));
      }
    } catch (error) {
      if (mounted) localFailure(context, error);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            add
                ? localText(
                    context,
                    'Added ${manga.title} to the library',
                    '${manga.title} ditambahkan ke perpustakaan',
                  )
                : localText(
                    context,
                    'Removed ${manga.title} from the library',
                    '${manga.title} dihapus dari perpustakaan',
                  ),
          ),
          action: SnackBarAction(
            label: localText(context, 'Undo', 'Urungkan'),
            onPressed: () => unawaited(
              apply(!add).catchError((Object error) {
                if (mounted) localFailure(context, error);
              }),
            ),
          ),
        ),
      );
  }

  Widget _libraryBadge(BuildContext context) => Positioned(
    top: 8,
    left: 8,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          context.l10n.inLibrary,
          style: context.textTheme.labelMedium?.copyWith(
            color: context.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    ),
  );

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalSourceSettingsScreen(
          sources: widget.services.sources,
          extension: widget.extension,
        ),
      ),
    );
    // A changed setting can change what the source lists (language,
    // mirror, content filters), so reload from the first page.
    if (mounted) _paging.refresh();
  }

  Future<ServerPage<LocalSourceManga>> _loadPage(int page) async {
    final generation = _requestGeneration;
    final result = await widget.services.sources.browsePage(
      widget.extension.id,
      query: _tab == _SourceTab.results ? _query : '',
      latest: _tab == _SourceTab.latest,
      filters: _tab == _SourceTab.results ? _filterChanges : const [],
      page: page,
      onFreshness: (fromCache) {
        if (!mounted || generation != _requestGeneration) return;
        final showingSaved = fromCache || (page != 1 && _showingSavedResults);
        if (showingSaved != _showingSavedResults) {
          setState(() => _showingSavedResults = showingSaved);
        }
      },
    );
    return (items: result.items, hasNextPage: result.hasMore);
  }

  @override
  void dispose() {
    _paging.dispose();
    super.dispose();
  }

  void _select(_SourceTab tab) {
    setState(() {
      _tab = tab;
      _requestGeneration++;
      _showingSavedResults = false;
    });
    _paging.refresh();
  }

  void _search(String? query) {
    final value = query?.trim();
    if ((value == null || value.isEmpty) && _filterChanges.isEmpty) {
      _query = '';
      _select(_SourceTab.popular);
    } else {
      _query = value ?? '';
      _select(_SourceTab.results);
    }
  }

  Future<void> _open(LocalSourceManga manga) async {
    await openLocalSourceManga(
      context,
      widget.services,
      widget.extension,
      manga,
    );
    // The title may have been added to or removed from the library there.
    if (mounted) await _loadLibrary();
  }

  /// The extension's filters in the same sheet as Server sources; sources
  /// without filters choose between Popular and Latest.
  Future<void> _showFilter() async {
    if (!widget.extension.canHaveSettings) return _showListChoice();
    if (_loadingFilters) return;
    var filters = _filters;
    if (filters == null) {
      setState(() => _loadingFilters = true);
      try {
        filters = await widget.services.sources.sourceFilters(
          widget.extension.id,
        );
      } catch (error) {
        if (mounted) localFailure(context, error);
        return;
      } finally {
        if (mounted) setState(() => _loadingFilters = false);
      }
      if (!mounted) return;
      _filters = filters;
    }
    if (filters.isEmpty) return _showListChoice();
    await showAppBottomSheet<void>(
      context: context,
      builder: (sheet) => SourceMangaFilter(
        inSheet: true,
        filters: filters!,
        sourceId: widget.extension.id,
        appliedChanges: _filterChanges,
        onReset: () async {
          // Like Mihon's Reset: ask the extension again, which some need
          // before they list their filters.
          try {
            final fresh = await widget.services.sources.sourceFilters(
              widget.extension.id,
              reload: true,
            );
            if (!mounted) return;
            _filters = fresh;
          } catch (_) {
            // Keep the filters already shown.
          }
          _filterChanges = const [];
          if (sheet.mounted) Navigator.pop(sheet);
          if (_query.isEmpty && _tab == _SourceTab.results) {
            _select(_SourceTab.popular);
          } else if (_tab == _SourceTab.results) {
            _select(_SourceTab.results);
          }
          if (mounted && (_filters?.isNotEmpty ?? false)) {
            unawaited(_showFilter());
          }
        },
        onSubmitted: (changes) {
          Navigator.pop(sheet);
          _filterChanges = changes ?? const [];
          if (_filterChanges.isEmpty && _query.isEmpty) {
            _select(_SourceTab.popular);
          } else {
            _select(_SourceTab.results);
          }
        },
      ),
    );
  }

  Future<void> _showListChoice() => showAppBottomSheet<void>(
    context: context,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetHeader(title: context.l10n.filter),
        for (final (tab, label) in [
          (_SourceTab.popular, context.l10n.sourceTypePopular),
          if (widget.extension.supportsLatest)
            (_SourceTab.latest, context.l10n.sourceTypeLatest),
        ])
          ListTile(
            title: Text(label),
            trailing: _tab == tab
                ? const Icon(FluentIcons.checkmark_24_regular)
                : null,
            onTap: () {
              Navigator.pop(sheet);
              _select(tab);
            },
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final extension = widget.extension;
    final l10n = context.l10n;
    final tabs = [
      _SourceTab.popular,
      if (extension.supportsLatest) _SourceTab.latest,
      if (_tab == _SourceTab.results) _SourceTab.results,
    ];
    final labels = [
      l10n.sourceTypePopular,
      if (extension.supportsLatest) l10n.sourceTypeLatest,
      if (_tab == _SourceTab.results) l10n.searchResults,
      _filterChanges.isEmpty
          ? l10n.filter
          : '${l10n.filter} ${_filterChanges.length}',
    ];
    void select(int index) =>
        index == tabs.length ? _showFilter() : _select(tabs[index]);
    final segments = AppleGlassSegments(
      labels: labels,
      symbols: [
        'heart',
        if (extension.supportsLatest) 'clock',
        if (_tab == _SourceTab.results) '',
        'line.3.horizontal.decrease',
      ],
      selectedIndex: tabs.indexOf(_tab),
      actionIndices: {tabs.length},
      scrollable: labels.length > 3,
      onSelected: select,
      fallback: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: Wrap(
          spacing: 4,
          children: [
            for (final (index, label) in labels.indexed)
              TextButton(onPressed: () => select(index), child: Text(label)),
          ],
        ),
      ),
    );
    final savedNote = _showingSavedResults
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              localText(
                context,
                'Showing saved results',
                'Menampilkan hasil tersimpan',
              ),
              style: context.textTheme.bodySmall,
            ),
          )
        : null;
    return CollapsingTitleScaffold(
      title: extension.name,
      // Pull down above the title to load the catalogue again.
      onRefresh: () async => _paging.refresh(),
      subtitle: extension.homepage?.toString(),
      below: _showSearch || savedNote != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ?savedNote,
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SearchField(
                      initialText: _query,
                      labelText: l10n.searchSourceHint(extension.name),
                      onClose: () => setState(() => _showSearch = false),
                      onSubmitted: _search,
                    ),
                  ),
              ],
            )
          : null,
      pinned: segments,
      actions: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 12),
          child: AppleGlassToolbar(
            joined: true,
            actions: [
              AppleGlassToolbarAction(
                id: 'search-source',
                symbol: 'magnifyingglass',
                label: l10n.search,
                onPressed: () => setState(() => _showSearch = true),
                fallbackIcon: FluentIcons.search_24_regular,
              ),
              AppleGlassToolbarAction(
                id: 'source-menu',
                symbol: 'ellipsis',
                label: l10n.more,
                onPressed: null,
                fallbackIcon: FluentIcons.more_horizontal_24_regular,
                menu: [
                  AppleGlassToolbarMenuItem(
                    id: 'display',
                    title: _showList
                        ? l10n.displayModeGrid
                        : l10n.displayModeList,
                    symbol: _showList ? 'square.grid.2x2' : 'list.bullet',
                    onSelected: () => setState(() => _showList = !_showList),
                    fallbackIcon: _showList
                        ? FluentIcons.grid_24_regular
                        : FluentIcons.list_24_regular,
                  ),
                  if (extension.canHaveSettings)
                    AppleGlassToolbarMenuItem(
                      id: 'source-settings',
                      title: localText(
                        context,
                        'Source settings',
                        'Pengaturan sumber',
                      ),
                      symbol: 'gearshape',
                      onSelected: _openSettings,
                      fallbackIcon: FluentIcons.settings_24_regular,
                    ),
                  if (extension.homepage case final url?)
                    AppleGlassToolbarMenuItem(
                      id: 'home',
                      title: l10n.openHomepage,
                      symbol: 'globe',
                      onSelected: () => _openLocalSourceHomepage(context, url),
                      fallbackIcon: FluentIcons.globe_24_regular,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
      body: _resultList(),
    );
  }

  Widget _resultList() => PagingListener(
    controller: _paging,
    builder: (context, state, fetchNextPage) {
      final inset = AppleGlassFloatingHeader.insetOf(context);
      final bottom = MediaQuery.paddingOf(context).bottom + 8;
      final padding = EdgeInsets.fromLTRB(8, inset, 8, bottom);
      final delegate = PagedChildBuilderDelegate<LocalSourceManga>(
        firstPageProgressIndicatorBuilder: (_) =>
            const CenterKuchieShimmerIndicator(),
        firstPageErrorIndicatorBuilder: (_) {
          final error = state.error;
          final blocked = error is MihonRuntimeException && error.looksBlocked;
          final homepage = widget.extension.homepage;
          return Emoticons(
            illustration: KuchieCharacterPhase.fetchFailed,
            title: localText(
              context,
              'Could not load manga',
              'Manga gagal dimuat',
            ),
            subTitle: error == null ? null : localErrorMessage(context, error),
            button: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (blocked && homepage != null)
                  FilledButton.tonal(
                    onPressed: () =>
                        _openLocalSourceHomepage(context, homepage),
                    child: Text(context.l10n.webView),
                  ),
                TextButton(
                  onPressed: fetchNextPage,
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          );
        },
        noItemsFoundIndicatorBuilder: (_) => Emoticons(
          illustration: KuchieCharacterPhase.noResults,
          title: context.l10n.noMangaFound,
          button: TextButton(
            onPressed: _paging.refresh,
            child: Text(context.l10n.refresh),
          ),
        ),
        newPageProgressIndicatorBuilder: (_) => PagingFooter(
          loading: state.isLoading,
          height: 64,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
        newPageErrorIndicatorBuilder: (_) => TextButton(
          onPressed: fetchNextPage,
          child: Text(context.l10n.retry),
        ),
        itemBuilder: (context, manga, index) => _showList
            ? MangaCoverListTile(
                key: ValueKey(manga.id),
                titleOverride: manga.title,
                coverImage: manga.cover == null
                    ? null
                    : NetworkImage(
                        manga.cover.toString(),
                        headers: manga.coverHeaders,
                      ),
                fallbackCoverImage: manga.coverFallback == null
                    ? null
                    : NetworkImage(
                        manga.coverFallback.toString(),
                        headers: manga.coverHeaders,
                      ),
                showBadges: false,
                onPressed: () => _open(manga),
                onLongPress: () => _toggleLibrary(manga),
              )
            : Semantics(
                button: true,
                label: manga.title,
                value: _inLibrary.contains(_seriesIdOf(manga))
                    ? context.l10n.inLibrary
                    : null,
                excludeSemantics: true,
                // Grid cells are tight; keep the tile filling its cell.
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MangaCoverGridTile(
                      key: ValueKey(manga.id),
                      titleOverride: manga.title,
                      coverImage: manga.cover == null
                          ? null
                          : NetworkImage(
                              manga.cover.toString(),
                              headers: manga.coverHeaders,
                            ),
                      fallbackCoverImage: manga.coverFallback == null
                          ? null
                          : NetworkImage(
                              manga.coverFallback.toString(),
                              headers: manga.coverHeaders,
                            ),
                      showBadges: false,
                      showDarkOverlay: false,
                      borderRadius: _coverRadius,
                      onPressed: () => _open(manga),
                      onLongPress: () => _toggleLibrary(manga),
                    ),
                    if (_inLibrary.contains(_seriesIdOf(manga)))
                      _libraryBadge(context),
                  ],
                ),
              ),
      );
      // Pull-to-refresh lives in the header scaffold, above the title.
      return _showList
          ? PagedListView<int, LocalSourceManga>(
              state: state,
              fetchNextPage: fetchNextPage,
              padding: padding,
              physics: const AlwaysScrollableScrollPhysics(),
              builderDelegate: delegate,
            )
          : PagedGridView<int, LocalSourceManga>(
              state: state,
              fetchNextPage: fetchNextPage,
              padding: padding,
              physics: const AlwaysScrollableScrollPhysics(),
              showNewPageErrorIndicatorAsGridChild: false,
              showNewPageProgressIndicatorAsGridChild: false,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    context.windowSizeClass == WindowSizeClass.compact ? 2 : 4,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: .74,
              ),
              builderDelegate: delegate,
            );
    },
  );
}

void _openLocalSourceHomepage(BuildContext context, Uri url) {
  // Shared in-app WebView keeps an explicit external browser action. It sends
  // the extensions' user agent, so a Cloudflare check passed here carries
  // over to the source.
  unawaited(() async {
    final userAgent = await LocalNetworkSettings.instance.effectiveUserAgent();
    if (!context.mounted) return;
    await openInAppWebView(context, url.toString(), userAgent: userAgent);
  }());
}

/// Series header for on-device series: the same cover tile, title, author,
/// status and source line as the server's compact header, over the same
/// blurred cover backdrop.
class LocalMangaHero extends StatelessWidget {
  const LocalMangaHero({
    super.key,
    required this.title,
    required this.source,
    this.cover,
    this.fallbackCover,
    this.author,
    this.status,
    this.showBackdrop = true,
    this.onSourcePressed,
    this.onSearch,
  });

  final String title;
  final String source;
  final ImageProvider? cover;
  final ImageProvider? fallbackCover;
  final String? author;
  final MangaStatus? status;
  final bool showBackdrop;
  final VoidCallback? onSourcePressed;

  /// Holding the title or author searches it; a tap always copies.
  final ValueChanged<String>? onSearch;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
      child: MangaCoverDescriptiveListTile(
        titleOverride: title,
        authorOverride: author,
        statusOverride: status ?? MangaStatus.unknown,
        sourceNameOverride: source,
        onSourcePressed: onSourcePressed,
        coverImage: cover,
        fallbackCoverImage: fallbackCover,
        showBadges: false,
        // Long titles stop at two lines; a tap still copies all of it.
        titleMaxLines: 2,
        onTitleClicked: (text) => onSearch?.call(text ?? ''),
      ),
    );
    if (!showBackdrop || (cover == null && fallbackCover == null)) {
      return header;
    }
    return LayoutBuilder(
      builder: (context, constraints) => MangaCoverHero(
        backdrop: _localCoverImage(
          cover,
          fallbackCover,
          (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
              .round()
              .clamp(1, 720),
          const SizedBox.expand(),
        ),
        child: header,
      ),
    );
  }
}

Widget _localCoverImage(
  ImageProvider? cover,
  ImageProvider? fallback,
  int? cacheWidth,
  Widget placeholder,
) {
  Widget image(ImageProvider provider, ImageErrorWidgetBuilder onError) =>
      Image(
        image: ResizeImage.resizeIfNeeded(cacheWidth, null, provider),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: onError,
      );
  Widget useFallback() => fallback == null || fallback == cover
      ? placeholder
      : image(fallback, (_, _, _) => placeholder);
  return cover == null
      ? useFallback()
      : image(cover, (_, _, _) => useFallback());
}

Future<void> openLocalSourceManga(
  BuildContext context,
  LocalCollectionServices services,
  LocalExtension extension,
  LocalSourceManga manga,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => _LocalSourceMangaPage(
      services: services,
      extension: extension,
      manga: manga,
    ),
  ),
);

class _LocalSourceMangaPage extends StatefulWidget {
  const _LocalSourceMangaPage({
    required this.services,
    required this.extension,
    required this.manga,
  });
  final LocalCollectionServices services;
  final LocalExtension extension;
  final LocalSourceManga manga;

  @override
  State<_LocalSourceMangaPage> createState() => _LocalSourceMangaPageState();
}

class _LocalSourceMangaPageState extends State<_LocalSourceMangaPage> {
  late Future<List<LocalSourceChapter>> _chapters = _load();
  late Future<LocalSeries?> _library = widget.services.catalog.find(_seriesId);
  var _marks = const <String, LocalChapterMarks>{};
  File? _customCover;

  /// The chapter last read online, which Resume weighs against saved ones.
  LocalRemoteRead? _lastOnline;
  int _personalRequest = 0;

  /// Chapter ids picked for a bulk action; selection mode while not empty.
  final _selection = <String>{};
  bool _unreadOnly = false;
  bool _bookmarkedOnly = false;
  late LocalSourceManga _manga = widget.manga;
  int _detailsRequest = 0;
  final _busy = <String>{};
  final _scrollOffset = ValueNotifier(0.0);
  bool _savingLibrary = false;
  String get _seriesId =>
      localSourceSeriesId(widget.extension, widget.manga.id);
  LocalDownloadQueue get _queue => widget.services.downloads;

  /// The line above the chapter list: checking, nothing new, or new chapters.
  ChapterCheck? _check;
  int _checkRequest = 0;

  Future<List<LocalSourceChapter>> _load() {
    final chapters = widget.services.sources.chapters(
      widget.extension.id,
      widget.manga,
    );
    // Callers rebuild right after, so no setState here.
    _check = (state: ChapterCheckState.checking, count: 0);
    unawaited(_trackCheck(chapters));
    return chapters;
  }

  /// Compares with the chapter count seen last time this series was opened.
  Future<void> _trackCheck(Future<List<LocalSourceChapter>> chapters) async {
    final request = ++_checkRequest;
    ChapterCheck? result;
    try {
      final count = (await chapters).length;
      final prefs = await SharedPreferences.getInstance();
      final key = 'local.reader.chapterCount.$_seriesId';
      final before = prefs.getInt(key);
      await prefs.setInt(key, count);
      result = switch (before) {
        // First visit: nothing to compare with.
        null => null,
        final before when count > before => (
          state: ChapterCheckState.newChapters,
          count: count - before,
        ),
        _ => (state: ChapterCheckState.upToDate, count: 0),
      };
    } catch (_) {
      result = (state: ChapterCheckState.failed, count: 0);
    }
    if (mounted && request == _checkRequest) setState(() => _check = result);
  }

  @override
  void initState() {
    super.initState();
    _queue.completed.addListener(_reload);
    unawaited(_loadMangaDetails());
    unawaited(_loadPersonal());
  }

  Future<void> _loadPersonal() async {
    final request = ++_personalRequest;
    try {
      final catalog = widget.services.catalog;
      final marks = await catalog.chapterMarks(_seriesId);
      final meta = await catalog.seriesMeta(_seriesId);
      final lastOnline = await catalog.lastRemoteRead(_seriesId);
      if (!mounted || request != _personalRequest) return;
      setState(() {
        _marks = marks;
        _customCover = meta.cover;
        _lastOnline = lastOnline;
      });
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Animation<double>? _covered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // History opens the reader above this page; refresh read marks and
    // Resume once that reader closes.
    final covered = ModalRoute.of(context)?.secondaryAnimation;
    if (covered != _covered) {
      _covered?.removeStatusListener(_onUncovered);
      _covered = covered?..addStatusListener(_onUncovered);
    }
  }

  void _onUncovered(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) _reload();
  }

  @override
  void dispose() {
    _covered?.removeStatusListener(_onUncovered);
    _queue.completed.removeListener(_reload);
    _scrollOffset.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _library = widget.services.catalog.find(_seriesId);
    });
    unawaited(_loadPersonal());
  }

  Future<void> _mark(
    Iterable<String> chapterIds, {
    bool? read,
    bool? bookmarked,
  }) => _changeDownload(() async {
    await widget.services.catalog.setChapterMarks(
      _seriesId,
      chapterIds,
      read: read,
      bookmarked: bookmarked,
    );
    if (mounted) {
      setState(_selection.clear);
      _reload();
    }
  });

  void _toggleSelected(String chapterId) => setState(() {
    if (!_selection.remove(chapterId)) _selection.add(chapterId);
  });

  Future<void> _editCover() async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      final path = picked?.path;
      if (path == null || !mounted) return;
      await widget.services.catalog.setCover(_seriesId, File(path));
      if (mounted) _reload();
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Future<void> _resetCover() => _changeDownload(() async {
    await widget.services.catalog.setCover(_seriesId, null);
    if (mounted) _reload();
  });

  Future<void> _loadMangaDetails() async {
    final request = ++_detailsRequest;
    try {
      final details = await widget.services.sources.mangaDetails(
        widget.extension.id,
        widget.manga,
      );
      if (mounted &&
          request == _detailsRequest &&
          !identical(details, _manga)) {
        setState(() => _manga = details);
      }
    } catch (_) {
      // Keep the metadata from Browse while chapters load independently.
    }
    if (mounted && request == _detailsRequest) {
      unawaited(keepLocalSourceCover(widget.services, _seriesId, _manga));
    }
  }

  /// Adds the series with the categories the user picks (none checked at
  /// first), or edits them once it is in the library. Unchecking every
  /// category removes it from the library.
  Future<void> _editLibrary(LocalSeries? series) async {
    if (_savingLibrary) return;
    setState(() => _savingLibrary = true);
    try {
      final catalog = widget.services.catalog;
      final inLibrary = series?.inLibrary == true;
      final names = await catalog.categories();
      if (!mounted) return;
      final Set<String> picked;
      if (names.isEmpty) {
        // Nothing to choose from: add straight away, or confirm the removal.
        if (inLibrary &&
            !await localConfirm(
              context,
              context.l10n.removeFromLibrary,
              context.l10n.duplicatesRemoveConfirm(1),
            )) {
          return;
        }
        picked = const {};
      } else {
        final current = {...?series?.categories}.intersection(names.toSet());
        final choice = await showLibraryCategoryPicker<String>(
          context,
          options: [for (final name in names) (id: name, name: name)],
          initial: inLibrary ? current : const {},
          inLibrary: inLibrary,
          subtitle: _manga.title,
        );
        if (choice == null || !mounted) return;
        if (inLibrary &&
            choice.length == current.length &&
            choice.containsAll(current)) {
          return;
        }
        picked = choice;
      }
      final keep = !inLibrary || picked.isNotEmpty;
      if (keep) {
        await catalog.setInLibrary(
          seriesId: _seriesId,
          title: _manga.title,
          inLibrary: true,
          source: widget.services.sources.seriesReference(
            _manga,
            sourceName: widget.extension.name,
          ),
        );
        await catalog.setCategories(_seriesId, picked.toList());
        if (!inLibrary) {
          unawaited(keepLocalSourceCover(widget.services, _seriesId, _manga));
        }
      } else {
        // Clear memberships first so a later add starts with nothing checked.
        await catalog.setCategories(_seriesId, const []);
        await catalog.setInLibrary(
          seriesId: _seriesId,
          title: _manga.title,
          inLibrary: false,
        );
      }
      if (mounted) _reload();
    } catch (error) {
      if (mounted) localFailure(context, error);
    } finally {
      if (mounted) {
        setState(() => _savingLibrary = false);
      } else {
        _savingLibrary = false;
      }
    }
  }

  Future<void> _download(LocalSourceChapter chapter) async {
    if (!_busy.add(chapter.id)) return;
    setState(() {});
    try {
      await enqueueLocalChapterDownload(
        widget.services,
        widget.extension,
        _manga,
        _seriesId,
        chapter,
      );
    } catch (error) {
      if (mounted) localFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(chapter.id));
    }
  }

  bool _descriptionExpanded = false;
  bool _descending = true;
  bool _onlyDownloaded = false;
  bool _grid = false;
  void _openChapter(LocalSourceChapter chapter, LocalSeries? series) {
    unawaited(() async {
      try {
        final available = await _chapters;
        if (!mounted) return;
        final readingOrder = widget.extension.chaptersNewestFirst
            ? available.reversed.toList(growable: false)
            : available;
        await openLocalSourceChapter(
          context,
          services: widget.services,
          extension: widget.extension,
          manga: _manga,
          chapters: readingOrder,
          initialChapter: chapter,
          seriesId: _seriesId,
          savedSeries: series,
        );
        if (mounted) _reload();
      } catch (error) {
        if (mounted) localFailure(context, error);
      }
    }());
  }

  Future<void> _refresh() async {
    setState(() {
      _chapters = _load();
      _library = widget.services.catalog.find(_seriesId);
    });
    unawaited(_loadMangaDetails());
    try {
      await _chapters;
    } catch (_) {
      // FutureBuilder handles lookup errors.
    }
  }

  Future<void> _changeDownload(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Future<void> _removeChapter(LocalSourceChapter chapter) async {
    if (await localConfirm(
          context,
          context.l10n.removeFromDevice,
          chapter.title,
        ) &&
        mounted) {
      await _changeDownload(() async {
        await widget.services.catalog.removeChapter(_seriesId, chapter.id);
        if (mounted) _reload();
      });
    }
  }

  Future<void> _chapterMenu(
    Offset point,
    LocalSourceChapter chapter,
    LocalSeries? series,
    LocalChapter? saved,
    LocalDownload? job, {
    required LocalChapterMarks marks,
    required List<LocalSourceChapter> readingOrder,
  }) async {
    final l10n = context.l10n;
    final index = readingOrder.indexWhere((other) => other.id == chapter.id);
    await showAppleGlassMenu<void>(
      context: context,
      position: menuAnchorForPoint(context, point),
      popUpAnimationStyle: context.motionStyle,
      items: [
        PopupMenuItem(
          onTap: () => _openChapter(chapter, series),
          child: ChapterMenuRow(
            icon: FluentIcons.book_open_24_regular,
            label: l10n.offlineChapterRead,
          ),
        ),
        PopupMenuItem(
          onTap: () => _toggleSelected(chapter.id),
          child: ChapterMenuRow(
            icon: FluentIcons.checkbox_checked_24_regular,
            label: l10n.select,
          ),
        ),
        PopupMenuItem(
          onTap: () => _mark([chapter.id], read: !marks.read),
          child: ChapterMenuRow(
            icon: marks.read
                ? FluentIcons.eye_off_24_regular
                : FluentIcons.eye_24_regular,
            label: marks.read ? l10n.markAsUnread : l10n.markAsRead,
          ),
        ),
        if (index > 0)
          PopupMenuItem(
            onTap: () => _mark([
              for (final previous in readingOrder.take(index)) previous.id,
            ], read: true),
            child: ChapterMenuRow(
              icon: FluentIcons.arrow_up_24_regular,
              label: l10n.markPreviousAsRead,
            ),
          ),
        PopupMenuItem(
          onTap: () => _mark([chapter.id], bookmarked: !marks.bookmarked),
          child: ChapterMenuRow(
            icon: marks.bookmarked
                ? FluentIcons.bookmark_off_24_regular
                : FluentIcons.bookmark_24_regular,
            label: marks.bookmarked ? l10n.removeBookmark : l10n.bookmark,
          ),
        ),
        if (saved != null)
          PopupMenuItem(
            onTap: () => _removeChapter(chapter),
            child: ChapterMenuRow(
              icon: FluentIcons.delete_24_regular,
              label: l10n.removeFromDevice,
            ),
          )
        else if (job != null)
          PopupMenuItem(
            onTap: () =>
                _changeDownload(() => _queue.remove(_seriesId, chapter.id)),
            child: ChapterMenuRow(
              icon: FluentIcons.dismiss_24_regular,
              label: l10n.cancelDownloads,
            ),
          )
        else
          PopupMenuItem(
            onTap: () => _download(chapter),
            child: ChapterMenuRow(
              icon: FluentIcons.arrow_download_24_regular,
              label: localText(
                context,
                'Save to device',
                'Simpan ke perangkat',
              ),
            ),
          ),
      ],
    );
  }

  Widget _chapterRow(
    LocalSourceChapter chapter,
    LocalSeries? series,
    LocalChapter? saved,
    LocalDownload? job, {
    required LocalChapterMarks marks,
    required List<LocalSourceChapter> readingOrder,
  }) {
    final selecting = _selection.isNotEmpty;
    final selected = _selection.contains(chapter.id);
    final working =
        _busy.contains(chapter.id) ||
        job?.state == LocalDownloadState.queued ||
        job?.state == LocalDownloadState.downloading;
    final date = chapter.uploadDate;
    Future<void> runSwipe(ChapterSwipeAction action) async {
      switch (action) {
        case ChapterSwipeAction.toggleRead:
          await _mark([chapter.id], read: !marks.read);
        case ChapterSwipeAction.toggleBookmark:
          await _mark([chapter.id], bookmarked: !marks.bookmarked);
        case ChapterSwipeAction.download:
          if (saved != null) {
            await _removeChapter(chapter);
          } else if (job == null) {
            await _download(chapter);
          } else {
            await _changeDownload(() => _queue.resume(_seriesId, chapter.id));
          }
        case ChapterSwipeAction.disabled:
          break;
      }
    }

    IconData? swipeIcon(ChapterSwipeAction action) => chapterSwipeIcon(
      action,
      read: marks.read,
      bookmarked: marks.bookmarked,
      downloadQueued: working,
      downloadFailed: job?.state == LocalDownloadState.failed,
      downloaded: saved != null,
      canDownload: true,
    );

    return Consumer(
      builder: (context, ref, _) {
        final swipeLeft =
            ref.watch(chapterSwipeToLeftProvider) ??
            DBKeys.chapterSwipeToLeft.initial;
        final swipeRight =
            ref.watch(chapterSwipeToRightProvider) ??
            DBKeys.chapterSwipeToRight.initial;
        return ChapterRowView(
          key: ValueKey('local-chapter-${chapter.id}'),
          title: chapter.title,
          date: date?.toLocal().millisecondsSinceEpoch.toDaysAgo(context),
          extra: job == null || job.pageCount == 0 || saved != null
              ? null
              : '${job.done} / ${job.pageCount}',
          isRead: marks.read,
          isBookmarked: marks.bookmarked,
          // Online reads keep their page too, for the last one read.
          lastPageRead:
              saved?.progress ??
              (_lastOnline?.chapterId == chapter.id
                  ? _lastOnline!.progress
                  : 0),
          pageCount: saved?.pages.length ?? 0,
          isDownloaded: saved != null,
          isSelected: selected,
          leading: selecting
              ? Icon(
                  selected
                      ? FluentIcons.checkmark_circle_24_filled
                      : FluentIcons.circle_24_regular,
                  color: selected ? context.colorScheme.primary : null,
                )
              : null,
          onTap: selecting
              ? () => _toggleSelected(chapter.id)
              : () => _openChapter(chapter, series),
          onLongPress: () => _toggleSelected(chapter.id),
          onLongPressAt: selecting
              ? null
              : (point) => _chapterMenu(
                  point,
                  chapter,
                  series,
                  saved,
                  job,
                  marks: marks,
                  readingOrder: readingOrder,
                ),
          trailing: selecting
              ? null
              : saved != null
              ? IconButton(
                  tooltip: context.l10n.removeFromDevice,
                  onPressed: () => _removeChapter(chapter),
                  icon: Icon(
                    FluentIcons.checkmark_circle_24_filled,
                    color: context.colorScheme.primary,
                  ),
                )
              : working
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      value: job == null || job.pageCount == 0
                          ? null
                          : job.done / job.pageCount,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: localText(
                    context,
                    'Save to device',
                    'Simpan ke perangkat',
                  ),
                  icon: const Icon(FluentIcons.arrow_circle_down_24_regular),
                  onPressed: job == null
                      ? () => _download(chapter)
                      : () => _changeDownload(
                          () => _queue.resume(_seriesId, chapter.id),
                        ),
                ),
          swipeEnabled: !selecting,
          leftSwipeIcon: swipeIcon(swipeLeft),
          rightSwipeIcon: swipeIcon(swipeRight),
          onSwipeLeft: () => runSwipe(swipeLeft),
          onSwipeRight: () => runSwipe(swipeRight),
        );
      },
    );
  }

  Widget _chapterGridButton(
    LocalSourceChapter chapter,
    LocalSeries? series,
    LocalChapter? saved,
    LocalDownload? job, {
    required LocalChapterMarks marks,
    required List<LocalSourceChapter> readingOrder,
  }) {
    final selecting = _selection.isNotEmpty;
    return ChapterGridTileView(
      key: ValueKey('local-chapter-grid-${chapter.id}'),
      label: ChapterGridTileView.numberLabel(
        chapter.number,
        readingOrder.indexOf(chapter) + 1,
      ),
      tooltip: chapter.title,
      isRead: marks.read,
      isBookmarked: marks.bookmarked,
      isDownloaded: saved != null,
      lastPageRead: saved?.progress ?? 0,
      isSelected: _selection.contains(chapter.id),
      onTap: selecting
          ? () => _toggleSelected(chapter.id)
          : () => _openChapter(chapter, series),
      onLongPress: () => _toggleSelected(chapter.id),
      onLongPressAt: selecting
          ? null
          : (point) => _chapterMenu(
              point,
              chapter,
              series,
              saved,
              job,
              marks: marks,
              readingOrder: readingOrder,
            ),
    );
  }

  void _copyTag(String tag) {
    unawaited(Clipboard.setData(ClipboardData(text: tag)));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.copiedToClipboard)));
  }

  Future<void> _showFilters() => showAppBottomSheet<void>(
    context: context,
    builder: (sheet) => StatefulBuilder(
      builder: (context, setSheetState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(title: context.l10n.filter),
          SwitchListTile(
            title: Text(context.l10n.filterOptionDownloaded),
            value: _onlyDownloaded,
            onChanged: (value) {
              setState(() => _onlyDownloaded = value);
              setSheetState(() {});
            },
          ),
          SwitchListTile(
            title: Text(context.l10n.filterOptionUnread),
            value: _unreadOnly,
            onChanged: (value) {
              setState(() => _unreadOnly = value);
              setSheetState(() {});
            },
          ),
          SwitchListTile(
            title: Text(context.l10n.filterOptionBookmarked),
            value: _bookmarkedOnly,
            onChanged: (value) {
              setState(() => _bookmarkedOnly = value);
              setSheetState(() {});
            },
          ),
          SwitchListTile(
            title: Text(localText(context, 'Newest first', 'Terbaru dahulu')),
            value: _descending,
            onChanged: (value) {
              setState(() => _descending = value);
              setSheetState(() {});
            },
          ),
        ],
      ),
    ),
  );

  Future<void> _downloadChoices() async {
    final chapters = await _chapters;
    final series = await _library;
    if (!mounted) return;
    final saved = {
      for (final chapter in series?.chapters ?? <LocalChapter>[]) chapter.id,
    };
    final remaining = chapters
        .where((chapter) => !saved.contains(chapter.id))
        .toList();
    // Oldest first, as chapters are read.
    final ordered = remaining.reversed.toList(growable: false);
    final unread = [
      for (final chapter in ordered)
        if (!(_marks[chapter.id]?.read ?? false)) chapter,
    ];
    final choice = await showAppBottomSheet<List<LocalSourceChapter>>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(
            title: localText(sheet, 'Save to device', 'Simpan ke perangkat'),
          ),
          for (final (chapters, title) in [
            (unread.take(1).toList(), sheet.l10n.downloadNextChapter),
            (unread.take(5).toList(), sheet.l10n.downloadNextChaptersN(5)),
            (unread.take(10).toList(), sheet.l10n.downloadNextChaptersN(10)),
            (unread, sheet.l10n.downloadUnreadChapters),
            (ordered, sheet.l10n.downloadAllChapters),
          ])
            ListTile(
              leading: const Icon(FluentIcons.arrow_circle_down_24_regular),
              title: Text(title),
              trailing: chapters.isEmpty ? null : Text('${chapters.length}'),
              enabled: chapters.isNotEmpty,
              onTap: chapters.isEmpty
                  ? null
                  : () => Navigator.pop(sheet, chapters),
            ),
          SizedBox(height: MediaQuery.paddingOf(sheet).bottom),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    for (final chapter in choice) {
      if (!mounted) break;
      await _download(chapter);
    }
  }

  Widget _selectionBar(
    List<LocalSourceChapter> shown,
    Map<String, LocalChapter> downloaded,
    Map<String, LocalDownload> jobs,
    LocalChapterMarks Function(String id) marksOf,
  ) {
    final l10n = context.l10n;
    final ids = _selection.toList(growable: false);
    final allBookmarked = ids.every((id) => marksOf(id).bookmarked);
    final unsaved = [
      for (final chapter in shown)
        if (_selection.contains(chapter.id) &&
            !downloaded.containsKey(chapter.id) &&
            !jobs.containsKey(chapter.id))
          chapter,
    ];
    return SelectionActionBar(
      leading: [
        IconButton(
          tooltip: l10n.clearSelection,
          icon: const Icon(FluentIcons.dismiss_24_regular),
          onPressed: () => setState(_selection.clear),
        ),
        Text('${ids.length}', style: context.textTheme.titleMedium),
      ],
      actions: [
        IconButton(
          tooltip: l10n.selectAll,
          icon: const Icon(FluentIcons.select_all_on_24_regular),
          onPressed: () => setState(
            () => _selection.addAll(shown.map((chapter) => chapter.id)),
          ),
        ),
        IconButton(
          tooltip: l10n.markAsRead,
          icon: const Icon(Icons.done_all_rounded),
          onPressed: () => _mark(ids, read: true),
        ),
        IconButton(
          tooltip: l10n.markAsUnread,
          icon: const Icon(Icons.remove_done_rounded),
          onPressed: () => _mark(ids, read: false),
        ),
        IconButton(
          tooltip: allBookmarked ? l10n.removeBookmark : l10n.bookmark,
          icon: Icon(
            allBookmarked
                ? FluentIcons.bookmark_off_24_regular
                : FluentIcons.bookmark_24_regular,
          ),
          onPressed: () => _mark(ids, bookmarked: !allBookmarked),
        ),
        IconButton(
          tooltip: localText(context, 'Save to device', 'Simpan ke perangkat'),
          icon: const Icon(FluentIcons.arrow_circle_down_24_regular),
          onPressed: unsaved.isEmpty
              ? null
              : () async {
                  setState(_selection.clear);
                  for (final chapter in unsaved) {
                    if (!mounted) break;
                    await _download(chapter);
                  }
                },
        ),
      ],
      clearsSystemNav: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? image(Uri? url) => url == null
        ? null
        : NetworkImage(url.toString(), headers: _manga.coverHeaders);
    final homepage = _manga.webUrl ?? widget.extension.homepage;
    // The copy saved on this iPhone stands in when the source's cover link
    // was not kept (covers the runtime proxies change address every launch).
    final kept = widget.services.catalog.keptCover(_seriesId);
    final ImageProvider? keptCover = kept == null ? null : FileImage(kept);
    // A picked cover is a local file and wins over the source's covers.
    final cover = _customCover != null
        ? FileImage(_customCover!)
        : image(_manga.cover) ?? keptCover;
    final fallbackCover = image(_manga.coverFallback) ?? keptCover;
    final coverBehindBar =
        supportsAppleGlass(context) && (cover != null || fallbackCover != null);
    return Scaffold(
      extendBodyBehindAppBar: coverBehindBar,
      appBar: MangaDetailsAppBar(
        title: Text(_manga.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        coverBehindBar: coverBehindBar,
        scrollOffset: _scrollOffset,
        actions: [
          AppleGlassToolbar(
            joined: true,
            actions: [
              AppleGlassToolbarAction(
                id: 'local-manga-downloads',
                symbol: 'arrow.down.circle',
                label: localText(context, 'Save chapters', 'Simpan chapter'),
                onPressed: () => _changeDownload(_downloadChoices),
                fallbackIcon: FluentIcons.arrow_circle_down_24_regular,
              ),
              AppleGlassToolbarAction(
                id: 'local-manga-options',
                symbol: 'ellipsis',
                label: context.l10n.more,
                onPressed: null,
                fallbackIcon: FluentIcons.more_horizontal_24_regular,
                menu: [
                  AppleGlassToolbarMenuItem(
                    id: 'refresh',
                    title: context.l10n.refresh,
                    symbol: 'arrow.clockwise',
                    onSelected: _refresh,
                    fallbackIcon: FluentIcons.arrow_clockwise_24_regular,
                  ),
                  AppleGlassToolbarMenuItem(
                    id: 'edit-cover',
                    title: context.l10n.editCover,
                    symbol: 'photo',
                    onSelected: _editCover,
                    fallbackIcon: FluentIcons.image_edit_24_regular,
                  ),
                  if (_customCover != null)
                    AppleGlassToolbarMenuItem(
                      id: 'reset-cover',
                      title: localText(
                        context,
                        'Use source cover',
                        'Pakai cover sumber',
                      ),
                      symbol: 'arrow.uturn.backward',
                      onSelected: _resetCover,
                      fallbackIcon: FluentIcons.arrow_undo_24_regular,
                    ),
                  if (homepage != null)
                    AppleGlassToolbarMenuItem(
                      id: 'home',
                      title: context.l10n.openHomepage,
                      symbol: 'globe',
                      onSelected: () =>
                          _openLocalSourceHomepage(context, homepage),
                      fallbackIcon: FluentIcons.globe_24_regular,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<LocalSourceChapter>>(
          future: _chapters,
          builder: (context, snapshot) => FutureBuilder<LocalSeries?>(
            future: _library,
            builder: (context, library) {
              final chapters = snapshot.data ?? const [];
              final series = library.data;
              final downloaded = {
                for (final chapter in series?.chapters ?? <LocalChapter>[])
                  chapter.id: chapter,
              };
              // The newest read, saved or online, as History shows it.
              final reads = [
                for (final chapter in downloaded.values)
                  if (chapter.lastReadAt case final at?)
                    (id: chapter.id, at: at),
                if (_lastOnline case final online?)
                  (id: online.chapterId, at: online.lastReadAt),
              ]..sort((a, b) => b.at.compareTo(a.at));
              final resumeChapter = chapters
                  .where((chapter) => chapter.id == reads.firstOrNull?.id)
                  .firstOrNull;
              final readingOrder = widget.extension.chaptersNewestFirst
                  ? chapters.reversed
                  : chapters;
              final firstChapter = resumeChapter ?? readingOrder.firstOrNull;
              final descending = widget.extension.chaptersNewestFirst
                  ? chapters
                  : chapters.reversed;
              final orderedForReading = readingOrder.toList(growable: false);
              const noMarks = (read: false, bookmarked: false);
              LocalChapterMarks marksOf(String id) => _marks[id] ?? noMarks;
              final shown = (_descending ? descending : readingOrder)
                  .where(
                    (chapter) =>
                        (!_onlyDownloaded ||
                            downloaded.containsKey(chapter.id)) &&
                        (!_unreadOnly || !marksOf(chapter.id).read) &&
                        (!_bookmarkedOnly || marksOf(chapter.id).bookmarked),
                  )
                  .toList();
              return ValueListenableBuilder<List<LocalDownload>>(
                valueListenable: _queue,
                builder: (context, jobs, _) {
                  final byChapter = {
                    for (final job in jobs)
                      if (job.request.seriesId == _seriesId)
                        job.request.chapterId: job,
                  };
                  final list = NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.depth == 0 &&
                          notification.metrics.axis == Axis.vertical) {
                        _scrollOffset.value = notification.metrics.pixels;
                      }
                      return false;
                    },
                    // The arrow shows under the bar the page scrolls behind.
                    child: PullToRefresh(
                      onRefresh: _refresh,
                      top: MediaQuery.paddingOf(context).top,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: LocalMangaHero(
                              title: _manga.title,
                              source:
                                  '${widget.extension.name} (${widget.extension.language.toUpperCase()})',
                              author: _manga.author.isEmpty
                                  ? null
                                  : _manga.author,
                              status:
                                  _manga.status >= 0 &&
                                      _manga.status < MangaStatus.values.length
                                  ? MangaStatus.values[_manga.status]
                                  : MangaStatus.unknown,
                              cover: cover,
                              fallbackCover: fallbackCover,
                              showBackdrop: coverBehindBar,
                              onSearch: (query) => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => _LocalSourcePage(
                                    services: widget.services,
                                    extension: widget.extension,
                                    initialQuery: query,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: MangaActionButton(
                                      horizontal: supportsAppleGlass(context),
                                      active: series?.inLibrary == true,
                                      icon: _savingLibrary
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              series?.inLibrary == true
                                                  ? FluentIcons.heart_24_filled
                                                  : FluentIcons
                                                        .heart_24_regular,
                                            ),
                                      label: series?.inLibrary == true
                                          ? context.l10n.inLibrary
                                          : context.l10n.addToLibrary,
                                      onPressed: () => _editLibrary(series),
                                    ),
                                  ),
                                  // Same three actions as server series.
                                  Expanded(
                                    child: MangaActionButton(
                                      horizontal: supportsAppleGlass(context),
                                      icon: const Icon(
                                        FluentIcons.arrow_sync_24_regular,
                                      ),
                                      label: context.l10n.tracking,
                                      onPressed: () => showAppDialog<void>(
                                        context: context,
                                        builder: (dialog) => AlertDialog(
                                          title: Text(dialog.l10n.tracking),
                                          content: Text(
                                            localText(
                                              dialog,
                                              'Tracking with AniList, MyAnimeList and others runs on a Kuchie server. Connect one in Settings to track this series.',
                                              'Pelacakan AniList, MyAnimeList, dan lainnya berjalan di server Kuchie. Hubungkan server di Pengaturan untuk melacak seri ini.',
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dialog),
                                              child: Text(dialog.l10n.close),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: MangaActionButton(
                                      horizontal: supportsAppleGlass(context),
                                      icon: const Icon(
                                        FluentIcons.globe_24_regular,
                                      ),
                                      label: context.l10n.webView,
                                      onPressed: homepage == null
                                          ? null
                                          : () => _openLocalSourceHomepage(
                                              context,
                                              homepage,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_manga.description.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: MangaDescriptionBody(
                                  description: _manga.description,
                                  isExpanded: _descriptionExpanded,
                                  onToggleExpanded: () => setState(
                                    () => _descriptionExpanded =
                                        !_descriptionExpanded,
                                  ),
                                ),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: SeriesTagsSection(
                              tags: _manga.genres,
                              expanded: _descriptionExpanded,
                              onExpand: () => setState(
                                () => _descriptionExpanded =
                                    !_descriptionExpanded,
                              ),
                              onTagTap: (_, tag) => _copyTag(tag),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: LocalSeriesPersonal(
                              catalog: widget.services.catalog,
                              seriesId: _seriesId,
                              categories: series?.inLibrary == true
                                  ? series!.categories
                                  : null,
                              onCategoriesChanged: () => setState(() {
                                _library = widget.services.catalog.find(
                                  _seriesId,
                                );
                              }),
                            ),
                          ),
                          if (firstChapter != null)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  10,
                                ),
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                  onPressed: () =>
                                      _openChapter(firstChapter, series),
                                  child: Text(
                                    '${resumeChapter != null ? context.l10n.resume : context.l10n.start} ${firstChapter.title}',
                                  ),
                                ),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: ListTile(
                              title: Text(
                                context.l10n.noOfChapters(chapters.length),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ChapterListLayoutToggle(
                                    mode: _grid
                                        ? ChapterListMode.grid
                                        : ChapterListMode.list,
                                    onChanged: (mode) => setState(
                                      () =>
                                          _grid = mode == ChapterListMode.grid,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  ChapterHeaderButton(
                                    icon: FluentIcons.filter_24_regular,
                                    tooltip: context.l10n.filter,
                                    onPressed: _showFilters,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: ChapterCheckStatus(check: _check),
                          ),
                          if (snapshot.hasError)
                            SliverToBoxAdapter(
                              child: Center(
                                child: TextButton(
                                  onPressed: _refresh,
                                  child: Text(context.l10n.retry),
                                ),
                              ),
                            )
                          else if (!snapshot.hasData)
                            const SliverToBoxAdapter(
                              child: CenterKuchieShimmerIndicator(),
                            )
                          else if (shown.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Center(
                                  child: Text(context.l10n.noChaptersFound),
                                ),
                              ),
                            )
                          else if (_grid)
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              sliver: SliverGrid.builder(
                                itemCount: shown.length,
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 64,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 8,
                                    ),
                                itemBuilder: (_, index) {
                                  final chapter = shown[index];
                                  return _chapterGridButton(
                                    chapter,
                                    series,
                                    downloaded[chapter.id],
                                    byChapter[chapter.id],
                                    marks: marksOf(chapter.id),
                                    readingOrder: orderedForReading,
                                  );
                                },
                              ),
                            )
                          else
                            SliverList.builder(
                              itemCount: shown.length,
                              itemBuilder: (_, index) {
                                final chapter = shown[index];
                                return _chapterRow(
                                  chapter,
                                  series,
                                  downloaded[chapter.id],
                                  byChapter[chapter.id],
                                  marks: marksOf(chapter.id),
                                  readingOrder: orderedForReading,
                                );
                              },
                            ),
                          // Keeps the last rows clear of the selection bar.
                          if (_selection.isNotEmpty)
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 88),
                            ),
                        ],
                      ),
                    ),
                  );
                  // Keep one tree shape so entering selection keeps the scroll.
                  return Stack(
                    children: [
                      list,
                      if (_selection.isNotEmpty)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _selectionBar(
                            shown,
                            downloaded,
                            byChapter,
                            marksOf,
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<void> openLocalSourceChapter(
  BuildContext context, {
  required LocalCollectionServices services,
  required LocalExtension extension,
  required LocalSourceManga manga,
  required List<LocalSourceChapter> chapters,
  required LocalSourceChapter initialChapter,
  required String seriesId,
  LocalSeries? savedSeries,
}) {
  unawaited(keepLocalSourceCover(services, seriesId, manga, replace: false));
  // Swipe from the left edge to close, back to the series page.
  return Navigator.of(context).push<void>(
    ReaderSwipeBackRoute(
      builder: (_) => _LocalChapterSession(
        services: services,
        extension: extension,
        readerFormat: (
          genres: manga.genres.isNotEmpty
              ? manga.genres
              : savedSeries?.source?.genres ?? const [],
          sourceName: extension.name,
        ),
        chapters: chapters,
        initialId: initialChapter.id,
        initialTitle: initialChapter.title,
        // History needs the source reference to reopen chapters read online.
        series:
            savedSeries ??
            LocalSeries(
              id: seriesId,
              title: manga.title,
              chapters: const [],
              source: services.sources.seriesReference(
                manga,
                sourceName: extension.name,
              ),
            ),
      ),
    ),
  );
}

/// Queues [chapter] of [manga] for saving on this device.
Future<void> enqueueLocalChapterDownload(
  LocalCollectionServices services,
  LocalExtension extension,
  LocalSourceManga manga,
  String seriesId,
  LocalSourceChapter chapter,
) async {
  final locator = chapter.runtimeLocator;
  final pages = locator == null
      ? await services.sources.pages(extension.id, chapter)
      : const <Uri>[];
  await services.downloads.enqueue(
    LocalDownloadRequest(
      seriesId: seriesId,
      title: manga.title,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      source: services.sources.seriesReference(
        manga,
        sourceName: extension.name,
      ),
      pages: pages,
      runtimeChapter: locator == null
          ? null
          : (sourceId: extension.id, locator: locator),
    ),
  );
}

/// Saves the source's cover for History and the library while the runtime
/// that serves it is running. Proxied covers stop loading after a restart.
Future<void> keepLocalSourceCover(
  LocalCollectionServices services,
  String seriesId,
  LocalSourceManga manga, {
  bool replace = true,
}) async {
  final url = manga.cover ?? manga.coverFallback;
  if (url == null) return;
  final catalog = services.catalog;
  try {
    if (!replace && await catalog.sourceCoverFile(seriesId).exists()) return;
    final response = await http
        .get(url, headers: manga.coverHeaders)
        .timeout(const Duration(seconds: 20));
    final type = response.headers['content-type'] ?? '';
    if (response.statusCode != 200 ||
        type.startsWith('text/') ||
        type.contains('json')) {
      return;
    }
    await catalog.saveSourceCover(seriesId, response.bodyBytes);
  } on Exception {
    // History falls back to the source cover link and the placeholder.
  }
}

/// Reopens a chapter from History that was read online and never saved.
Future<void> openRemoteLocalChapter(
  BuildContext context,
  LocalCollectionServices services, {
  required LocalSeries series,
  required String chapterId,
  VoidCallback? onReady,
}) async {
  final sources = services.sources;
  final reference = localSeriesReference(sources, series);
  if (reference == null) throw StateError('The source is unavailable.');
  final selection = await sources.resolveSeries(reference, series.title);
  final available = await sources.chapters(
    selection.extension.id,
    selection.manga,
  );
  final chapters = selection.extension.chaptersNewestFirst
      ? available.reversed.toList(growable: false)
      : available;
  final initial = chapters.where((chapter) => chapter.id == chapterId);
  if (initial.isEmpty) throw StateError('The chapter is no longer listed.');
  if (!context.mounted) return;
  onReady?.call();
  await openLocalSourceChapter(
    context,
    services: services,
    extension: selection.extension,
    manga: selection.manga,
    chapters: chapters,
    initialChapter: initial.first,
    seriesId: series.id,
    savedSeries: series.chapters.isEmpty ? null : series,
  );
}

Future<void> openSavedLocalChapter(
  BuildContext context,
  LocalCollectionServices services,
  LocalSeries series,
  LocalChapter chapter,
) => Navigator.of(context).push<void>(
  ReaderSwipeBackRoute(
    builder: (_) => _LocalChapterSession(
      services: services,
      chapters: const [],
      initialId: chapter.id,
      initialTitle: chapter.title,
      series: series,
    ),
  ),
);

class _LocalChapterSession extends StatefulWidget {
  const _LocalChapterSession({
    required this.services,
    this.extension,
    this.readerFormat,
    required this.chapters,
    required this.initialId,
    required this.initialTitle,
    required this.series,
  });

  final LocalCollectionServices services;
  final LocalExtension? extension;
  final ReaderFormatMetadata? readerFormat;
  final List<LocalSourceChapter> chapters;
  final String initialId;
  final String initialTitle;
  final LocalSeries series;

  @override
  State<_LocalChapterSession> createState() => _LocalChapterSessionState();
}

class _LocalChapterSessionState extends State<_LocalChapterSession> {
  late var _extension = widget.extension;
  late final _chapters = {
    for (final chapter in widget.chapters) chapter.id: chapter,
  };
  late final _saved = {
    for (final chapter in widget.series.chapters) chapter.id: chapter,
  };
  List<LocalReaderChapterEntry> get _entries => [
    for (final chapter in _chapters.values)
      LocalReaderChapterEntry(
        id: chapter.id,
        title: chapter.title,
        saved: _saved[chapter.id],
      ),
    for (final chapter in _saved.values)
      if (!_chapters.containsKey(chapter.id))
        LocalReaderChapterEntry(
          id: chapter.id,
          title: chapter.title,
          saved: chapter,
        ),
  ];
  late Future<LocalReaderChapterContent> _initial = _load(widget.initialId);
  final _client = http.Client();
  final _previews = <String, LocalPreviewPages>{};
  final _requests = <String, Future<LocalReaderChapterContent>>{};
  Future<Directory>? _directory;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    if (_extension == null) unawaited(_loadOtherChapters());
  }

  Future<void> _loadOtherChapters() async {
    final sources = widget.services.sources;
    final reference = localSeriesReference(sources, widget.series);
    if (reference == null) return;
    try {
      final selection = await sources.resolveSeries(
        reference,
        widget.series.title,
      );
      final chapters = await sources.chapters(
        selection.extension.id,
        selection.manga,
      );
      if (!mounted) return;
      setState(() {
        _extension = selection.extension;
        final ordered = selection.extension.chaptersNewestFirst
            ? chapters.reversed
            : chapters;
        _chapters.addEntries(
          ordered.map((chapter) => MapEntry(chapter.id, chapter)),
        );
      });
    } on Exception {
      // The local chapter picker stays usable while its source is offline.
    } on StateError {
      // Installed source was disabled or removed.
    }
  }

  Future<LocalReaderChapterContent> _load(String id) {
    if (_saved[id] case final chapter?) {
      return Future.value(LocalReaderChapterContent(chapter: chapter));
    }
    return _requests.putIfAbsent(id, () async {
      try {
        final chapter = _chapters[id]!;
        final pages = await widget.services.sources.chapterPages(
          _extension!.id,
          chapter,
        );
        if (_closed) throw const LocalTransferCancelled();
        final directory = await (_directory ??= Directory.systemTemp.createTemp(
          'kuchie-preview-',
        ));
        if (_closed) throw const LocalTransferCancelled();
        final progress = await widget.services.catalog.remoteProgress(
          widget.series.id,
          chapter.id,
        );
        if (_closed) throw const LocalTransferCancelled();
        final session = LocalPreviewPages(
          directory: Directory('${directory.path}/${_previews.length}'),
          chapterId: chapter.id,
          title: chapter.title,
          urls: [for (final page in pages) page.url],
          headers: [for (final page in pages) page.headers],
          client: _client,
          isCancelled: () => _closed,
          progress: progress,
        );
        _previews[id] = session;
        return LocalReaderChapterContent(
          chapter: session.chapter,
          ephemeral: true,
          preparePage: session.prepare,
        );
      } catch (_) {
        unawaited(_requests.remove(id));
        rethrow;
      }
    });
  }

  Future<void> _clean() async {
    try {
      final directory = await _directory;
      if (directory == null) return;
      await Future.wait([
        for (final preview in _previews.values) preview.settle(),
      ]);
      await directory.delete(recursive: true);
    } on FileSystemException {
      // The system can purge temporary storage.
    }
  }

  @override
  void dispose() {
    _closed = true;
    _client.close();
    unawaited(_clean());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<LocalReaderChapterContent>(
        future: _initial,
        initialData: switch (_saved[widget.initialId]) {
          final chapter? => LocalReaderChapterContent(chapter: chapter),
          _ => null,
        },
        builder: (context, snapshot) {
          if (snapshot.data case final content?) {
            return LocalReader(
              series: widget.series,
              chapter: content.chapter,
              catalog: widget.services.catalog,
              readerFormat: widget.readerFormat,
              ephemeral: content.ephemeral,
              preparePage: content.preparePage,
              chapterEntries: _entries,
              loadChapter: _load,
            );
          }
          return Scaffold(
            appBar: detailNavigationAppBar(
              context,
              title: Text(widget.initialTitle),
            ),
            body: Center(
              child: snapshot.hasError
                  ? OutlinedButton(
                      onPressed: () =>
                          setState(() => _initial = _load(widget.initialId)),
                      child: Text(context.l10n.retry),
                    )
                  : const CircularProgressIndicator(),
            ),
          );
        },
      );
}
