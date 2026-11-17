import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/enum.dart';
import '../../../constants/language_list.dart';
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
import '../../../widgets/kuchie_character_motion.dart';
import '../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../widgets/popup_widgets/app_dialog.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/selection_action_bar.dart';
import '../../../widgets/server_image.dart';
import '../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../widgets/touch_tab_pager.dart';
import '../../browse_center/presentation/browse/browse_no_search_results.dart';
import '../../browse_center/presentation/extension/widgets/extension_catalog_tile.dart';
import '../../browse_center/presentation/extension/widgets/extension_info_content.dart';
import '../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart'
    show ChapterMenuRow, menuAnchorForPoint;
import '../../manga_book/presentation/manga_details/widgets/chapter_list_mode_toggle.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_action_button.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_cover_hero.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_description.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_details_app_bar.dart';
import '../../manga_book/presentation/reader/controller/auto_webtoon.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../data/local_catalog.dart';
import '../data/local_collection_services.dart';
import '../data/local_download_queue.dart';
import '../data/local_mihon_runtime.dart';
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
    unawaited(_loadSourcePreferences());
  }

  Future<void> _loadSourcePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pinned.addAll(prefs.getStringList('localPinnedSources') ?? const []);
      _lastUsed ??= prefs.getString('localLastSource');
      _languages ??= prefs.getStringList('localBrowseLanguages')?.toSet();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _tabChanged() => setState(() {});

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

  Future<void> _install(
    LocalSourcePackage package, {
    required bool update,
  }) async {
    final accepted = await localConfirm(
      context,
      update
          ? localText(context, 'Update extension?', 'Perbarui ekstensi?')
          : localText(context, 'Install extension?', 'Pasang ekstensi?'),
      '${package.name} ${package.version}\n${package.repository.host}',
    );
    if (accepted && mounted) {
      await _perform(package.id, () async {
        try {
          await _sources.install(package);
        } on LocalSourceUntrustedException catch (error) {
          // Mihon's "untrusted extension": the APK verifies, but its signer
          // is not the store's key. Install only if the reader trusts it.
          if (!mounted || !await _trustSigner(package, error.signer)) return;
          await _sources.install(package, trustSigner: error.signer);
        }
      });
    }
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

  void _goToTab(int index) => _tabs.animateTo(
    index,
    duration: context.reduceMotion ? Duration.zero : kTabScrollDuration,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final index = _tabs.index;
    final labels = [l10n.sources, l10n.extensions, l10n.migrate];
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
              subTitle: snapshot.error is FormatException
                  ? (snapshot.error! as FormatException).message
                  : null,
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
    Widget Function(T) buildTile,
  ) => [
    if (entries.isNotEmpty) ...[
      SliverToBoxAdapter(child: ListTile(title: Text(title))),
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
    Widget tile(LocalExtension extension) => ListTile(
      leading: _extensionIcon(extension.icon),
      title: Text(
        extension.name,
        style: supportsAppleGlass(context)
            ? context.textTheme.titleMedium
            : null,
      ),
      subtitle: Text(_languageName(extension.language)),
      onTap: () => _openSource(extension),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (extension.supportsLatest)
            IconButton(
              tooltip: context.l10n.latest,
              icon: const Icon(FluentIcons.news_24_regular),
              onPressed: () => _openSource(extension, latest: true),
            ),
          IconButton(
            tooltip: _pinned.contains(extension.id)
                ? context.l10n.unpinSource
                : context.l10n.pinSource,
            icon: Icon(
              _pinned.contains(extension.id)
                  ? FluentIcons.pin_24_filled
                  : FluentIcons.pin_24_regular,
            ),
            onPressed: () async {
              setState(() {
                if (!_pinned.remove(extension.id)) _pinned.add(extension.id);
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setStringList('localPinnedSources', _pinned.toList());
            },
          ),
        ],
      ),
    );
    return _scroll(
      context,
      [
        ..._section(languageMap['pinned']?.displayName ?? '', pinned, tile),
        ..._section(languageMap['lastUsed']?.displayName ?? '', lastUsed, tile),
        for (final MapEntry(key: language, value: entries) in remaining.entries)
          ..._section(_languageName(language), entries, tile),
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
    final updates = grouped.updates;
    final packages = grouped.byLanguage;
    final updatedIds = {for (final package in updates) package.id};
    final installedList = data.extensions
        .where(
          (extension) =>
              !updatedIds.contains(extension.packageId) &&
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
        trailing: TextButton(
          onPressed: install,
          child: Text(
            _busyExtension == package.id ? context.l10n.processing : label,
          ),
        ),
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

class _LocalMigratePage extends StatelessWidget {
  const _LocalMigratePage({this.onImportManga, this.onRestoreBackup});

  final VoidCallback? onImportManga;
  final VoidCallback? onRestoreBackup;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(
      16,
      AppleGlassFloatingHeader.insetOf(context) + 8,
      16,
      MediaQuery.paddingOf(context).bottom + 16,
    ),
    children: [
      if (onImportManga != null)
        ListTile(
          leading: const Icon(FluentIcons.folder_open_24_regular),
          title: Text(localText(context, 'Import manga', 'Impor manga')),
          subtitle: const Text('CBZ, ZIP'),
          onTap: onImportManga,
        ),
      if (onRestoreBackup != null)
        ListTile(
          leading: const Icon(FluentIcons.arrow_counterclockwise_24_regular),
          title: Text(
            localText(
              context,
              'Restore local backup',
              'Pulihkan cadangan lokal',
            ),
          ),
          onTap: onRestoreBackup,
        ),
    ],
  );
}

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
    await _action(() async {
      for (final store in stores) {
        await widget.sources.refreshRepository(store.url);
      }
    });
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
    });
    try {
      await widget.sources.addRepository(url);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (kDebugMode) debugPrint('Kuchie extension store failed: $error');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (error) {
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
            errorMaxLines: 3,
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
  });

  final LocalCollectionServices services;
  final LocalExtension extension;
  final bool latest;

  @override
  State<_LocalSourcePage> createState() => _LocalSourcePageState();
}

enum _SourceTab { popular, latest, results }

class _LocalSourcePageState extends State<_LocalSourcePage> {
  late _SourceTab _tab = widget.latest ? _SourceTab.latest : _SourceTab.popular;
  late final _paging = ServerPagingController<LocalSourceManga>(
    firstPageKey: 1,
    fetchPage: _loadPage,
  );
  bool _showSearch = false;
  bool _showList = false;
  bool _showingSavedResults = false;
  int _requestGeneration = 0;
  String _query = '';

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
    if (value == null || value.isEmpty) {
      _select(_SourceTab.popular);
    } else {
      _query = value;
      _select(_SourceTab.results);
    }
  }

  void _open(LocalSourceManga manga) =>
      openLocalSourceManga(context, widget.services, widget.extension, manga);

  Future<void> _showFilter() => showAppBottomSheet<void>(
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
      l10n.filter,
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
    return Scaffold(
      appBar: detailNavigationAppBar(
        context,
        title: const SizedBox.shrink(),
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
                        onSelected: () =>
                            _openLocalSourceHomepage(context, url),
                        fallbackIcon: FluentIcons.globe_24_regular,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  extension.name,
                  style: context.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (extension.homepage case final url?)
                  Text(
                    url.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (_showingSavedResults)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      localText(
                        context,
                        'Showing saved results',
                        'Menampilkan hasil tersimpan',
                      ),
                      style: context.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          if (_showSearch)
            Padding(
              padding: KEdgeInsets.h16v4.size,
              child: SearchField(
                initialText: _query,
                labelText: l10n.searchSourceHint(extension.name),
                onClose: () => setState(() => _showSearch = false),
                onSubmitted: _search,
              ),
            ),
          Expanded(
            child: AppleGlassFloatingHeader.enabled(context)
                ? AppleGlassFloatingHeader.overlay(
                    header: segments,
                    child: _resultList(),
                  )
                : Column(
                    children: [
                      segments,
                      Expanded(child: _resultList()),
                    ],
                  ),
          ),
        ],
      ),
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
        firstPageErrorIndicatorBuilder: (_) => Emoticons(
          illustration: KuchieCharacterPhase.fetchFailed,
          title: localText(
            context,
            'Could not load manga',
            'Manga gagal dimuat',
          ),
          button: TextButton(
            onPressed: fetchNextPage,
            child: Text(context.l10n.retry),
          ),
        ),
        noItemsFoundIndicatorBuilder: (_) => Emoticons(
          illustration: KuchieCharacterPhase.noResults,
          title: context.l10n.noMangaFound,
          button: TextButton(
            onPressed: _paging.refresh,
            child: Text(context.l10n.refresh),
          ),
        ),
        newPageErrorIndicatorBuilder: (_) => TextButton(
          onPressed: fetchNextPage,
          child: Text(context.l10n.retry),
        ),
        itemBuilder: (context, manga, index) => _showList
            ? ListTile(
                leading: ClipRRect(
                  borderRadius: KBorderRadius.r8.radius,
                  child: SizedBox(
                    width: 40,
                    height: 60,
                    child: _LocalCover(
                      url: manga.cover,
                      fallback: manga.coverFallback,
                      headers: manga.coverHeaders,
                    ),
                  ),
                ),
                title: Text(manga.title),
                onTap: () => _open(manga),
              )
            : Semantics(
                button: true,
                label: manga.title,
                excludeSemantics: true,
                child: MangaCoverGridTile(
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
                ),
              ),
      );
      return RefreshIndicator(
        edgeOffset: inset,
        onRefresh: () async => _paging.refresh(),
        child: _showList
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
                      context.windowSizeClass == WindowSizeClass.compact
                      ? 2
                      : 4,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  childAspectRatio: .74,
                ),
                builderDelegate: delegate,
              ),
      );
    },
  );
}

