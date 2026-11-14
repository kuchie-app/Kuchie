// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../../../offline/data/offline_download_providers.dart';
import '../../controller/reader_controller.dart';

class ReaderBookmarkButton extends ConsumerWidget {
  const ReaderBookmarkButton({
    super.key,
    required this.chapterId,
    required this.fallbackIsBookmarked,
    this.dark,
  });

  final int chapterId;
  final bool fallbackIsBookmarked;
  final bool? dark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBookmarked =
        ref.watch(
          chapterProvider(
            chapterId: chapterId,
          ).select((c) => c.value?.user.isBookmarked),
        ) ??
        fallbackIsBookmarked;
    return AppleGlassToolbarButton(
      id: 'reader-bookmark',
      dark: dark,
      symbol: isBookmarked ? 'bookmark.fill' : 'bookmark',
      label: isBookmarked ? context.l10n.removeBookmark : context.l10n.bookmark,
      fallbackIcon: isBookmarked
          ? FluentIcons.bookmark_24_filled
          : FluentIcons.bookmark_24_regular,
      onPressed: () async {
        await recordBookmark(
          ref,
          chapterId: chapterId,
          isBookmarked: !isBookmarked,
        );
        if (context.mounted) {
          final refreshed = ref.refresh(
            chapterProvider(chapterId: chapterId).future,
          );
          await refreshed;
        }
      },
    );
  }
}
