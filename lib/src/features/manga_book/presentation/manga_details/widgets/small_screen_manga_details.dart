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

import '../../../../../constants/enum.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/desktop/desktop_page_frame.dart';
import '../../../../../widgets/emoticons.dart';
import '../../../../../widgets/ios/apple_glass_capability.dart';
import '../../../../../widgets/pull_refresh_indicator.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../controller/chapter_list_entry.dart';
import '../controller/manga_details_controller.dart';
import 'add_to_library_category.dart';
import 'chapter_check_status.dart';
import 'chapter_context_menu.dart';
import 'chapter_grid_tile.dart';
import 'chapter_list_mode_toggle.dart';
import 'chapter_list_tile.dart';
import 'manga_description.dart';
import 'missing_chapters_tile.dart';
import 'recommends_row.dart';

class SmallScreenMangaDetails extends HookConsumerWidget {
  const SmallScreenMangaDetails({
    super.key,
    required this.chapterList,
    required this.manga,
    required this.selectedChapters,
    required this.mangaId,
    required this.onRefresh,
    required this.onDescriptionRefresh,
    required this.onMigrate,
    required this.onListRefresh,
    required this.showResumeFab,
    this.continueReading,
    this.onOpenChapterFilters,
  });
  final int mangaId;
  final bool showResumeFab;
  final ({String label, String chapter, VoidCallback open})? continueReading;
  final VoidCallback? onOpenChapterFilters;
  final MangaDto manga;
  final AsyncValueSetter<bool> onRefresh;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final AsyncValue<List<MangaChapterListEntry>?> chapterList;
  final AsyncValueSetter<bool> onListRefresh;
  final AsyncValueSetter<bool> onDescriptionRefresh;
  final AsyncCallback onMigrate;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapterEntries = chapterList.value;
    final selectionAnchor = useState<int?>(null);
    final glass = supportsAppleGlass(context);
    final listMode = ref.watch(mangaChapterListModeProvider(mangaId: mangaId));
    final chapterCount =
        chapterEntries?.whereType<MangaChapterEntry>().length ?? 0;
    // The arrow shows under the bar, which the page scrolls behind.
    return PullToRefresh(
      onRefresh: () => onRefresh(true),
      top: MediaQuery.paddingOf(context).top,
      child: DesktopFullBleedScroll(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Part of the page's own scroll: a scroll view of its own here
            // would take drags that start on the header, and the chapters
            // below would never move.
            SliverToBoxAdapter(
              child: MangaDescription(
                manga: manga,
                onMigrate: onMigrate,
                refresh: () => onDescriptionRefresh(false),
                editLibraryCategories: () =>
                    editMangaLibraryCategories(ref, context, manga),
                addMangaToLibrary: () =>
                    addMangaToLibraryWithCategory(ref, context, manga),
              ),
            ),
            if (manga.title.isNotBlank && onOpenChapterFilters == null)
              SliverToBoxAdapter(
                child: RecommendsRow(mangaId: mangaId, mangaTitle: manga.title),
              ),
            if (continueReading case final entry?)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: FilledButton(
                    onPressed: entry.open,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(
                      entry.chapter.isBlank
                          ? entry.label
                          : '${entry.label} ${entry.chapter}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: ListTile(
                contentPadding: const EdgeInsetsDirectional.only(
                  start: 16,
                  end: 24,
                ).onDesktopPageLine(context),
                title: Text(context.l10n.noOfChapters(chapterCount)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChapterListModeToggle(mangaId: mangaId),
                    if (onOpenChapterFilters case final openFilters?) ...[
                      const SizedBox(width: 6),
                      ChapterHeaderButton(
                        icon: FluentIcons.filter_24_regular,
                        tooltip: context.l10n.filter,
                        onPressed: openFilters,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: ServerChapterCheckStatus(mangaId: mangaId),
            ),
            chapterList.showUiWhenData(
              context,
              (data) {
                if (data.isNotBlank) {
                  void toggleSelect(ChapterDto val) {
                    if ((val.id).isNull) return;
                    selectedChapters.value = selectedChapters.value.toggleKey(
                      val.id,
                      val,
                    );
                  }

                  void openChapterMenu(ChapterDto chapter, Offset position) {
                    final ordered = [
                      for (final entry in chapterEntries!)
                        if (entry case MangaChapterEntry(:final chapter))
                          chapter,
                    ];
                    final raw = ref.read(
                      mangaChapterListProvider(mangaId: mangaId),
                    );
                    showChapterContextMenu(
                      context: context,
                      ref: ref,
                      position: menuAnchorForPoint(context, position),
                      seriesUrl: manga.realUrl,
                      chapter: chapter,
                      selectedChapters: selectedChapters,
                      selectionAnchor: selectionAnchor,
                      orderedChapters: ordered,
                      bulkChapters: raw.value ?? ordered,
                      refresh: () => onListRefresh(false),
                      onRead: () => ReaderRoute(
                        mangaId: mangaId,
                        chapterId: chapter.id,
                        showReaderLayoutAnimation: true,
                      ).push(context),
                    );
                  }

                  if (listMode == ChapterListMode.grid) {
                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ).onDesktopPageLine(context),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 64,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                        itemCount: chapterEntries!.length,
                        itemBuilder: (context, index) {
                          final entry = chapterEntries[index];
                          return switch (entry) {
                            MangaChapterEntry() => ChapterGridTile(
                              key: ValueKey('${entry.chapter.id}'),
                              manga: manga,
                              chapter: entry.chapter,
                              isSelected: selectedChapters.value.containsKey(
                                entry.chapter.id,
                              ),
                              canTapSelect: selectedChapters.value.isNotEmpty,
                              toggleSelect: toggleSelect,
                              onLongPressAt:
                                  glass && selectedChapters.value.isEmpty
                                  ? (point) =>
                                        openChapterMenu(entry.chapter, point)
                                  : null,
                            ),
                            MissingChaptersEntry() => MissingChaptersGridTile(
                              key: ValueKey('missing-${entry.id}'),
                              count: entry.count,
                            ),
                          };
                        },
                      ),
                    );
                  }
                  return DesktopSliverGutterClearance(
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final entry = chapterEntries[index];
                        return switch (entry) {
                          MangaChapterEntry() => ChapterListTile(
                            key: ValueKey('${entry.chapter.id}'),
                            manga: manga,
                            chapter: entry.chapter,
                            updateData: () => onRefresh(false),
                            isSelected: selectedChapters.value.containsKey(
                              entry.chapter.id,
                            ),
                            canTapSelect: selectedChapters.value.isNotEmpty,
                            selectionMode: selectedChapters.value.isNotEmpty,
                            toggleSelect: toggleSelect,
                            onLongPressAt:
                                glass && selectedChapters.value.isEmpty
                                ? (point) =>
                                      openChapterMenu(entry.chapter, point)
                                : null,
                          ),
                          MissingChaptersEntry() => MissingChaptersListTile(
                            key: ValueKey('missing-${entry.id}'),
                            count: entry.count,
                          ),
                        };
                      }, childCount: chapterEntries!.length),
                    ),
                  );
                } else {
                  return SliverToBoxAdapter(
                    child: Emoticons(
                      title: context.l10n.noChaptersFound,
                      button: TextButton(
                        onPressed: () => onDescriptionRefresh(true),
                        child: Text(context.l10n.refresh),
                      ),
                    ),
                  );
                }
              },
              refresh: () => onRefresh(false),
              wrapper: (child) => SliverToBoxAdapter(
                child: SizedBox(height: context.height * .5, child: child),
              ),
            ),
            if (manga.title.isNotBlank && onOpenChapterFilters != null)
              SliverToBoxAdapter(
                child: RecommendsRow(mangaId: mangaId, mangaTitle: manga.title),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: !context.usesDesktopShell || showResumeFab ? 96 : 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
