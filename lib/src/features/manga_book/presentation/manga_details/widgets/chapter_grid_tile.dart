// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';

class ChapterGridTile extends StatelessWidget {
  const ChapterGridTile({
    super.key,
    required this.manga,
    required this.chapter,
    required this.toggleSelect,
    this.canTapSelect = false,
    this.isSelected = false,
    this.onRowTap,
    this.onSecondaryTapAt,
    this.onLongPressAt,
  });
  final MangaDto manga;
  final ChapterDto chapter;
  final ValueChanged<ChapterDto> toggleSelect;
  final bool canTapSelect;
  final bool isSelected;
  final ValueChanged<bool>? onRowTap;
  final ValueChanged<Offset>? onSecondaryTapAt;
  final ValueChanged<Offset>? onLongPressAt;

  static String label(ChapterDto chapter) {
    final number = chapter.chapterNumber;
    if (number < 0) return '#${chapter.sourceOrder}';
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
  }

  @override
  Widget build(BuildContext context) {
    final lastPage = chapter.user.lastPageRead.getValueOnNullOrNegative();
    return ChapterGridTileView(
      key: Key("manga-${manga.id}-chapter-${chapter.id}"),
      label: label(chapter),
      tooltip: chapter.name,
      isRead: chapter.user.isRead.ifNull(),
      isBookmarked: chapter.user.isBookmarked.ifNull(),
      isDownloaded: chapter.user.isDownloaded.ifNull(),
      lastPageRead: lastPage,
      isSelected: isSelected,
      onLongPressAt: onLongPressAt,
      onSecondaryTapDown: (position) {
        if (onSecondaryTapAt != null) {
          onSecondaryTapAt!(position);
        } else {
          toggleSelect(chapter);
        }
      },
      onTap: () {
        if (onRowTap != null) {
          final keys = HardwareKeyboard.instance.logicalKeysPressed;
          onRowTap!(
            keys.contains(LogicalKeyboardKey.shiftLeft) ||
                keys.contains(LogicalKeyboardKey.shiftRight),
          );
        } else if (canTapSelect) {
          toggleSelect(chapter);
        } else {
          ReaderRoute(
            mangaId: manga.id,
            chapterId: chapter.id,
            showReaderLayoutAnimation: true,
          ).push(context);
        }
      },
      onLongPress: () => toggleSelect(chapter),
    );
  }
}

/// One chapter in the number grid, for every collection. Callers pass plain
/// state, so server and on-device series draw the same tile.
class ChapterGridTileView extends StatelessWidget {
  const ChapterGridTileView({
    super.key,
    required this.label,
    required this.tooltip,
    required this.isRead,
    required this.isBookmarked,
    required this.isDownloaded,
    required this.lastPageRead,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.onLongPressAt,
    this.onSecondaryTapDown,
  });

  /// Short chapter number shown in the tile, e.g. "12" or "12.5".
  final String label;
  final String tooltip;
  final bool isRead;
  final bool isBookmarked;
  final bool isDownloaded;

  /// Zero-based page the reader stopped on; 0 means not started.
  final int lastPageRead;
  final bool isSelected;
  final VoidCallback onTap;

  /// Used when [onLongPressAt] is null (e.g. to start selecting).
  final VoidCallback onLongPress;

  /// Opens a menu at the press point; replaces [onLongPress].
  final ValueChanged<Offset>? onLongPressAt;
  final ValueChanged<Offset>? onSecondaryTapDown;

  /// Grid label for a chapter number, or the 1-based position without one.
  static String numberLabel(double? number, int position) {
    if (number == null || number < 0) return '#$position';
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final inProgress = !isRead && lastPageRead != 0;

    final Color background;
    final Color textColor;
    Border? border;
    if (isSelected) {
      background = cs.primary.withValues(alpha: 0.22);
      textColor = cs.onSurface;
      border = Border.all(color: cs.primary);
    } else if (isRead) {
      background = cs.onSurface.withValues(alpha: 0.02);
      textColor = cs.outline;
      border = Border.all(color: cs.outlineVariant);
    } else {
      background = cs.surfaceContainer;
      textColor = cs.onSurface;
      border = Border.all(color: cs.outlineVariant);
    }

    Widget tile = Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: inProgress && !isSelected ? null : border,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: isRead ? FontWeight.w500 : FontWeight.w600,
                ),
              ),
            ),
          ),
          if (isBookmarked)
            Positioned(
              top: -1,
              right: 5,
              child: Icon(
                Icons.bookmark_rounded,
                size: 13,
                color: isRead ? cs.outline : cs.primary,
              ),
            ),
          if (inProgress)
            Positioned(
              bottom: 3,
              child: Text(
                context.l10n.page(lastPageRead + 1),
                style: TextStyle(
                  color: cs.secondary,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else if (isDownloaded)
            Positioned(
              bottom: 5,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: BrandColors.of(context).gradient,
                ),
              ),
            ),
        ],
      ),
    );

    if (inProgress && !isSelected) {
      tile = Container(
        decoration: BoxDecoration(
          gradient: BrandColors.of(context).gradient,
          borderRadius: BorderRadius.circular(13.5),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: -2,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(1.5),
        child: tile,
      );
    }

    return GestureDetector(
      onLongPressStart: onLongPressAt == null
          ? null
          : (details) => onLongPressAt!(details.globalPosition),
      onSecondaryTapDown: onSecondaryTapDown == null
          ? null
          : (details) => onSecondaryTapDown!(details.globalPosition),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 500),
        triggerMode: onLongPressAt == null ? null : TooltipTriggerMode.manual,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPressAt == null ? onLongPress : null,
          child: tile,
        ),
      ),
    );
  }
}