class _LocalCover extends StatelessWidget {
  const _LocalCover({required this.url, this.fallback, required this.headers});

  final Uri? url;
  final Uri? fallback;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _localCoverImage(
      url == null ? null : NetworkImage(url.toString(), headers: headers),
      fallback == null
          ? null
          : NetworkImage(fallback.toString(), headers: headers),
      constraints.hasBoundedWidth
          ? (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(1, 1200)
          : null,
      const Center(child: Icon(FluentIcons.book_24_regular)),
    ),
  );
}

void _openLocalSourceHomepage(BuildContext context, Uri url) {
  // Shared in-app WebView keeps an explicit external browser action.
  unawaited(openInAppWebView(context, url.toString()));
}

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
  });

  final String title;
  final String source;
  final ImageProvider? cover;
  final ImageProvider? fallbackCover;
  final String? author;
  final MangaStatus? status;
  final bool showBackdrop;

  Widget _image(
    BuildContext context, {
    required double width,
    bool backdrop = false,
  }) {
    final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, backdrop ? 720 : 1200);
    final placeholder = backdrop
        ? const SizedBox.expand()
        : const Center(child: Icon(FluentIcons.book_24_regular));
    return _localCoverImage(cover, fallbackCover, cacheWidth, placeholder);
  }

  @override
  Widget build(BuildContext context) {
    const coverWidth = kDescriptiveCoverWidth - kMangaCoverCardInset;
    final header = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        12,
        MediaQuery.paddingOf(context).top + 16,
        16,
        12,
      ),
      child: Row(
        spacing: 12,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: ColoredBox(
              color: context.colorScheme.surfaceContainer,
              child: SizedBox(
                width: coverWidth,
                height: mangaCoverBoxHeight(coverWidth, coverInset: 0),
                child: _image(context, width: coverWidth),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(title, style: context.textTheme.titleLarge),
                if (author != null)
                  Text(author!, style: context.textTheme.bodyMedium),
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (status case final status?
                        when status != MangaStatus.unknown) ...[
                      Icon(
                        status.icon,
                        color: context.textTheme.bodySmall?.color,
                        size: 16,
                      ),
                      Text(
                        status.toLocale(context),
                        style: context.textTheme.bodySmall,
                      ),
                      Text('•', style: context.textTheme.bodySmall),
                    ],
                    Text(source, style: context.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!showBackdrop || (cover == null && fallbackCover == null)) {
      return header;
    }
    return LayoutBuilder(
      builder: (context, constraints) => MangaCoverHero(
        backdrop: _image(context, width: constraints.maxWidth, backdrop: true),
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

  Future<List<LocalSourceChapter>> _load() =>
      widget.services.sources.chapters(widget.extension.id, widget.manga);

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
      if (!mounted || request != _personalRequest) return;
      setState(() {
        _marks = marks;
        _customCover = meta.cover;
      });
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  @override
  void dispose() {
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
  }

  Future<void> _toggleLibrary(bool inLibrary) async {
    if (_savingLibrary) return;
    _savingLibrary = true;
    try {
      if (inLibrary &&
          !await localConfirm(
            context,
            context.l10n.removeFromLibrary,
            context.l10n.duplicatesRemoveConfirm(1),
          )) {
        return;
      }
      if (!mounted) return;
      await widget.services.catalog.setInLibrary(
        seriesId: _seriesId,
        title: _manga.title,
        inLibrary: !inLibrary,
        source: widget.services.sources.seriesReference(
          _manga,
          sourceName: widget.extension.name,
        ),
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) localFailure(context, error);
    } finally {
      _savingLibrary = false;
    }
  }

  Future<void> _download(LocalSourceChapter chapter) async {
    if (!_busy.add(chapter.id)) return;
    setState(() {});
    try {
      final locator = chapter.runtimeLocator;
      final pages = locator == null
          ? await widget.services.sources.pages(widget.extension.id, chapter)
          : const <Uri>[];
      await _queue.enqueue(
        LocalDownloadRequest(
          seriesId: _seriesId,
          title: _manga.title,
          chapterId: chapter.id,
          chapterTitle: chapter.title,
          source: widget.services.sources.seriesReference(
            _manga,
            sourceName: widget.extension.name,
          ),
          pages: pages,
          runtimeChapter: locator == null
              ? null
              : (sourceId: widget.extension.id, locator: locator),
        ),
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
    final dateLabel = date == null
        ? null
        : MaterialLocalizations.of(context).formatShortDate(date.toLocal());
    final subtitle = saved != null
        ? localText(context, 'Saved to device', 'Tersimpan di perangkat')
        : job == null
        ? dateLabel
        : job.pageCount == 0
        ? null
        : '${job.done} / ${job.pageCount}';
    final dimmed = marks.read && !selected;
    return GestureDetector(
      onLongPressStart: (details) => selecting
          ? _toggleSelected(chapter.id)
          : _chapterMenu(
              details.globalPosition,
              chapter,
              series,
              saved,
              job,
              marks: marks,
              readingOrder: readingOrder,
            ),
      child: ListTile(
        selected: selected,
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 4, 12, 4),
        title: Text(
          chapter.title,
          style: dimmed
              ? TextStyle(color: context.colorScheme.onSurfaceVariant)
              : null,
        ),
        leading: selecting
            ? Icon(
                selected
                    ? FluentIcons.checkmark_circle_24_filled
                    : FluentIcons.circle_24_regular,
                color: selected ? context.colorScheme.primary : null,
              )
            : marks.bookmarked
            ? Icon(
                FluentIcons.bookmark_24_filled,
                color: context.colorScheme.primary,
              )
            : null,
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: dimmed
                    ? TextStyle(
                        color: context.colorScheme.onSurfaceVariant.withValues(
                          alpha: .7,
                        ),
                      )
                    : null,
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
        onTap: selecting
            ? () => _toggleSelected(chapter.id)
            : () => _openChapter(chapter, series),
      ),
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
    final selected = _selection.contains(chapter.id);
    final colors = context.colorScheme;
    return GestureDetector(
      onLongPressStart: (details) => selecting
          ? _toggleSelected(chapter.id)
          : _chapterMenu(
              details.globalPosition,
              chapter,
              series,
              saved,
              job,
              marks: marks,
              readingOrder: readingOrder,
            ),
      child: OutlinedButton(
        onPressed: selecting
            ? () => _toggleSelected(chapter.id)
            : () => _openChapter(chapter, series),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          foregroundColor: marks.read && !selected
              ? colors.onSurfaceVariant
              : null,
          side: selected ? BorderSide(color: colors.primary, width: 2) : null,
          backgroundColor: selected
              ? colors.primary.withValues(alpha: .18)
              : saved == null
              ? null
              : colors.primaryContainer,
        ),
        child: Text(chapter.title, maxLines: 2, textAlign: TextAlign.center),
      ),
    );
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
    final count = await showAppBottomSheet<int>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(
            title: localText(sheet, 'Save to device', 'Simpan ke perangkat'),
          ),
          for (final (count, title) in [
            (1, sheet.l10n.downloadNextChapter),
            (5, sheet.l10n.downloadNextChaptersN(5)),
          ])
            ListTile(
              leading: const Icon(FluentIcons.arrow_circle_down_24_regular),
              title: Text(title),
              enabled: remaining.isNotEmpty,
              onTap: remaining.isEmpty
                  ? null
                  : () => Navigator.pop(sheet, count),
            ),
        ],
      ),
    );
    if (count == null || !mounted) return;
    for (final chapter in remaining.reversed.take(count)) {
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
    // A picked cover is a local file and wins over the source's covers.
    final cover = _customCover != null
        ? FileImage(_customCover!)
        : image(_manga.cover);
    final fallbackCover = image(_manga.coverFallback);
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
              final resume = [
                ...downloaded.values.where(
                  (chapter) => chapter.lastReadAt != null,
                ),
              ]..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
              final resumeChapter = chapters
                  .where((chapter) => chapter.id == resume.firstOrNull?.id)
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
                    child: RefreshIndicator(
                      onRefresh: _refresh,
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
                                      icon: Icon(
                                        series?.inLibrary == true
                                            ? FluentIcons.heart_24_filled
                                            : FluentIcons.heart_24_regular,
                                      ),
                                      label: series?.inLibrary == true
                                          ? context.l10n.inLibrary
                                          : context.l10n.addToLibrary,
                                      onPressed: () => _toggleLibrary(
                                        series?.inLibrary == true,
                                      ),
                                    ),
                                  ),
                                  if (homepage != null)
                                    Expanded(
                                      child: MangaActionButton(
                                        horizontal: supportsAppleGlass(context),
                                        icon: const Icon(
                                          FluentIcons.globe_24_regular,
                                        ),
                                        label: context.l10n.webView,
                                        onPressed: () =>
                                            _openLocalSourceHomepage(
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
                          if (_manga.genres.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final genre
                                        in _descriptionExpanded
                                            ? _manga.genres
                                            : _manga.genres.take(3))
                                      Chip(label: Text(genre)),
                                  ],
                                ),
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
                                  AppleGlassToolbarButton(
                                    id: 'manga-chapter-filters',
                                    symbol: 'line.3.horizontal.decrease',
                                    label: context.l10n.filter,
                                    onPressed: _showFilters,
                                    fallbackIcon: FluentIcons.filter_24_regular,
                                  ),
                                ],
                              ),
                            ),
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
                                      maxCrossAxisExtent: 82,
                                      mainAxisExtent: 44,
                                      crossAxisSpacing: 6,
                                      mainAxisSpacing: 6,
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
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
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

/// Reopens a chapter from History that was read online and never saved.
Future<void> openRemoteLocalChapter(
  BuildContext context,
  LocalCollectionServices services, {
  required LocalSeries series,
  required String chapterId,
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
  MaterialPageRoute(
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
