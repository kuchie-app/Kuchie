// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/enum.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_page_frame.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/ios/apple_glass_capability.dart';
import '../../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../../widgets/kuchie_character_motion.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../source/controller/source_controller.dart';
import 'controller/source_quick_search_controller.dart';
import 'widgets/source_short_search.dart';

String _normalizedTitle(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

// Wait for every source before deciding whether a title match is unique.
List<MangaDto>? _exactMatches(
  AsyncValue<List<QuickSearchResults>> results,
  String query,
) {
  final rows = results.value;
  if (rows == null || results.isLoading || results.isRefreshing) return null;
  if (rows.any((e) => e.mangaList.isLoading)) return null;
  final want = _normalizedTitle(query);
  return [
    for (final row in rows)
      for (final manga in row.mangaList.value ?? const <MangaDto>[])
        if (_normalizedTitle(manga.title) == want) manga,
  ];
}

class GlobalSearchScreen extends HookConsumerWidget {
  const GlobalSearchScreen({
    super.key,
    this.initialQuery,
    this.fromSuggestion = false,
  });
  final String? initialQuery;

  /// Opens a lone exact title match directly when launched from a suggestion.
  final bool fromSuggestion;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState(initialQuery?.trim());
    final queryController = useTextEditingController(text: initialQuery);
    final searchFocusNode = useFocusNode();
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
          searchFocusNode.requestFocus();
        }
      });
      return null;
    }, const []);
    final hasQuery = query.value.isNotBlank;
    final quickSearchResult = hasQuery
        ? ref.watch(quickSearchResultsProvider(query: query.value))
        : const AsyncData<List<QuickSearchResults>>([]);
    final onlyHasResults = ref.watch(globalSearchOnlyHasResultsProvider);
    final hasPinned = ref.watch(pinnedSourcesProvider).isNotEmpty;
    final decided = useRef(false);
    final cancelled = useRef(false);
    // Focus may change without rebuilding; track it directly from the node.
    final hadFocus = useRef(false);
    useEffect(() {
      void update() => hadFocus.value = searchFocusNode.hasFocus;
      update();
      searchFocusNode.addListener(update);
      return () => searchFocusNode.removeListener(update);
    }, [searchFocusNode]);
    final wasTopBar = useRef(false);

    void cancelAutoOpen() => cancelled.value = true;

    useEffect(() {
      bool onKey(KeyEvent event) {
        if (event is KeyDownEvent &&
            ModalRoute.of(context)?.isCurrent == true) {
          cancelAutoOpen();
        }
        return false;
      }

      HardwareKeyboard.instance.addHandler(onKey);
      return () => HardwareKeyboard.instance.removeHandler(onKey);
    }, const []);

    // A refresh may add sources with another exact match.
    final sourceList = fromSuggestion && hasQuery
        ? ref.watch(sourceListProvider)
        : null;
    final sourcesSettled =
        sourceList != null && !sourceList.isLoading && !sourceList.isRefreshing;
    if (fromSuggestion &&
        sourcesSettled &&
        !decided.value &&
        !cancelled.value &&
        query.value == initialQuery?.trim() &&
        initialQuery.isNotBlank) {
      final matches = _exactMatches(quickSearchResult, initialQuery!);
      if (matches != null) {
        decided.value = true;
        if (matches.length == 1) {
          final mangaId = matches.single.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Never replace a route the user opened on top meanwhile.
            if (!context.mounted ||
                cancelled.value ||
                query.value != initialQuery?.trim() ||
                ModalRoute.of(context)?.isCurrent != true) {
              return;
            }
            MangaRoute(mangaId: mangaId).pushReplacement(context);
          });
        }
      }
    }
    final glass = supportsAppleGlass(context);
    final results = Expanded(
      child: !hasQuery
          ? _SearchMessage(
              icon: FluentIcons.search_24_regular,
              label: context.l10n.searchAllSources,
            )
          : quickSearchResult.showUiWhenData(context, (data) {
              if (data.isBlank) {
                return Emoticons(
                  title: context.l10n.noSourcesFound,
                  button: TextButton(
                    onPressed: () => ref.invalidate(sourceListProvider),
                    child: Text(context.l10n.refresh),
                  ),
                );
              }
              final visible = onlyHasResults
                  ? data
                        .where((e) => (e.mangaList.value?.isNotEmpty).ifNull())
                        .toList()
                  : data;
              if (visible.isEmpty) {
                if (data.any((row) => row.mangaList.isLoading)) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                return Emoticons(
                  illustration: KuchieCharacterPhase.noResults,
                  title: context.l10n.noSearchResults,
                  button: TextButton(
                    onPressed: () =>
                        ref
                                .read(
                                  globalSearchOnlyHasResultsProvider.notifier,
                                )
                                .state =
                            false,
                    child: Text(context.l10n.allSources),
                  ),
                );
              }
              return ListView.builder(
                itemBuilder: (context, index) => SourceShortSearch(
                  source: visible[index].source,
                  mangaList: visible[index].mangaList,
                  query: query.value,
                ),
                itemCount: visible.length,
              );
            }),
    );
    final chips = _SearchFilterChips(
      hasPinned: hasPinned,
      onInteract: cancelAutoOpen,
    );
    // The shell slot mounts a frame later; restore focus only if the old field held it.
    final topBar = showsMergedTopBar(context);
    final restoreFocus = topBar && !wasTopBar.value && hadFocus.value;
    wasTopBar.value = topBar;
    final searchField = SearchField(
      controller: queryController,
      focusNode: searchFocusNode,
      autofocus: restoreFocus,
      hintText: context.l10n.searchAllSources,
      onChanged: (_) => cancelAutoOpen(),
      onSubmitted: (value) {
        cancelAutoOpen();
        query.value = value?.trim();
      },
    );
    final searchTitleBox = Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: searchField,
      ),
    );
    final content = Listener(
      onPointerDown: (_) => cancelAutoOpen(),
      onPointerSignal: (_) => cancelAutoOpen(),
      child: NotificationListener<UserScrollNotification>(
        onNotification: (_) {
          cancelAutoOpen();
          return false;
        },
        child: Scaffold(
          appBar: context.usesDesktopShell || glass
              ? null
              : AppBar(
                  leading: detailNavigationBackButton(context),
                  title: Text(context.l10n.globalSearch),
                  bottom: PreferredSize(
                    preferredSize: kCalculateAppBarBottomSize([true]),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width:
                                context.windowSizeClass >=
                                    WindowSizeClass.expanded
                                ? context.widthScale(scale: .5)
                                : null,
                            child: Padding(
                              padding: KEdgeInsets.h16v4.size,
                              child: searchField,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          body: context.usesDesktopShell
              ? SafeArea(
                  child: Column(
                    children: [
                      topBar
                          ? Semantics(
                              header: true,
                              namesRoute: true,
                              label: context.l10n.globalSearch,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ).onDesktopPageLine(context, top: true),
                                child: chips,
                              ),
                            )
                          : Semantics(
                              header: true,
                              namesRoute: true,
                              label: context.l10n.globalSearch,
                              child: _DesktopHeader(
                                hasPinned: hasPinned,
                                chips: chips,
                                searchField: searchField,
                              ),
                            ),
                      results,
                    ],
                  ),
                )
              : glass
              ? SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        // The back button carries its own edge inset.
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          0,
                          4,
                          kAppleGlassBarInset,
                          4,
                        ),
                        child: Row(
                          children: [
                            ?detailNavigationBackButton(context),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  context.l10n.globalSearch,
                                  style: context.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            _GlassSearchFilters(
                              hasPinned: hasPinned,
                              onInteract: cancelAutoOpen,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: searchField,
                      ),
                      results,
                    ],
                  ),
                )
              : Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: chips,
                    ),
                    results,
                  ],
                ),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: searchTitleBox,
      minWidth: searchTopBarSlotMinWidth(0),
      child: content,
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 28,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: context.textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}

