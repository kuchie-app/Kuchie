import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../widgets/app_bottom_sheet.dart';
import '../data/local_preferences.dart';
import 'local_ui.dart';

/// Tachimanga's library sheet: Filter, Sort and Display tabs.
Future<void> showLocalLibraryOptions(BuildContext context) async {
  await LocalPreferences.instance.load();
  if (!context.mounted) return;
  await showAppBottomSheet<void>(
    context: context,
    builder: (sheet) => const _LocalLibraryOptions(),
  );
}

class _LocalLibraryOptions extends StatelessWidget {
  const _LocalLibraryOptions();

  @override
  Widget build(BuildContext context) {
    final preferences = LocalPreferences.instance;
    return DefaultTabController(
      length: 3,
      child: ListenableBuilder(
        listenable: preferences.library,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              tabs: [
                Tab(text: localText(context, 'Filter', 'Filter')),
                Tab(text: localText(context, 'Sort', 'Urutkan')),
                Tab(text: localText(context, 'Display', 'Tampilan')),
              ],
            ),
            SizedBox(
              height: 340,
              child: TabBarView(
                children: [
                  _filter(context, preferences),
                  _sort(context, preferences),
                  _display(context, preferences),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }

  Widget _filter(BuildContext context, LocalPreferences preferences) =>
      ListView(
        children: [
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(localText(context, 'Unread', 'Belum dibaca')),
            value: preferences.filterUnread.value,
            onChanged: (value) =>
                unawaited(preferences.setFilterUnread(value ?? false)),
          ),
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(localText(context, 'Downloaded', 'Terunduh')),
            value: preferences.filterDownloaded.value,
            onChanged: (value) =>
                unawaited(preferences.setFilterDownloaded(value ?? false)),
          ),
        ],
      );

  Widget _sort(BuildContext context, LocalPreferences preferences) {
    String label(LocalLibrarySort sort) => switch (sort) {
      LocalLibrarySort.alphabetical => localText(
        context,
        'Alphabetical',
        'Alfabetis',
      ),
      LocalLibrarySort.lastRead => localText(
        context,
        'Last read',
        'Terakhir dibaca',
      ),
      LocalLibrarySort.unread => localText(context, 'Unread', 'Belum dibaca'),
      LocalLibrarySort.totalChapters => localText(
        context,
        'Total chapters',
        'Total chapter',
      ),
    };
    return ListView(
      children: [
        for (final sort in LocalLibrarySort.values)
          ListTile(
            leading: SizedBox(
              width: 24,
              child: preferences.sort.value == sort
                  ? Icon(
                      preferences.sortDescending.value
                          ? FluentIcons.arrow_down_24_regular
                          : FluentIcons.arrow_up_24_regular,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
            ),
            title: Text(label(sort)),
            onTap: () => unawaited(preferences.setSort(sort)),
          ),
      ],
    );
  }

  Widget _display(BuildContext context, LocalPreferences preferences) {
    final columns = preferences.gridColumns.value;
    final choices = LocalPreferences.gridColumnChoices;
    return ListView(
      children: [
        RadioGroup<LocalLibraryDisplay>(
          groupValue: preferences.display.value,
          onChanged: (value) {
            if (value != null) unawaited(preferences.setDisplay(value));
          },
          child: Column(
            children: [
              RadioListTile(
                value: LocalLibraryDisplay.grid,
                title: Text(localText(context, 'Grid', 'Grid')),
              ),
              RadioListTile(
                value: LocalLibraryDisplay.list,
                title: Text(localText(context, 'List', 'Daftar')),
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(localText(context, 'Items per row', 'Item per baris')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: localText(context, 'Fewer', 'Lebih sedikit'),
                icon: const Icon(Icons.remove_circle),
                onPressed: columns > choices.first
                    ? () => unawaited(preferences.setGridColumns(columns - 1))
                    : null,
              ),
              Text('$columns'),
              IconButton(
                tooltip: localText(context, 'More', 'Lebih banyak'),
                icon: const Icon(Icons.add_circle),
                onPressed: columns < choices.last
                    ? () => unawaited(preferences.setGridColumns(columns + 1))
                    : null,
              ),
            ],
          ),
        ),
        CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            localText(context, 'Unread badges', 'Lencana belum dibaca'),
          ),
          value: preferences.unreadBadges.value,
          onChanged: (value) =>
              unawaited(preferences.setUnreadBadges(value ?? true)),
        ),
        CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            localText(context, 'Downloaded badges', 'Lencana terunduh'),
          ),
          value: preferences.downloadedBadges.value,
          onChanged: (value) =>
              unawaited(preferences.setDownloadedBadges(value ?? true)),
        ),
      ],
    );
  }
}
