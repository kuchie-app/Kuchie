// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide useTabController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_hooks/material_hooks.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/count_pill.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/desktop/desktop_view_switch.dart';
import '../../../../widgets/ios/apple_glass_floating_header.dart';
import '../../../../widgets/ios/apple_glass_segments.dart';
import '../../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../../widgets/ios/apple_page_title.dart';
import '../../../../widgets/touch_tab_pager.dart';
import '../../../migration/controller/bulk_migration_providers.dart';
import '../../../offline/data/server_reachability.dart';
import '../../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../../settings/presentation/library/widgets/persistent_search_bar/persistent_search_bar.dart';
import '../extension/controller/extension_controller.dart';
import '../extension/controller/extension_update_badge.dart';
import '../extension/widgets/extension_language_filter_dialog.dart';
import '../extension/widgets/install_extension_file.dart';
import '../source/controller/source_controller.dart' hide SourceLanguageFilter;
import '../source/widgets/source_language_filter.dart';
import 'browse_filter_panel.dart';

class BrowseScreen extends HookConsumerWidget {
  const BrowseScreen({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.children,
  });
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabController = useTabController(
      initialLength: 3,
      initialIndex: currentIndex,
      animationDuration: context.reduceMotion
          ? Duration.zero
          : kTabScrollDuration,
      keys: [context.reduceMotion],
    );

    useEffect(() {
      if (currentIndex != tabController.index) {
        tabController.animateTo(currentIndex);
      }
      return null;
    }, [currentIndex]);

    useEffect(() {
      if (currentIndex != tabController.index) {
        Future.microtask(() => onDestinationSelected(tabController.index));
      }
      return null;
    }, [tabController.index]);
    useListenable(tabController);
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final persistentBox =
        phone && ref.watch(libraryPersistentSearchBarProvider).ifNull();

    final topBar = showsMergedTopBar(context);
    final desktop = context.usesDesktopShell;
    final search = _BrowseDesktopSearch(tabIndex: tabController.index);
    final actions = <Widget>[
      if (tabController.index == 0) ...[
        if (phone && !persistentBox) ...[
          const PhoneSearchClearFilter(origin: PhoneSearchOrigin.sources),
          const PhoneSearchEntry(origin: PhoneSearchOrigin.sources),
        ],
        if (desktop) BrowseFilterButton(tabIndex: tabController.index),
      ],
      if (tabController.index == 1) ...[
        if (desktop) BrowseFilterButton(tabIndex: tabController.index),
        AppleGlassToolbarButton(
          id: 'extension-stores',
          symbol: 'puzzlepiece.extension',
          label: context.l10n.extensionStores,
          onPressed: () => const ExtensionStoreRoute().push(context),
          fallbackIcon: FluentIcons.puzzle_piece_24_regular,
        ),
        const InstallExtensionFile(),
      ],
      if (tabController.index != 2 && !desktop)
        AppleGlassToolbar(
          joined: true,
          actions: [
            if (tabController.index == 0)
              AppleGlassToolbarAction(
                id: 'filter-sources',
                symbol: 'line.3.horizontal.decrease',
                label: context.l10n.filterSources,
                onPressed: () => const SourceFilterRoute().push(context),
                fallbackIcon: FluentIcons.filter_24_regular,
              ),
            AppleGlassToolbarAction(
              id: 'languages',
              symbol: 'translate',
              label: context.l10n.languages,
              onPressed: () => showDialog(
                context: context,
                builder: (context) => tabController.index == 0
                    ? const SourceLanguageFilter()
                    : const ExtensionLanguageFilterDialog(),
                animationStyle: context.motionStyle,
              ),
              fallbackIcon: FluentIcons.translate_24_regular,
            ),
          ],
        ),
    ];
    final materialTabs = TabBar(
      dividerColor: Colors.transparent,
      isScrollable: true,
      controller: tabController,
      tabs: [
        Tab(text: context.l10n.sources),
        const Tab(child: _ExtensionsTabLabel()),
        Tab(text: context.l10n.migrate),
      ],
    );
    final extensionUpdates = phone
        ? ref.watch(extensionUpdateBadgeCountProvider).value ?? 0
        : 0;
    final PreferredSizeWidget tabBar = desktop
        ? _BrowseDesktopSwitchBar(
            controller: tabController,
            tabs: [
              context.l10n.sources,
              context.l10n.extensions,
              context.l10n.migrate,
            ],
          )
        : phone
        ? AppleGlassSegments(
            labels: [
              context.l10n.sources,
              extensionUpdates > 0
                  ? '${context.l10n.extensions} ($extensionUpdates)'
                  : context.l10n.extensions,
              context.l10n.migrate,
            ],
            selectedIndex: tabController.index,
            onSelected: tabController.animateTo,
            // Follows the pages while they are swiped.
            position: tabController.animation,
            fallback: materialTabs,
          )
        : materialTabs;
    final floatingTabs =
        !desktop && !topBar && AppleGlassFloatingHeader.enabled(context);
    final pager = TouchTabPager(controller: tabController, children: children);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              title: context.usesDesktopShell
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: search,
                      ),
                    )
                  : ApplePageTitle(
                      context.l10n.browse,
                      cloud: !ref.watch(serverUnreachableProvider),
                    ),
              actions: actions,
              bottom: floatingTabs ? null : tabBar,
            ),
      body: topBar
          ? Column(
              children: [
                tabBar,
                Expanded(child: pager),
              ],
            )
          : floatingTabs
          ? AppleGlassFloatingHeader.overlay(header: tabBar, child: pager)
          : pager,
    );
    return topBar
        ? TopBarSlot(
            content: desktopSearchSlotContent(
              search: search,
              actions: actions,
              spacedActionCount: tabController.index != 2 ? 1 : 0,
            ),
            minWidth: searchTopBarSlotMinWidth(actions.length),
            child: scaffold,
          )
        : scaffold;
  }
}

