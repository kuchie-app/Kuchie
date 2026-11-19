// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui' show ImageFilter;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../routes/navigation.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../../../widgets/app_bottom_sheet.dart';
import '../../../../../widgets/desktop/desktop_page_frame.dart';
import '../../../../../widgets/hover_tap_target.dart';
import '../../../../../widgets/in_app_web_view.dart';
import '../../../../../widgets/ios/apple_glass_capability.dart';
import '../../../../../widgets/ios/apple_glass_popup_button.dart';
import '../../../../../widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import '../../../../../widgets/popup_widgets/app_dialog.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../settings/presentation/appearance/widgets/manga_thumbnail_backdrop/manga_thumbnail_backdrop_tile.dart';
import '../../../../tracking/presentation/hub/track_sheet.dart';
import '../../../domain/manga/manga_model.dart';
import '../../manga_thumbnail_viewer/cover_viewer.dart';
import '../controller/manga_details_controller.dart';
import '../controller/next_update_controller.dart';
import '../manga_notes_screen.dart';
import '../server_web_url.dart';
import 'chapter_context_menu.dart';
import 'chapter_download_presets_button.dart';
import 'edit_manga_category_dialog.dart';
import 'manga_action_button.dart';
import 'manga_cover_hero.dart';
import 'manga_user_tags_row.dart';
import 'series_header.dart';
import 'series_info_column.dart';
import 'series_personal_section.dart';
import 'tag_actions_menu.dart';

MarkdownStyleSheet _markdownStyleSheetFromTheme(ThemeData theme) {
  return MarkdownStyleSheet(
    a: TextStyle(color: theme.colorScheme.primary),
    p: theme.textTheme.bodyMedium,
    pPadding: EdgeInsets.zero,
    code: theme.textTheme.bodyMedium!.copyWith(
      backgroundColor: theme.cardTheme.color,
      fontFamily: 'monospace',
      fontSize: theme.textTheme.bodyMedium!.fontSize! * 0.85,
    ),
    h1: theme.textTheme.headlineSmall,
    h1Padding: EdgeInsets.zero,
    h2: theme.textTheme.titleLarge,
    h2Padding: EdgeInsets.zero,
    h3: theme.textTheme.titleMedium,
    h3Padding: EdgeInsets.zero,
    h4: theme.textTheme.bodyLarge,
    h4Padding: EdgeInsets.zero,
    h5: theme.textTheme.bodyLarge,
    h5Padding: EdgeInsets.zero,
    h6: theme.textTheme.bodyLarge,
    h6Padding: EdgeInsets.zero,
    em: const TextStyle(fontStyle: FontStyle.italic),
    strong: const TextStyle(fontWeight: FontWeight.bold),
    del: const TextStyle(decoration: TextDecoration.lineThrough),
    blockquote: theme.textTheme.bodyMedium,
    img: theme.textTheme.bodyMedium,
    checkbox: theme.textTheme.bodyMedium!.copyWith(color: theme.primaryColor),
    blockSpacing: 8.0,
    listIndent: 24.0,
    listBullet: theme.textTheme.bodyMedium,
    listBulletPadding: const EdgeInsets.only(right: 4),
    tableHead: const TextStyle(fontWeight: FontWeight.w600),
    tableBody: theme.textTheme.bodyMedium,
    tableHeadAlign: TextAlign.center,
    tablePadding: const EdgeInsets.only(bottom: 4.0),
    tableBorder: TableBorder.all(color: theme.dividerColor),
    tableColumnWidth: const FlexColumnWidth(),
    tableCellsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    tableCellsDecoration: const BoxDecoration(),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    blockquoteDecoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(3),
      border: Border(
        left: BorderSide(color: theme.colorScheme.primary, width: 3),
      ),
    ),
    codeblockPadding: const EdgeInsets.all(8.0),
    codeblockDecoration: BoxDecoration(
      color: theme.cardTheme.color ?? theme.cardColor,
      borderRadius: BorderRadius.circular(2.0),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(width: 5.0, color: theme.dividerColor)),
    ),
  );
}

class MangaDescription extends HookConsumerWidget {
  const MangaDescription({
    super.key,
    required this.manga,
    required this.removeMangaFromLibrary,
    required this.addMangaToLibrary,
    required this.refresh,
    required this.onMigrate,
    this.expansion,
  });
  final SeriesInfoExpansion? expansion;
  final MangaDto manga;
  final AsyncCallback refresh;
  final AsyncCallback onMigrate;
  final AsyncCallback removeMangaFromLibrary;
  final AsyncCallback addMangaToLibrary;

