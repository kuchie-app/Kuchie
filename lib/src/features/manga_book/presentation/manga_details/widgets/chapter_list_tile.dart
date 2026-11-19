// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/desktop/desktop_page_frame.dart';
import '../../../../../widgets/web_route_link.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/downloads/downloads_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../../../widgets/chapter_actions/chapter_bulk_actions.dart';
import '../../../widgets/download_status_icon.dart';
import '../../downloads/controller/downloads_controller.dart';
import '../controller/manga_details_controller.dart';
import 'chapter_context_menu.dart';

typedef ChapterMenuOpener =
    void Function(RelativeRect position, void Function() refocus);

class ChapterListTile extends HookConsumerWidget {
  const ChapterListTile({
    super.key,
    required this.manga,
    required this.chapter,
    required this.updateData,
    required this.toggleSelect,
    this.canTapSelect = false,
    this.isSelected = false,
    this.desktop = false,
    this.selectionMode = false,
    this.isCurrent = false,
    this.onRowTap,
    this.onSecondaryTapAt,
    this.onOpenMenu,
    this.onLongPressAt,
  });
  final MangaDto manga;
  final ChapterDto chapter;
  final AsyncCallback updateData;
  final ValueChanged<ChapterDto> toggleSelect;
  final bool canTapSelect;
  final bool isSelected;

  final bool desktop;

  final bool selectionMode;

  /// Marks the chapter Resume would open.
  final bool isCurrent;

  /// Desktop tap handler; [shift] is true for a Shift-click range extend.
  final ValueChanged<bool>? onRowTap;

  /// Desktop right-click handler with the global tap position.
  final ValueChanged<Offset>? onSecondaryTapAt;

