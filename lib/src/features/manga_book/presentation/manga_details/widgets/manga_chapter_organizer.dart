// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/app_bottom_sheet.dart';
import '../../../../../widgets/ios/apple_glass_segments.dart';
import '../../../../../widgets/touch_tab_pager.dart';
import 'manga_chapter_display.dart';
import 'manga_chapter_filter.dart';
import 'manga_chapter_sort.dart';

class MangaChapterOrganizer extends StatelessWidget {
  const MangaChapterOrganizer({
    super.key,
    required this.mangaId,
    this.inSheet = false,
  });
  final int mangaId;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.l10n.filter,
      context.l10n.sort,
      context.l10n.display,
    ];
    final tabs = TabBar(
      tabAlignment: TabAlignment.fill,
      tabs: [for (final label in labels) Tab(text: label)],
    );
    final body = TouchTabPager(
      children: [
        MangaChapterFilter(mangaId: mangaId, inSheet: inSheet),
        MangaChapterSort(mangaId: mangaId, inSheet: inSheet),
        MangaChapterDisplay(inSheet: inSheet),
      ],
    );
    return DefaultTabController(
      length: labels.length,
      animationDuration: context.reduceMotion
          ? Duration.zero
          : kTabScrollDuration,
      child: inSheet
          ? FractionallySizedBox(
              heightFactor: 0.72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSheetHeader(title: context.l10n.includeChapters),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Builder(
                      builder: (context) {
                        final controller = DefaultTabController.of(context);
                        return ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) => AppleGlassSegments(
                            labels: labels,
                            selectedIndex: controller.index,
                            onSelected: controller.animateTo,
                            fallback: tabs,
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
            )
          : Scaffold(appBar: tabs, body: body),
    );
  }
}