class _GlassSearchFilters extends ConsumerWidget {
  const _GlassSearchFilters({
    required this.hasPinned,
    required this.onInteract,
  });

  final bool hasPinned;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned =
        hasPinned &&
        ref.watch(globalSearchScopeProvider) == GlobalSearchSourceFilter.pinned;
    final onlyHasResults = ref.watch(globalSearchOnlyHasResultsProvider);
    final l10n = context.l10n;
    void updateScope(GlobalSearchSourceFilter value) {
      onInteract();
      ref.read(globalSearchScopeProvider.notifier).update(value);
    }

    return AppleGlassToolbar(
      actions: [
        AppleGlassToolbarAction(
          id: 'global-search-filters',
          symbol: pinned || onlyHasResults
              ? 'line.3.horizontal.decrease.circle.fill'
              : 'line.3.horizontal.decrease',
          fallbackIcon: FluentIcons.filter_24_regular,
          label: l10n.filter,
          accessibilityValue: [
            pinned ? l10n.pinnedSources : l10n.allSources,
            if (onlyHasResults) l10n.hasResults,
          ].join(', '),
          onPressed: null,
          menu: [
            if (hasPinned)
              AppleGlassToolbarMenuItem(
                id: 'search-pinned',
                title: l10n.pinnedSources,
                symbol: 'pin',
                fallbackIcon: FluentIcons.pin_24_regular,
                selected: pinned,
                onSelected: () => updateScope(GlobalSearchSourceFilter.pinned),
              ),
            AppleGlassToolbarMenuItem(
              id: 'search-all',
              title: l10n.allSources,
              symbol: 'square.stack',
              fallbackIcon: FluentIcons.checkmark_starburst_24_regular,
              selected: !pinned,
              onSelected: () => updateScope(GlobalSearchSourceFilter.all),
            ),
            AppleGlassToolbarMenuItem(
              id: 'search-has-results',
              title: l10n.hasResults,
              symbol: 'checkmark.circle',
              fallbackIcon: FluentIcons.filter_24_regular,
              selected: onlyHasResults,
              onSelected: () {
                onInteract();
                ref.read(globalSearchOnlyHasResultsProvider.notifier).state =
                    !onlyHasResults;
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.hasPinned,
    required this.chips,
    required this.searchField,
  });
  final bool hasPinned;
  final Widget chips;
  final Widget searchField;

  @override
  Widget build(BuildContext context) {
    final backButton = detailNavigationBackButton(context);
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (backButton != null) ...[backButton, const SizedBox(width: 20)],
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: searchField,
              ),
            ),
            const SizedBox(width: 28),
            chips,
          ],
        ),
      ),
    );
  }
}