  static void openWebView(BuildContext context, WidgetRef ref, MangaDto manga) {
    final url = manga.realUrl.isNotBlank
        ? manga.realUrl
        : serverMangaWebUrl(ref, manga.id);
    if (url != null) {
      openInAppWebView(context, url, toast: ref.read(toastProvider));
    }
  }

  /// With no source realUrl, opens the server WebUI directly; otherwise offers both.
  static void openInBrowser(
    BuildContext context,
    WidgetRef ref,
    MangaDto manga,
  ) {
    final toast = ref.read(toastProvider);
    final serverUrl = serverMangaWebUrl(ref, manga.id);
    if (manga.realUrl.isBlank) {
      if (serverUrl != null) launchUrlInWeb(context, serverUrl, toast);
      return;
    }
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(title: sheetContext.l10n.openInBrowser),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                ListTile(
                  leading: const Icon(FluentIcons.globe_24_regular),
                  title: Text(sheetContext.l10n.openSourceInBrowser),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    launchUrlInWeb(context, manga.realUrl ?? '', toast);
                  },
                ),
                ListTile(
                  leading: const Icon(FluentIcons.server_24_regular),
                  title: Text(sheetContext.l10n.openOnServer),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (serverUrl != null) {
                      launchUrlInWeb(context, serverUrl, toast);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twoColumn = context.windowSizeClass >= WindowSizeClass.expanded;
    final compactGlass = !twoColumn && supportsAppleGlass(context);
    final isExpanded = useState(false);
    useListenable(expansion);
    final expanded = expansion?.isExpanded ?? isExpanded.value;
    void toggleExpanded() {
      if (expansion != null) {
        expansion!.toggle();
      } else {
        isExpanded.value = !isExpanded.value;
      }
    }

    final cs = context.theme.colorScheme;
    final surface = context.theme.scaffoldBackgroundColor;
    final inLibrary = manga.user.inLibrary.ifNull();
    final moreKey = useMemoized(
      () => GlobalKey<PopupMenuButtonState<String>>(),
    );
    Future<void> toggleLibrary() async {
      if (inLibrary) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AdaptiveAppAlert(
            title: Text(context.l10n.removeFromLibrary),
            content: Text(context.l10n.duplicatesRemoveConfirm(1)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(context.l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(context.l10n.remove),
              ),
            ],
          ),
          animationStyle: context.motionStyle,
        );
        if (confirmed != true || !context.mounted) return;
      }
      final val = await AsyncValue.guard(() async {
        if (inLibrary) {
          await removeMangaFromLibrary();
        } else {
          await addMangaToLibrary();
        }
        await refresh();
      });
      if (context.mounted) val.showToastOnError(ref.read(toastProvider));
    }

    final prediction = ref.watch(mangaNextUpdateProvider(mangaId: manga.id));
    final soonDays = manga.status == Enum$MangaStatus.COMPLETED
        ? null
        : prediction?.daysUntil(DateTime.now());

