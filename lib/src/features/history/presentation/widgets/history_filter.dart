// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/app_bottom_sheet.dart';
import '../../../library/presentation/library/widgets/library_filter_segments.dart';
import '../history_controller.dart';

class HistoryFilterSheet extends StatelessWidget {
  const HistoryFilterSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetHeader(
          title: context.l10n.unifiedSearchFiltersSection,
          trailing: const HistoryFilterResetButton(),
        ),
        const Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: HistoryFilterOptions(),
          ),
        ),
      ],
    );
  }
}

class HistoryFilterResetButton extends ConsumerWidget {
  const HistoryFilterResetButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(historyHasActiveFiltersProvider);
    return TextButton(
      onPressed: active
          ? () {
              ref
                  .read(historyFilterUnfinishedSeriesProvider.notifier)
                  .update(null);
              ref.read(historyFilterUnreadProvider.notifier).update(null);
              ref.read(historyFilterInLibraryProvider.notifier).update(null);
            }
          : null,
      child: Text(context.l10n.reset),
    );
  }
}

class HistoryFilterOptions extends ConsumerWidget {
  const HistoryFilterOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LibraryTriStateSegment(
          heading: l10n.filterHeaderSeries,
          provider: historyFilterUnfinishedSeriesProvider,
          onChanged: ref
              .read(historyFilterUnfinishedSeriesProvider.notifier)
              .update,
          includedLabel: l10n.filterOptionUnfinished,
          excludedLabel: l10n.filterOptionFinished,
        ),
        LibraryTriStateSegment(
          heading: l10n.filterHeaderReadStatus,
          provider: historyFilterUnreadProvider,
          onChanged: ref.read(historyFilterUnreadProvider.notifier).update,
          includedLabel: l10n.filterOptionUnread,
          excludedLabel: l10n.filterOptionRead,
        ),
        LibraryTriStateSegment(
          heading: l10n.filterHeaderLibrary,
          provider: historyFilterInLibraryProvider,
          onChanged: ref.read(historyFilterInLibraryProvider.notifier).update,
          includedLabel: l10n.filterOptionInLibrary,
          excludedLabel: l10n.filterOptionNotInLibrary,
        ),
      ],
    );
  }
}