class _SearchFilterChips extends ConsumerWidget {
  const _SearchFilterChips({required this.hasPinned, required this.onInteract});
  final bool hasPinned;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(globalSearchScopeProvider);
    final onlyHasResults = ref.watch(globalSearchOnlyHasResultsProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasPinned) ...[
          FilterChip(
            showCheckmark: false,
            avatar: const Icon(FluentIcons.pin_24_regular, size: 18),
            label: Text(context.l10n.pinnedSources),
            selected: scope == GlobalSearchSourceFilter.pinned,
            onSelected: (_) {
              onInteract();
              ref
                  .read(globalSearchScopeProvider.notifier)
                  .update(GlobalSearchSourceFilter.pinned);
            },
          ),
          const SizedBox(width: 8),
        ],
        FilterChip(
          showCheckmark: false,
          avatar: const Icon(
            FluentIcons.checkmark_starburst_24_regular,
            size: 18,
          ),
          label: Text(context.l10n.all),
          selected: !hasPinned || scope == GlobalSearchSourceFilter.all,
          onSelected: (_) {
            onInteract();
            ref
                .read(globalSearchScopeProvider.notifier)
                .update(GlobalSearchSourceFilter.all);
          },
        ),
        const SizedBox(width: 12),
        FilterChip(
          showCheckmark: false,
          avatar: const Icon(FluentIcons.filter_24_regular, size: 18),
          label: Text(context.l10n.hasResults),
          selected: onlyHasResults,
          onSelected: (_) {
            onInteract();
            ref.read(globalSearchOnlyHasResultsProvider.notifier).state =
                !onlyHasResults;
          },
        ),
      ],
    );
  }
}