    final soonWidget = soonDays == null
        ? null
        : InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AdaptiveAppAlert(
                title: Text(context.l10n.smartUpdate),
                content: Text(
                  context.l10n.smartUpdateExpected(
                    context.l10n.dayCount(soonDays),
                    context.l10n.dayCount(prediction?.intervalDays ?? 7),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(context.l10n.close),
                  ),
                ],
              ),
              animationStyle: context.motionStyle,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.hourglass_24_regular,
                  size: 14,
                  color: soonDays <= 1
                      ? cs.primary
                      : context.textTheme.bodySmall?.color,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    twoColumn
                        ? context.l10n.seriesNextChapterExpected(soonDays)
                        : soonDays == 0
                        ? context.l10n.soon
                        : context.l10n.inNDays(soonDays),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: soonDays <= 1 ? cs.primary : null,
                    ),
                  ),
                ),
              ],
            ),
          );

    final notes = manga.webUiNotes;
    Widget descriptionSection(bool expanded, bool showToggle) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (manga.description.isNotBlank || (twoColumn && notes.isNotBlank))
          Padding(
            padding: KEdgeInsets.a16.size.onDesktopPageLine(context),
            child: MangaDescriptionBody(
              description: manga.description ?? '',
              // Phones show notes in the personal section under the tags.
              notes: twoColumn ? notes : null,
              onEditNotes: !twoColumn && inLibrary
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MangaNotesScreen(
                          mangaId: manga.id,
                          seriesTitle: manga.title,
                          initialNotes: notes ?? '',
                          existingMetas: {
                            for (final meta in manga.meta) meta.key: meta.value,
                          },
                        ),
                      ),
                    )
                  : null,
              isExpanded: expanded,
              showToggle: showToggle,
              onToggleExpanded: toggleExpanded,
              onOpenLink: (url) =>
                  launchUrlInWeb(context, url, ref.read(toastProvider)),
            ),
          ),
        SeriesTagsSection(
          tags: manga.genre.where((e) => e.isNotBlank).toList(),
          leading: twoColumn ? AddUserTagChip(mangaId: manga.id) : null,
          expanded: expanded,
          onExpand: toggleExpanded,
          onTagTap: (chipContext, tag) =>
              showTagActionsMenu(chipContext, ref, tag: tag),
        ),
      ],
    );

    final showBackdrop = resolveMangaThumbnailBackdrop(
      override: ref.watch(mangaThumbnailBackdropProvider),
      twoColumn: twoColumn,
    );
    final coverBackdrop = ServerImage(
      imageUrl: manga.displayCoverUrl,
      fallbackImageUrl: manga.thumbnailUrl,
      coverVersion: manga.coverVersion,
      fallbackCoverVersion: manga.thumbnailUrlLastFetched,
      fit: BoxFit.cover,
    );
    final lightHero =
        compactGlass && showBackdrop && manga.displayCoverUrl.isNotBlank;

    final compactCoverHeader = Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 8,
      ).onDesktopPageLine(context, top: true),
      child: DesktopBoxBleed(
        start: kListTilePadding + kMangaCoverCardInset / 2,
        top: kListTilePadding + kMangaCoverCardInset / 2,
        child: MangaCoverDescriptiveListTile(
          manga: manga,
          showBadges: false,
          onCoverPressed: () => openCoverViewer(context, manga),
          onTitleClicked: (query) => openGlobalSearch(context, query: query),
          belowStatus: soonWidget,
          titleMaxLines: null,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!showBackdrop)
          SeriesHeader(
            manga: manga,
            belowStatus: soonWidget,
            onLibraryPressed: toggleLibrary,
          )
        else if (lightHero)
          MangaCoverHero(backdrop: coverBackdrop, child: compactCoverHeader)
        else
          Stack(
            children: [
              if (manga.displayCoverUrl.isNotBlank)
                Positioned.fill(
                  child: ClipRect(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: ColorFiltered(
                        colorFilter: BrandColors.of(context).neutral
                            ? const ColorFilter.matrix(<double>[
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0,
                                0,
                                0,
                                1,
                                0,
                              ])
                            : const ColorFilter.mode(
                                Colors.transparent,
                                BlendMode.dst,
                              ),
                        child: coverBackdrop,
                      ),
                    ),
                  ),
                ),
              if (showBackdrop)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.primary.withValues(alpha: 0.30),
                          surface.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                ),
              if (showBackdrop)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          surface.withValues(alpha: 0.10),
                          surface.withValues(alpha: 0.70),
                          surface,
                        ],
                      ),
                    ),
                  ),
                ),
              if (twoColumn)
                SeriesHeader(
                  manga: manga,
                  belowStatus: soonWidget,
                  onLibraryPressed: toggleLibrary,
                )
              else
                compactCoverHeader,
            ],
          ),
        Builder(
          builder: (context) {
            return Padding(
              padding:
                  (twoColumn
                          ? const EdgeInsets.fromLTRB(16, 4, 16, 4)
                          : const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ))
                      .onDesktopPageLine(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (twoColumn) ...[
                    Divider(height: 1, color: cs.outlineVariant),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      // Phones: Add to library, Tracking, Web View, the same
                      // three as on-device series.
                      if (!twoColumn)
                        Expanded(
                          child: MangaActionButton(
                            active: inLibrary,
                            icon: Icon(
                              inLibrary
                                  ? FluentIcons.heart_24_filled
                                  : FluentIcons.heart_24_regular,
                            ),
                            label: inLibrary
                                ? context.l10n.inLibrary
                                : context.l10n.addToLibrary,
                            horizontal: compactGlass,
                            onPressed: toggleLibrary,
                          ),
                        ),
                      Expanded(
                        child: MangaActionButton(
                          active: manga.trackRecords.nodes.isNotEmpty,
                          icon: const Icon(FluentIcons.arrow_sync_24_regular),
                          label: context.l10n.tracking,
                          horizontal: compactGlass,
                          onPressed: () => showTrackSheet(
                            context,
                            manga.id,
                            mangaTitle: manga.title,
                          ),
                        ),
                      ),
                      if (!twoColumn)
                        Expanded(
                          child: MangaActionButton(
                            icon: const Icon(FluentIcons.globe_24_regular),
                            label: context.l10n.webView,
                            horizontal: compactGlass,
                            onPressed: () => openWebView(context, ref, manga),
                          ),
                        ),
                      if (twoColumn && !manga.isLocalSource)
                        Expanded(
                          child: ChapterDownloadPresetsButton(
                            actionRow: true,
                            chapterList: ref.watch(
                              mangaChapterListForBulkActionsProvider(
                                mangaId: manga.id,
                              ),
                            ),
                            refresh: (_) => refresh(),
                          ),
                        ),
                      if (twoColumn)
                        Expanded(
                          child: AppleGlassPopupButton<String>(
                            key: moreKey,
                            tooltip: context.l10n.more,
                            popUpAnimationStyle: context.motionStyle,
                            onSelected: (value) async {
                              switch (value) {
                                case 'categories':
                                  showDialog<void>(
                                    context: context,
                                    builder: (_) => EditMangaCategoryDialog(
                                      mangaId: manga.id,
                                    ),
                                    animationStyle: context.motionStyle,
                                  );
                                case 'migrate':
                                  await onMigrate();
                                case 'web':
                                  openWebView(context, ref, manga);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'categories',
                                child: ChapterMenuRow(
                                  icon: FluentIcons.tag_24_regular,
                                  label: context.l10n.categories,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'migrate',
                                child: ChapterMenuRow(
                                  icon: FluentIcons.arrow_swap_24_regular,
                                  label: context.l10n.migrate,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'web',
                                child: ChapterMenuRow(
                                  icon: FluentIcons.globe_24_regular,
                                  label: context.l10n.webView,
                                ),
                              ),
                            ],
                            child: MangaActionButton(
                              icon: const Icon(
                                FluentIcons.more_horizontal_24_regular,
                              ),
                              label: context.l10n.more,
                              onPressed: () =>
                                  moreKey.currentState?.showButtonMenu(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        if (expansion == null)
          descriptionSection(expanded, true)
        else
          Stack(
            children: [
              Offstage(
                child: SizedBox(
                  key: expansion!.fullContentKey,
                  width: double.infinity,
                  child: descriptionSection(true, false),
                ),
              ),
              SizedBox(
                key: expansion!.visibleContentKey,
                width: double.infinity,
                child: descriptionSection(expanded, !expansion!.isAutomatic),
              ),
            ],
          ),
        if (twoColumn)
          MangaUserTagsRow(mangaId: manga.id)
        else
          _ServerPersonalSection(manga: manga, notes: notes ?? ''),
      ],
    );
  }
}

/// Rating, notes and your tags for a server series, under its tags.
class _ServerPersonalSection extends ConsumerWidget {
  const _ServerPersonalSection({required this.manga, required this.notes});

  final MangaDto manga;
  final String notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = mangaRatingProvider(mangaId: manga.id);
    final tags = mangaUserTagsProvider(mangaId: manga.id);
    return SeriesPersonalSection(
      rating: ref.watch(rating),
      onRate: (next) => ref.read(rating.notifier).update(next),
      notes: notes,
      onEditNotes: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MangaNotesScreen(
            mangaId: manga.id,
            seriesTitle: manga.title,
            initialNotes: notes,
            existingMetas: {for (final meta in manga.meta) meta.key: meta.value},
          ),
        ),
      ),
      tags: ref.watch(tags),
      onAddTag: () => showAddUserTagDialog(context, ref, manga.id),
      onRemoveTag: (tag) => ref.read(tags.notifier).remove(tag),
      onTagTap: (chipContext, tag) =>
          showTagActionsMenu(chipContext, ref, tag: tag),
    );
  }
}

class MangaDescriptionBody extends StatelessWidget {
  const MangaDescriptionBody({
    super.key,
    required this.description,
    this.notes,
    required this.isExpanded,
    required this.onToggleExpanded,
    this.onOpenLink,
    this.onEditNotes,
    this.showToggle = true,
  });

  final String description;
  final String? notes;
  final bool isExpanded;
  final bool showToggle;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String>? onOpenLink;
  final VoidCallback? onEditNotes;

  @override
  Widget build(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style;
    final fontSize = textStyle.fontSize ?? 14;
    final lineHeight = fontSize * (textStyle.height ?? 1.4);
    final styleSheet = _markdownStyleSheetFromTheme(context.theme).copyWith(
      p: textStyle,
      a: textStyle.copyWith(color: context.theme.colorScheme.primary),
    );
    MarkdownBody renderMarkdown(String data) => MarkdownBody(
      data: data,
      selectable: kIsWeb,
      contextMenuBuilder: (context, editableTextState) =>
          AdaptiveTextSelectionToolbar.editableText(
            editableTextState: editableTextState,
          ),
      onTapLink: (_, href, _) {
        if (href.isNotBlank) onOpenLink?.call(href!);
      },
      styleSheet: styleSheet,
    );
    final hasNotes = notes.isNotBlank;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasNotes) renderMarkdown(notes!),
        if (hasNotes && isExpanded && onEditNotes != null)
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: onEditNotes,
              icon: const Icon(FluentIcons.note_edit_24_regular, size: 16),
              label: Text(context.l10n.editNotes),
            ),
          ),
        if (hasNotes && description.isNotBlank)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(
              height: 1,
              thickness: 1,
              color: context.theme.colorScheme.outlineVariant,
            ),
          ),
        if (description.isNotBlank) renderMarkdown(description),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isExpanded)
          content
        else
          Stack(
            children: [
              ClipRect(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: lineHeight * (hasNotes ? 6 : 5),
                  ),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: content,
                  ),
                ),
              ),
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                height: lineHeight,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          context.theme.scaffoldBackgroundColor.withValues(
                            alpha: 0,
                          ),
                          context.theme.scaffoldBackgroundColor.withValues(
                            alpha: .9,
                          ),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        if (showToggle)
          InkWell(
            onTap: onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Icon(
                isExpanded
                    ? FluentIcons.chevron_up_24_regular
                    : FluentIcons.chevron_down_24_regular,
              ),
            ),
          ),
      ],
    );
  }
}

