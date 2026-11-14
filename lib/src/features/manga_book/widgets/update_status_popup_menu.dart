// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../constants/app_sizes.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/ios/apple_glass_capability.dart';
import '../../../widgets/ios/apple_glass_popup_button.dart';
import '../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../widgets/shell/update_banner_state.dart';
import '../../library/data/default_category.dart';
import '../../library/domain/category/category_model.dart';
import '../../library/presentation/library/widgets/library_random_entry.dart';
import '../data/updates/updates_repository.dart';
import '../presentation/manga_details/widgets/chapter_context_menu.dart';

class UpdateStatusPopupMenu extends ConsumerWidget {
  const UpdateStatusPopupMenu({
    super.key,
    this.getCategory,
    this.showDuplicatesButton = false,
  });
  final CategoryDto? Function()? getCategory;
  final bool showDuplicatesButton;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultId = ref.watch(settledDefaultCategoryIdProvider);
    final failedCount = ref.watch(failedUpdateCountProvider).value ?? 0;
    void update([int? categoryId]) {
      ref.read(updateOptimisticProvider.notifier).arm();
      ref.read(updatesRepositoryProvider).fetchUpdates(categoryId: categoryId);
    }

    List<AppleGlassToolbarMenuItem> options(
      BuildContext menuContext, {
      bool showCategoryName = false,
    }) {
      final category = getCategory?.call();
      return [
        if (showDuplicatesButton && !menuContext.usesDesktopShell)
          AppleGlassToolbarMenuItem(
            id: 'random',
            title: menuContext.l10n.openRandomEntry,
            symbol: 'shuffle',
            fallbackIcon: FluentIcons.arrow_shuffle_24_regular,
            onSelected: randomLibraryEntryAction(menuContext, ref),
          ),
        if (category != null && defaultId != null && category.id != defaultId)
          AppleGlassToolbarMenuItem(
            id: 'category-update-${category.id}',
            title: showCategoryName
                ? '${menuContext.l10n.categoryUpdate} · ${category.name}'
                : menuContext.l10n.categoryUpdate,
            symbol: 'tag',
            fallbackIcon: FluentIcons.tag_24_regular,
            onSelected: () => update(category.id),
          ),
        AppleGlassToolbarMenuItem(
          id: 'global-update',
          title: menuContext.l10n.globalUpdate,
          symbol: 'arrow.clockwise',
          fallbackIcon: FluentIcons.arrow_clockwise_24_regular,
          onSelected: update,
        ),
        AppleGlassToolbarMenuItem(
          id: 'update-errors',
          title: menuContext.l10n.libraryUpdateErrorsCount(failedCount),
          symbol: 'exclamationmark.circle',
          fallbackIcon: FluentIcons.error_circle_24_regular,
          onSelected: () => const LibraryUpdateErrorsRoute().push(menuContext),
        ),
        if (showDuplicatesButton)
          AppleGlassToolbarMenuItem(
            id: 'duplicates',
            title: menuContext.l10n.scanForDuplicates,
            symbol: 'square.on.square',
            fallbackIcon: FluentIcons.copy_24_regular,
            onSelected: () => const LibraryDuplicatesRoute().push(menuContext),
          ),
      ];
    }

    if (supportsAppleGlass(context)) {
      Widget nativeMenu(BuildContext context) => AppleGlassToolbarButton(
        id: 'update-overflow',
        symbol: 'ellipsis',
        label: context.l10n.more,
        fallbackIcon: FluentIcons.more_vertical_24_regular,
        onPressed: null,
        menu: options(context, showCategoryName: true),
      );
      final tabs = getCategory == null
          ? null
          : DefaultTabController.maybeOf(context);
      return tabs == null
          ? nativeMenu(context)
          : ListenableBuilder(
              listenable: tabs,
              builder: (context, _) => nativeMenu(context),
            );
    }
    return AppleGlassPopupButton(
      icon: const Icon(FluentIcons.more_vertical_24_regular),
      shape: RoundedRectangleBorder(borderRadius: KBorderRadius.r16.radius),
      itemBuilder: (context) => [
        for (final option in options(context))
          PopupMenuItem(
            onTap: option.onSelected,
            child: ChapterMenuRow(
              icon: option.fallbackIcon,
              label: option.title,
            ),
          ),
      ],
      popUpAnimationStyle: context.motionStyle,
    );
  }
}
