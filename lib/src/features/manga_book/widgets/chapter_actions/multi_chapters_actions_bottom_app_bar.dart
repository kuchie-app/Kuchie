// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/ios/apple_glass_capability.dart';
import '../../../../widgets/ios/apple_glass_surface.dart';
import '../../../../widgets/selection_action_bar.dart';
import '../../../account/data/account_providers.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter_batch/chapter_batch_model.dart';
import 'chapter_bulk_actions.dart';
import 'multi_chapters_action_icon.dart';

class MultiChaptersActionsBottomAppBar extends HookConsumerWidget {
  const MultiChaptersActionsBottomAppBar({
    super.key,
    required this.selectedChapters,
    required this.afterOptionSelected,
    this.chapterList,
  });

  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final AsyncCallback afterOptionSelected;
  final List<ChapterDto>? chapterList;

  List<int> get selectedChapterList => selectedChapters.value.keys.toList();
  List<ChapterDto> get selectedChapterDtos =>
      selectedChapters.value.values.toList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = useScrollController();
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    refresh([bool triggerAfterOption = true]) async {
      selectedChapters.value = {};
      if (triggerAfterOption) await afterOptionSelected();
    }

    final selected = selectedChapterDtos;
    final allBookmarked =
        selected.isNotEmpty &&
        selected.every((c) => c.user.isBookmarked.ifNull());

    final leading = <Widget>[
      IconButton(
        tooltip: context.l10n.clearSelection,
        icon: const Icon(FluentIcons.dismiss_24_regular),
        onPressed: () => refresh(false),
      ),
      Text(
        '${selectedChapters.value.length}',
        style: context.textTheme.titleMedium,
        semanticsLabel: context.l10n.numSelected(selectedChapters.value.length),
      ),
    ];
    final actions = <Widget>[
      IconButton(
        tooltip: context.l10n.selectAll,
        icon: const Icon(FluentIcons.select_all_on_24_regular),
        onPressed: chapterList == null
            ? null
            : () => selectedChapters.value = {
                for (final c in chapterList!) c.id: c,
              },
      ),
      MultiChaptersActionIcon(
        iconData: Icons.done_all_rounded,
        chapters: selected,
        change: ChapterChange(isRead: true, lastPageRead: 0),
        refresh: refresh,
      ),
      MultiChaptersActionIcon(
        iconData: Icons.remove_done_rounded,
        chapters: selected,
        // Stale progress on "unread" would still count as in-progress.
        change: ChapterChange(isRead: false, lastPageRead: 0),
        refresh: refresh,
      ),
      IconButton(
        tooltip: allBookmarked
            ? context.l10n.removeBookmark
            : context.l10n.bookmark,
        icon: Icon(
          allBookmarked
              ? FluentIcons.bookmark_24_filled
              : FluentIcons.bookmark_24_regular,
        ),
        onPressed: () => setChaptersBookmark(
          ref: ref,
          chapters: selected,
          isBookmarked: !allBookmarked,
          refresh: refresh,
        ),
      ),
      IconButton(
        tooltip: context.l10n.markPreviousAsRead,
        icon: const Icon(FluentIcons.text_bullet_list_checkmark_20_regular),
        onPressed: chapterList == null || selected.isEmpty
            ? null
            : () => markPreviousAsRead(
                context: context,
                ref: ref,
                bulkList: chapterList!,
                anchor: selected.last,
                refresh: refresh,
              ),
      ),
      IconButton(
        tooltip: canDownload
            ? context.l10n.downloads
            : context.l10n.accountPermissionDenied,
        icon: const Icon(FluentIcons.cloud_arrow_down_24_regular),
        onPressed: !canDownload
            ? null
            : () => queueServerDownload(
                context: context,
                ref: ref,
                chapterIds: selectedChapterList,
                refresh: refresh,
              ),
      ),
      IconButton(
        tooltip: context.l10n.delete,
        icon: const Icon(FluentIcons.delete_24_regular),
        onPressed: () async {
          final deleted = await deleteChaptersFromServerWithConfirm(
            context: context,
            ref: ref,
            chapters: selected,
          );
          if (deleted) await refresh(true);
        },
      ),
    ];
    if (supportsAppleGlass(context)) {
      final colors = context.colorScheme;
      final view = View.of(context);
      final safeBottom = view.viewPadding.bottom / view.devicePixelRatio;
      const radius = BorderRadius.all(
        Radius.circular(AppleGlassSurface.radius),
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 8, 8, safeBottom + 8),
        child: AppleGlassSurface(
          child: Material(
            type: MaterialType.transparency,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(
                  foregroundColor: colors.onSurface,
                  minimumSize: const Size.square(44),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    ...leading,
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 32,
                      child: VerticalDivider(
                        width: 12,
                        color: colors.onSurface.withValues(alpha: 0.16),
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: scrollController,
                        child: SingleChildScrollView(
                          controller: scrollController,
                          primary: false,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: Row(children: actions),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SelectionActionBar(
      clearsSystemNav: true,
      leading: leading,
      actions: actions,
    );
  }
}