/// Series tags under the description, for every collection: one fitted row
/// with a "+N more" chip while collapsed, every tag when expanded.
class SeriesTagsSection extends StatelessWidget {
  const SeriesTagsSection({
    super.key,
    required this.tags,
    required this.expanded,
    required this.onExpand,
    required this.onTagTap,
    this.leading,
  });

  final List<String> tags;
  final bool expanded;
  final VoidCallback onExpand;
  final void Function(BuildContext, String) onTagTap;

  /// E.g. the add-your-own-tag chip; on-device series have none.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty && leading == null) return const SizedBox.shrink();
    final padding = const EdgeInsets.fromLTRB(
      16,
      0,
      16,
      12,
    ).onDesktopPageLine(context);
    if (!expanded) {
      return Padding(
        padding: padding,
        child: CollapsedSeriesTags(
          tags: tags,
          leading: leading,
          onExpand: onExpand,
          onTagTap: onTagTap,
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ?leading,
          for (final tag in tags)
            Builder(
              builder: (chipContext) => SeriesGenreChip(
                label: tag,
                onTap: () => onTagTap(chipContext, tag),
              ),
            ),
        ],
      ),
    );
  }
}

class CollapsedSeriesTags extends StatelessWidget {
  const CollapsedSeriesTags({
    super.key,
    required this.tags,
    required this.leading,
    required this.onExpand,
    required this.onTagTap,
  });