class _ExtensionsTabLabel extends ConsumerWidget {
  const _ExtensionsTabLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(extensionUpdateBadgeCountProvider).value ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.extensions,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (count > 0) ...[const SizedBox(width: 4), CountPill(count: count)],
      ],
    );
  }
}

class _BrowseDesktopSwitchBar extends ConsumerWidget
    implements PreferredSizeWidget {
  const _BrowseDesktopSwitchBar({required this.controller, required this.tabs});

  final TabController controller;
  final List<String> tabs;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(extensionUpdateBadgeCountProvider).value ?? 0;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => DesktopViewSwitchBar(
        labels: tabs,
        counts: [0, count, 0],
        selectedIndex: controller.index,
        onChanged: controller.animateTo,
      ),
    );
  }
}

class _BrowseDesktopSearch extends ConsumerWidget {
  const _BrowseDesktopSearch({required this.tabIndex});

  final int tabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final String query;
    final ValueChanged<String> onChanged;
    final String hint;
    switch (tabIndex) {
      case 1:
        query = ref.watch(extensionQueryProvider) ?? '';
        onChanged = (value) =>
            ref.read(extensionQueryProvider.notifier).update(value);
        hint = l10n.searchExtensionsHint;
      case 2:
        query = ref.watch(migrationSourcePickerQueryProvider);
        onChanged = (value) =>
            ref.read(migrationSourcePickerQueryProvider.notifier).update(value);
        hint = l10n.searchSourcesHint;
      default:
        query = ref.watch(sourceSearchQueryProvider) ?? '';
        onChanged = (value) =>
            ref.read(sourceSearchQueryProvider.notifier).update(value);
        hint = l10n.searchSourcesHint;
    }
    return DesktopSearchField(
      query: query,
      onChanged: onChanged,
      onNavigate: () => onChanged(''),
      hintText: hint,
    );
  }
}
