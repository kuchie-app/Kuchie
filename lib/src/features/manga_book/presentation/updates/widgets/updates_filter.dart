// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/app_bottom_sheet.dart';
import '../../../../../widgets/ios/apple_glass_segments.dart';
import 'updates_filter_content.dart';

class UpdatesFilterSheet extends StatelessWidget {
  const UpdatesFilterSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      animationDuration: context.reduceMotion
          ? Duration.zero
          : kTabScrollDuration,
      child: _UpdatesFilterBody(),
    );
  }
}

class _UpdatesFilterBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final l10n = context.l10n;
    final labels = [l10n.filter, l10n.display];
    final maxHeight = MediaQuery.sizeOf(context).height * 0.65;
    final tabs = <Widget>[
      const SingleChildScrollView(
        key: PageStorageKey('updates-filters'),
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: UpdatesFilterSegments(),
      ),
      const SingleChildScrollView(
        key: PageStorageKey('updates-display'),
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: UpdatesGroupingSegment(),
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => AppSheetHeader(
            title: l10n.updates,
            trailing: controller.index == 0
                ? const UpdatesFilterResetButton()
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => AppleGlassSegments(
              labels: labels,
              selectedIndex: controller.index,
              onSelected: controller.animateTo,
              fallback: TabBar(
                tabAlignment: TabAlignment.fill,
                tabs: [for (final label in labels) Tab(text: label)],
              ),
            ),
          ),
        ),
        Flexible(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final content = ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: tabs[controller.index],
              );
              if (context.reduceMotion) return content;
              return AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: content,
              );
            },
          ),
        ),
      ],
    );
  }
}