  final List<String> tags;
  final Widget? leading;
  final VoidCallback onExpand;
  final void Function(BuildContext, String) onTagTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(
        context,
      ).style.copyWith(fontSize: 12, fontWeight: FontWeight.w600);
      double textWidth(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      var count = tags.length;
      while (count > 0) {
        final moreWidth = count < tags.length
            ? 8 +
                  textWidth(context.l10n.seriesTagsMore(tags.length - count)) +
                  30
            : 0;
        final width =
            (leading == null ? 0 : 38) +
            tags
                .take(count)
                .fold<double>(0, (sum, tag) => sum + 8 + textWidth(tag) + 30) +
            moreWidth;
        if (width <= constraints.maxWidth) break;
        count--;
      }
      return Row(
        children: [
          ?leading,
          for (final (index, tag) in tags.take(count).indexed) ...[
            if (leading != null || index > 0) const SizedBox(width: 8),
            Builder(
              builder: (chipContext) => SeriesGenreChip(
                label: tag,
                onTap: () => onTagTap(chipContext, tag),
              ),
            ),
          ],
          if (count < tags.length) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Material(
                color: context.colorScheme.onSurface.withValues(alpha: .06),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: context.colorScheme.onSurface.withValues(alpha: .18),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onExpand,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    child: Text(
                      context.l10n.seriesTagsMore(tags.length - count),
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class SeriesGenreChip extends StatelessWidget {
  const SeriesGenreChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HoverTapTarget(
      builder: (context, hovered) => Stack(
        children: [
          BrandChip(label: label),
          Positioned.fill(
            child: AnimatedContainer(
              duration: Duration(milliseconds: context.reduceMotion ? 0 : 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: cs.onSurface.withValues(alpha: hovered ? 0.08 : 0),
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
