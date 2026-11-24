// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:gap/gap.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/theme/reader_overlay_colors.dart';
import '../../../../../domain/chapter/chapter_model.dart';
import '../../../../../domain/chapter/missing_chapters.dart';
import '../../../../../domain/chapter_page/chapter_page_model.dart';
import '../../reader_chapter_gap_warning.dart';

/// The quiet marker between two chapters in the reader: "Finished:" with the
/// chapter just read and "Current:" with the one that follows, so chapters
/// run on like one long strip. At the very end it says so in [note].
class InfinityContinuousChapterSeparator extends StatelessWidget {
  const InfinityContinuousChapterSeparator({
    super.key,
    required this.chapterName,
    required this.isChapterStart,
    this.nextChapterName,
    this.alwaysShow = true,
    this.gapCount = 0,
    this.note,
  });

  /// The chapter that just ended, or with [isChapterStart] the one beginning.
  final String chapterName;
  final bool isChapterStart;

  /// The chapter after [chapterName], once it is known.
  final String? nextChapterName;
  final int gapCount;
  final String? note;

  /// "Always show chapter transition": off collapses this to a slim label so
  /// chapters run together with less interruption.
  final bool alwaysShow;

  @override
  Widget build(BuildContext context) {
    final readerBackground =
        Scaffold.maybeOf(context)?.widget.backgroundColor ??
        context.theme.scaffoldBackgroundColor;
    final foreground = readerCanvasForeground(readerBackground);
    final secondary = foreground.withValues(alpha: 0.6);
    final current = isChapterStart ? chapterName : nextChapterName;
    if (!alwaysShow && gapCount == 0 && note == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          current ?? chapterName,
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall?.copyWith(color: secondary),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final labelStyle = context.textTheme.labelMedium?.copyWith(
      color: secondary,
    );
    final nameStyle = context.textTheme.titleSmall?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w600,
    );
    Widget line(String label, String name) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, textAlign: TextAlign.center, style: labelStyle),
        const Gap(2),
        Text(name, textAlign: TextAlign.center, style: nameStyle),
      ],
    );
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 352),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: MergeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isChapterStart)
                  line(context.l10n.readerChapterFinished, chapterName),
                if (current case final current?) ...[
                  if (!isChapterStart) const Gap(12),
                  line(context.l10n.readerChapterCurrent, current),
                ],
                if (note case final note?) ...[
                  const Gap(12),
                  Text(
                    note,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
                if (gapCount > 0) ...[
                  const Gap(16),
                  DefaultTextStyle.merge(
                    style: TextStyle(color: foreground),
                    child: ReaderChapterGapWarning(count: gapCount),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static ({
    String chapterName,
    String? nextChapterName,
    bool isChapterStart,
    int gapCount,
  })?
  getSeparatorInfo(
    int index,
    List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>
    loadedChapters,
  ) {
    int currentIndex = 0;
    for (int i = 0; i < loadedChapters.length; i++) {
      final chapterData = loadedChapters[i];

      if (index == currentIndex + chapterData.pages.pages.length - 1 &&
          i < loadedChapters.length - 1) {
        return (
          chapterName: chapterData.chapter.name,
          nextChapterName: loadedChapters[i + 1].chapter.name,
          isChapterStart: false,
          gapCount: chapterGap(
            higher: loadedChapters[i + 1].chapter.chapterNumber,
            lower: chapterData.chapter.chapterNumber,
          ),
        );
      }

      currentIndex += chapterData.pages.pages.length;
    }
    return null;
  }
}
