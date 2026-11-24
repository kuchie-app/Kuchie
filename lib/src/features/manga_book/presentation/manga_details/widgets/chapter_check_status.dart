// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../controller/manga_details_controller.dart';

/// The line above a chapter list that says whether the source is being
/// checked, had nothing new, or brought new chapters. Empty for null.
class ChapterCheckStatus extends StatelessWidget {
  const ChapterCheckStatus({super.key, required this.check, this.padding});

  final ChapterCheck? check;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final check = this.check;
    final colors = context.theme.colorScheme;
    final style = context.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final Widget content = switch (check) {
      null => const SizedBox.shrink(key: ValueKey('none')),
      (state: final state, count: final count) => Row(
        key: ValueKey((state, count)),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 14,
            child: switch (state) {
              ChapterCheckState.checking => CircularProgressIndicator(
                strokeWidth: 1.6,
                color: colors.primary,
              ),
              ChapterCheckState.upToDate => Icon(
                FluentIcons.checkmark_circle_16_regular,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              ChapterCheckState.newChapters => Icon(
                FluentIcons.sparkle_16_filled,
                size: 14,
                color: colors.primary,
              ),
              ChapterCheckState.failed => Icon(
                FluentIcons.warning_16_regular,
                size: 14,
                color: colors.error,
              ),
            },
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              switch (state) {
                ChapterCheckState.checking =>
                  context.l10n.chapterCheckRefreshing,
                ChapterCheckState.upToDate => context.l10n.chapterCheckUpToDate,
                ChapterCheckState.newChapters => context.l10n.chapterCheckNew(
                  count,
                ),
                ChapterCheckState.failed => context.l10n.chapterCheckFailed,
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: state == ChapterCheckState.newChapters
                  ? style?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    )
                  : style,
            ),
          ),
        ],
      ),
    };
    return Semantics(
      liveRegion: check != null,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: AlignmentDirectional.topStart,
        child: check == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding:
                    padding ??
                    const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: content,
                  ),
                ),
              ),
      ),
    );
  }
}

/// [ChapterCheckStatus] for a server series.
class ServerChapterCheckStatus extends ConsumerWidget {
  const ServerChapterCheckStatus({
    super.key,
    required this.mangaId,
    this.padding,
  });

  final int mangaId;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ChapterCheckStatus(
    check: ref.watch(mangaChapterCheckProvider(mangaId: mangaId)),
    padding: padding,
  );
}
