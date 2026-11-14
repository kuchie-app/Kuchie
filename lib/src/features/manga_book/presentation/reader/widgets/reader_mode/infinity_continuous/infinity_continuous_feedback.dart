// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../../utils/theme/reader_overlay_colors.dart';
import '../../../../../domain/chapter/chapter_model.dart';
import '../../../../../domain/chapter/missing_chapters.dart';
import '../../../../../domain/chapter_page/chapter_page_model.dart';
import '../../reader_chapter_gap_warning.dart';
import 'infinity_continuous_config.dart';

class InfinityContinuousFeedback {
  const InfinityContinuousFeedback._();

  static void showEndOfMangaFeedback(
    BuildContext context,
    ObjectRef<DateTime?> lastFeedbackTime,
  ) {
    final now = DateTime.now();

    if (lastFeedbackTime.value != null &&
        now.difference(lastFeedbackTime.value!) <
            InfinityContinuousConfig.feedbackCooldown) {
      return;
    }

    lastFeedbackTime.value = now;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              FluentIcons.book_open_24_regular,
              size: 18,
              color: context.theme.colorScheme.onInverseSurface,
            ),
            const Gap(12),
            Expanded(
              child: Text(
                context.l10n.noMoreChaptersAhead,
                style: TextStyle(
                  color: context.theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.theme.colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarAnimationStyle: context.snackBarMotionStyle,
    );
  }

  static void showStartOfMangaFeedback(
    BuildContext context,
    ObjectRef<DateTime?> lastFeedbackTime,
  ) {
    final now = DateTime.now();

    if (lastFeedbackTime.value != null &&
        now.difference(lastFeedbackTime.value!) <
            InfinityContinuousConfig.feedbackCooldown) {
      return;
    }

    lastFeedbackTime.value = now;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              FluentIcons.arrow_previous_24_regular,
              size: 18,
              color: context.theme.colorScheme.onInverseSurface,
            ),
            const Gap(12),
            Expanded(
              child: Text(
                context.l10n.noMoreChaptersBehind,
                style: TextStyle(
                  color: context.theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.theme.colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarAnimationStyle: context.snackBarMotionStyle,
    );
  }

  static void showLoadingNextChapterFeedback(
    BuildContext context,
    String chapterName,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  context.theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
            const Gap(12),
            Expanded(
              child: Text(
                context.l10n.loadingNextChapter,
                style: TextStyle(
                  color: context.theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.theme.colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarAnimationStyle: context.snackBarMotionStyle,
    );
  }

  static void showLoadingPreviousChapterFeedback(
    BuildContext context,
    String chapterName,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  context.theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
            const Gap(12),
            Expanded(
              child: Text(
                context.l10n.loadingPreviousChapter,
                style: TextStyle(
                  color: context.theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.theme.colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarAnimationStyle: context.snackBarMotionStyle,
    );
  }

  static void showNextChapterLoadedFeedback(
    BuildContext context,
    String chapterName,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              FluentIcons.checkmark_circle_24_regular,
              color: context.theme.colorScheme.onInverseSurface,
              size: 18,
            ),
            const Gap(12),
            Expanded(
              child: Text(
                context.l10n.nextChapterLoaded(chapterName),
                style: TextStyle(
                  color: context.theme.colorScheme.onInverseSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: context.theme.colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
        duration: const Duration(milliseconds: 1500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarAnimationStyle: context.snackBarMotionStyle,
    );
  }

  static void showPreviousChapterLoadedFeedback(
    BuildContext context,
    String chapterName,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              FluentIcons.checkmark_circle_24_regular,
              color: context.theme.colorScheme.onInverseSurface,
              size: 18,
            ),
            const Gap(12),
            Expanded(
              child: Text(
                context.l10n.previousChapterLoaded(chapterName),
                style: TextStyle(
                  color: context.theme.colorScheme.onInverseSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: context.theme.colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
        duration: const Duration(milliseconds: 1500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarAnimationStyle: context.snackBarMotionStyle,
    );
  }

  static void showChapterLoadFailedFeedback(
    BuildContext context,
    String chapterName, {
    bool isNext = true,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              color: context.theme.colorScheme.onErrorContainer,
              size: 18,
            ),
            const Gap(12),
            Expanded(
              child: Text(
                isNext
                    ? context.l10n.failedToLoadNextChapter
                    : context.l10n.failedToLoadPreviousChapter,
                style: TextStyle(
                  color: context.theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.theme.colorScheme.errorContainer,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarAnimationStyle: context.snackBarMotionStyle,
    );
  }
}

class InfinityContinuousChapterSeparator extends StatelessWidget {
  const InfinityContinuousChapterSeparator({
    super.key,
    required this.chapterName,
    required this.isChapterStart,
    this.alwaysShow = true,
    this.gapCount = 0,
    this.note,
  });

  final String chapterName;
  final bool isChapterStart;
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
    final secondary = foreground.withValues(alpha: 0.72);
    if (!alwaysShow && gapCount == 0 && note == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          chapterName,
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall?.copyWith(color: secondary),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final divider = SizedBox(
      width: 20,
      child: Divider(color: foreground.withValues(alpha: 0.18)),
    );
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 352),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  divider,
                  Flexible(
                    child: Semantics(
                      label: isChapterStart
                          ? null
                          : context.l10n.chapterCompleted,
                      excludeSemantics: !isChapterStart,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Icon(
                            isChapterStart
                                ? FluentIcons.play_circle_24_regular
                                : FluentIcons.checkmark_circle_24_regular,
                            size: 18,
                            color: foreground,
                          ),
                          Text(
                            isChapterStart
                                ? chapterName
                                : context.l10n.finished,
                            textAlign: TextAlign.center,
                            style: context.textTheme.titleSmall?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  divider,
                ],
              ),
              if (!isChapterStart) ...[
                const Gap(2),
                Text(
                  chapterName,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: secondary,
                  ),
                ),
              ],
              if (note case final note?) ...[
                const Gap(6),
                Text(
                  note,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: secondary,
                  ),
                ),
              ],
              if (gapCount > 0) ...[
                const Gap(12),
                DefaultTextStyle.merge(
                  style: TextStyle(color: foreground),
                  child: ReaderChapterGapWarning(count: gapCount),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static ({String chapterName, bool isChapterStart, int gapCount})?
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