  /// The row guards the menu focus-return callback with its mounted state.
  final ChapterMenuOpener? onOpenMenu;
  final ValueChanged<Offset>? onLongPressAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!desktop) return _phoneTile(context, ref);
    return _desktopRow(context, ref);
  }

  Future<void> _runSwipeAction(
    BuildContext context,
    WidgetRef ref,
    ChapterSwipeAction action,
  ) async {
    switch (action) {
      case ChapterSwipeAction.toggleRead:
        await markChaptersRead(
          context: context,
          ref: ref,
          chapters: [chapter],
          isRead: !chapter.user.isRead.ifNull(),
          refresh: (_) => updateData(),
        );
      case ChapterSwipeAction.toggleBookmark:
        await toggleChapterBookmark(ref, chapter);
        await updateData();
      case ChapterSwipeAction.download:
        await runChapterSwipeDownload(
          context: context,
          ref: ref,
          chapter: chapter,
          queueEntry: ref.read(downloadsFromIdProvider(chapter.id)),
          refresh: (_) => updateData(),
        );
      case ChapterSwipeAction.disabled:
        break;
    }
  }

  Widget _phoneTile(BuildContext context, WidgetRef ref) {
    final showChapterNumber =
        ref.watch(mangaChapterDisplayModeProvider) ==
        ChapterDisplay.chapterNumber;
    final read = chapter.user.isRead.ifNull();
    final bookmarked = chapter.user.isBookmarked.ifNull();
    final downloaded = chapter.user.isDownloaded.ifNull();
    final swipeLeft =
        ref.watch(chapterSwipeToLeftProvider) ??
        DBKeys.chapterSwipeToLeft.initial;
    final swipeRight =
        ref.watch(chapterSwipeToRightProvider) ??
        DBKeys.chapterSwipeToRight.initial;
    final queueEntry = ref.watch(downloadsFromIdProvider(chapter.id));
    final canDownload = canDownloadChapters(ref);
    final reader = ReaderRoute(
      mangaId: manga.id,
      chapterId: chapter.id,
      showReaderLayoutAnimation: true,
    );
    return ChapterRowView(
      key: Key("manga-${manga.id}-chapter-${chapter.id}"),
      title: showChapterNumber
          ? context.l10n.chapterNumber(chapter.formattedChapterNumber)
          : chapter.name,
      date: int.tryParse(chapter.uploadDate).toDaysAgo(context),
      scanlator: chapter.scanlator.isNotBlank
          ? chapter.scanlator!
          : context.l10n.unknownScanlator,
      isRead: read,
      isBookmarked: bookmarked,
      lastPageRead: chapter.user.lastPageRead.getValueOnNullOrNegative(),
      pageCount: chapter.pageCount,
      isDownloaded: downloaded,
      isSelected: isSelected,
      linkLocation: reader.location,
      onTap: () {
        if (canTapSelect) {
          toggleSelect(chapter);
        } else {
          reader.push(context);
        }
      },
      onLongPress: () => toggleSelect(chapter),
      onLongPressAt: onLongPressAt,
      onSecondaryTap: () => toggleSelect(chapter),
      // Server series download on the server only.
      trailing: manga.isLocalSource
          ? null
          : DownloadStatusIcon(
              updateData: updateData,
              chapter: chapter,
              mangaId: manga.id,
              isDownloaded: downloaded,
            ),
      swipeEnabled: !selectionMode && !canTapSelect,
      leftSwipeIcon: chapterSwipeIcon(
        swipeLeft,
        read: read,
        bookmarked: bookmarked,
        downloadQueued: queueEntry != null,
        downloadFailed: queueEntry?.state == DownloadState.ERROR,
        downloaded: downloaded,
        canDownload: canDownload,
      ),
      rightSwipeIcon: chapterSwipeIcon(
        swipeRight,
        read: read,
        bookmarked: bookmarked,
        downloadQueued: queueEntry != null,
        downloadFailed: queueEntry?.state == DownloadState.ERROR,
        downloaded: downloaded,
        canDownload: canDownload,
      ),
      onSwipeLeft: () => _runSwipeAction(context, ref, swipeLeft),
      onSwipeRight: () => _runSwipeAction(context, ref, swipeRight),
    );
  }

  Widget _desktopRow(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    final showChapterNumber =
        ref.watch(mangaChapterDisplayModeProvider) ==
        ChapterDisplay.chapterNumber;
    final read = chapter.user.isRead.ifNull();
    final readColor = cs.onSurface.withValues(alpha: 0.38);
    final bookmarked = chapter.user.isBookmarked.ifNull();
    final hovered = useState(false);
    final popping = useState(false);
    final optionsFocus = useMemoized(FocusNode.new);
    useEffect(() => optionsFocus.dispose, [optionsFocus]);
    final optionsFocused = useState(false);
    final showHoverActions = hovered.value || optionsFocused.value;
    final optionsButtonKey = useMemoized(GlobalKey.new);

    final allowPop = !context.reduceMotion;
    Future<void> toggleBookmark() async {
      await toggleChapterBookmark(ref, chapter);
      if (allowPop) {
        popping.value = true;
        Future.delayed(const Duration(milliseconds: 180), () {
          if (context.mounted) popping.value = false;
        });
      }
      await updateData();
    }

    void openOptions() {
      final box =
          optionsButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      onOpenMenu?.call(
        menuAnchorForRect(context, box.localToGlobal(Offset.zero) & box.size),
        () {
          if (context.mounted) optionsFocus.requestFocus();
        },
      );
    }

    final title = showChapterNumber
        ? context.l10n.chapterNumber(chapter.formattedChapterNumber)
        : chapter.name;
    final scanlator = (chapter.scanlator ?? '').trim().isEmpty
        ? ''
        : chapter.scanlator!;
    final progress = chapter.pageCount > 0
        ? (chapter.user.lastPageRead / chapter.pageCount).clamp(0.0, 1.0)
        : 0.0;

    return WebRouteLink(
      location: ReaderRoute(
        mangaId: manga.id,
        chapterId: chapter.id,
        showReaderLayoutAnimation: true,
      ).location,
      builder: (context, openInNewTab) => GestureDetector(
        onSecondaryTapDown: (details) =>
            onSecondaryTapAt?.call(details.globalPosition),
        child: MouseRegion(
          onEnter: (_) => hovered.value = true,
          onExit: (_) => hovered.value = false,
          child: Material(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.16)
                : isCurrent
                ? cs.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            child: InkWell(
              onTap: () => WebRouteLink.handleTap(openInNewTab, () {
                final shift =
                    HardwareKeyboard.instance.logicalKeysPressed.contains(
                      LogicalKeyboardKey.shiftLeft,
                    ) ||
                    HardwareKeyboard.instance.logicalKeysPressed.contains(
                      LogicalKeyboardKey.shiftRight,
                    );
                onRowTap?.call(shift);
              }),
              child: Container(
                height: 46,
                padding: const EdgeInsets.only(right: 4),
                child: Stack(
                  children: [
                    IconButtonTheme(
                      data: IconButtonThemeData(
                        style: IconButton.styleFrom(
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (selectionMode)
                            Checkbox(
                              value: isSelected,
                              visualDensity: VisualDensity.compact,
                              onChanged: (_) => toggleSelect(chapter),
                            )
                          else
                            SizedBox(width: desktopPageLineStart(context, 13)),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                color: read ? readColor : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: Text(
                              scanlator,
                              style: TextStyle(
                                fontSize: 13,
                                color: read ? readColor : cs.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 92,
                            child: Text(
                              int.tryParse(
                                chapter.uploadDate,
                              ).toDaysAgo(context),
                              style: TextStyle(
                                fontSize: 13,
                                color: read ? readColor : cs.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 32,
                            child: bookmarked
                                ? AnimatedScale(
                                    scale: popping.value ? 1.35 : 1.0,
                                    duration: const Duration(milliseconds: 180),
                                    child: IconButton(
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      tooltip: context.l10n.removeBookmark,
                                      onPressed: toggleBookmark,
                                      icon: Icon(
                                        FluentIcons.bookmark_24_filled,
                                        color: cs.primary,
                                      ),
                                    ),
                                  )
                                : showHoverActions
                                ? AnimatedScale(
                                    scale: popping.value ? 1.35 : 1.0,
                                    duration: const Duration(milliseconds: 180),
                                    child: IconButton(
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      tooltip: context.l10n.bookmark,
                                      onPressed: toggleBookmark,
                                      icon: Icon(
                                        FluentIcons.bookmark_24_regular,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          if (!manga.isLocalSource)
                            SizedBox(
                              width: 32,
                              child: DownloadStatusIcon(
                                updateData: updateData,
                                chapter: chapter,
                                mangaId: manga.id,
                                isDownloaded: chapter.user.isDownloaded
                                    .ifNull(),
                              ),
                            ),
                          SizedBox(
                            width: 32,
                            child: Visibility(
                              visible: showHoverActions,
                              maintainSize: true,
                              maintainState: true,
                              maintainAnimation: true,
                              child: Focus(
                                focusNode: optionsFocus,
                                onFocusChange: (v) => optionsFocused.value = v,
                                child: IconButton(
                                  key: optionsButtonKey,
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  tooltip: context.l10n.more,
                                  onPressed: openOptions,
                                  icon: Icon(
                                    FluentIcons.more_vertical_24_regular,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isCurrent &&
                        chapter.pageCount > 0 &&
                        chapter.user.lastPageRead.getValueOnNullOrNegative() !=
                            0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Tooltip(
                          message: context.l10n.pageOfTotal(
                            chapter.user.lastPageRead + 1,
                            chapter.pageCount,
                          ),
                          child: ClipRect(
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: cs.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation(cs.primary),
                            ),
                          ),
                        ),
                      ),
                    if (isCurrent)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 3,
                        child: ColoredBox(color: cs.primary),
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

/// Icon for a chapter swipe action, or null when the action does nothing.
IconData? chapterSwipeIcon(
  ChapterSwipeAction action, {
  required bool read,
  required bool bookmarked,
  required bool downloadQueued,
  required bool downloadFailed,
  required bool downloaded,
  required bool canDownload,
}) {
  switch (action) {
    case ChapterSwipeAction.toggleRead:
      return read ? Icons.remove_done_rounded : Icons.done_rounded;
    case ChapterSwipeAction.toggleBookmark:
      return bookmarked
          ? FluentIcons.bookmark_24_filled
          : FluentIcons.bookmark_24_regular;
    case ChapterSwipeAction.download:
      if (!canDownload) return null;
      if (downloadQueued) {
        return downloadFailed
            ? FluentIcons.cloud_arrow_down_24_regular
            : FluentIcons.arrow_download_off_24_regular;
      }
      return downloaded
          ? FluentIcons.delete_24_regular
          : FluentIcons.cloud_arrow_down_24_regular;
    case ChapterSwipeAction.disabled:
      return null;
  }
}

/// One chapter row on phones, for every collection: title with bookmark,
/// "date • page • scanlator", a trailing slot and the swipe actions from
/// the chapter-swipe settings. Server and on-device series draw this row.
class ChapterRowView extends StatelessWidget {
  const ChapterRowView({
    super.key,
    required this.title,
    required this.isRead,
    required this.isBookmarked,
    required this.isSelected,
    required this.onTap,
    this.date,
    this.scanlator,
    this.extra,
    this.lastPageRead = 0,
    this.pageCount = 0,
    this.isDownloaded = false,
    this.linkLocation,
    this.onLongPress,
    this.onLongPressAt,
    this.onSecondaryTap,
    this.trailing,
    this.leading,
    this.swipeEnabled = false,
    this.leftSwipeIcon,
    this.rightSwipeIcon,
    this.onSwipeLeft,
    this.onSwipeRight,
  });

  final String title;
  final bool isRead;
  final bool isBookmarked;
  final bool isSelected;
  final VoidCallback onTap;
  final String? date;
  final String? scanlator;

  /// Last subtitle part, e.g. download progress or a page count.
  final String? extra;

  /// Zero-based page the reader stopped on; shown while unread.
  final int lastPageRead;

  /// Pages in the chapter, when known, for "Page 12 / 40".
  final int pageCount;

  /// Saved (on the server or this device): adds a download-done mark.
  final bool isDownloaded;

  /// Web route of the reader, so a modifier-click can open a new tab.
  final String? linkLocation;
  final VoidCallback? onLongPress;

  /// Opens a menu at the press point; replaces [onLongPress].
  final ValueChanged<Offset>? onLongPressAt;
  final VoidCallback? onSecondaryTap;
  final Widget? trailing;

  /// Replaces the bookmark marker, e.g. with a selection check.
  final Widget? leading;
  final bool swipeEnabled;
  final IconData? leftSwipeIcon;
  final IconData? rightSwipeIcon;
  final AsyncCallback? onSwipeLeft;
  final AsyncCallback? onSwipeRight;

  @override
  Widget build(BuildContext context) {
    final readColor = context.theme.colorScheme.onSurface.withValues(
      alpha: 0.38,
    );
    final dim = TextStyle(color: isRead ? readColor : null);
    final parts = <InlineSpan>[
      if (date case final date? when date.isNotEmpty)
        TextSpan(text: date, style: dim),
      if (!isRead && lastPageRead != 0)
        TextSpan(
          text: pageCount > 0
              ? context.l10n.pageOfTotal(lastPageRead + 1, pageCount)
              : context.l10n.page(lastPageRead + 1),
          style: TextStyle(color: context.theme.colorScheme.onSurfaceVariant),
        ),
      if (scanlator case final scanlator? when scanlator.isNotEmpty)
        TextSpan(text: scanlator, style: dim),
      if (extra case final extra? when extra.isNotEmpty)
        TextSpan(text: extra, style: dim),
    ];
    final row = WebRouteLink(
      location: linkLocation,
      builder: (context, openInNewTab) => GestureDetector(
        onSecondaryTap: onSecondaryTap,
        onLongPressStart: onLongPressAt == null
            ? null
            : (details) => onLongPressAt!(details.globalPosition),
        child: ListTile(
          leading: leading,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Read, bookmarked and saved at a glance.
              if (leading == null && isRead) ...[
                Icon(Icons.done_all_rounded, color: readColor, size: 18),
                const Gap(4),
              ],
              if (leading == null && isBookmarked) ...[
                Icon(
                  FluentIcons.bookmark_24_filled,
                  color: isRead
                      ? readColor
                      : context.theme.colorScheme.primary,
                  size: 18,
                ),
                const Gap(4),
              ],
              if (leading == null && isDownloaded) ...[
                Icon(
                  FluentIcons.arrow_download_24_filled,
                  color: isRead
                      ? readColor
                      : context.theme.colorScheme.primary,
                  size: 16,
                ),
                const Gap(4),
              ],
              Expanded(
                child: Text(title, style: dim, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          subtitle: parts.isEmpty
              ? null
              : Text.rich(
                  TextSpan(
                    children: [
                      for (final (index, part) in parts.indexed) ...[
                        if (index > 0) TextSpan(text: ' • ', style: dim),
                        part,
                      ],
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: trailing,
          selectedColor: context.theme.colorScheme.onSurface,
          selectedTileColor: context.theme.colorScheme.secondaryContainer,
          selected: isSelected,
          onTap: () => WebRouteLink.handleTap(openInNewTab, onTap),
          onLongPress: onLongPressAt == null ? onLongPress : null,
        ),
      ),
    );
    return _ChapterSwipeRow(
      enabled: swipeEnabled && (onSwipeLeft != null || onSwipeRight != null),
      leftIcon: leftSwipeIcon,
      rightIcon: rightSwipeIcon,
      onSwipeLeft: onSwipeLeft ?? () async {},
      onSwipeRight: onSwipeRight ?? () async {},
      isSelected: isSelected,
      child: row,
    );
  }
}

class _ChapterSwipeRow extends StatefulWidget {
  const _ChapterSwipeRow({
    required this.enabled,
    required this.leftIcon,
    required this.rightIcon,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.isSelected,
    required this.child,
  });

  final bool enabled;
  final IconData? leftIcon;
  final IconData? rightIcon;
  final AsyncCallback onSwipeLeft;
  final AsyncCallback onSwipeRight;
  final bool isSelected;
  final Widget child;

  @override
  State<_ChapterSwipeRow> createState() => _ChapterSwipeRowState();
}

class _ChapterSwipeRowState extends State<_ChapterSwipeRow>
    with SingleTickerProviderStateMixin {
  static const double _threshold = 56;
  double _offset = 0;
  Tween<double> _tween = Tween(begin: 0, end: 0);
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    _snap.addListener(() => setState(() => _offset = _tween.evaluate(_snap)));
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  bool get _canLeft => widget.enabled && widget.leftIcon != null;
  bool get _canRight => widget.enabled && widget.rightIcon != null;

  void _settle() {
    if (_offset == 0) return;
    final fired = _offset.abs() >= _threshold;
    final toLeft = _offset < 0;
    _tween = Tween(begin: _offset, end: 0);
    _snap.forward(from: 0);
    if (fired) {
      if (toLeft && _canLeft) {
        unawaited(widget.onSwipeLeft());
      } else if (!toLeft && _canRight) {
        unawaited(widget.onSwipeRight());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.maxWidth * 0.45;
        return GestureDetector(
          onHorizontalDragStart: (_) => _snap.stop(),
          onHorizontalDragUpdate: (details) {
            if (!widget.enabled) return;
            var next = _offset + (details.primaryDelta ?? 0);
            if (next < 0 && !_canLeft) next = 0;
            if (next > 0 && !_canRight) next = 0;
            next = next.clamp(-maxDrag, maxDrag);
            if (next != _offset) setState(() => _offset = next);
          },
          onHorizontalDragEnd: (_) => _settle(),
          onHorizontalDragCancel: _settle,
          child: Stack(
            children: [
              Positioned.fill(child: _swipeBackground(cs)),
              Transform.translate(
                offset: Offset(_offset, 0),
                child: Material(
                  color: widget.isSelected ? cs.secondaryContainer : cs.surface,
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _swipeBackground(ColorScheme cs) {
    final toLeft = _offset < 0;
    final icon = toLeft ? widget.leftIcon : widget.rightIcon;
    final past = _offset.abs() >= _threshold && icon != null;
    return ColoredBox(
      color: past ? cs.primaryContainer : cs.surfaceContainerLowest,
      child: _offset == 0 || !past
          ? null
          : Align(
              alignment: toLeft ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(icon, color: cs.onPrimaryContainer, size: 24),
              ),
            ),
    );
  }
}
