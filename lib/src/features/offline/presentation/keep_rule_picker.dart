// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../account/data/account_providers.dart';
import '../data/offline_database.dart';

const kOfflineBufferSizes = [5, 10, 25];

/// Dismissing the sheet returns null. Stopping or deleting remains available
/// when the account can't start new downloads.
Future<({OfflineKeepRule rule, int count, bool remove})?> pickOfflineKeepRule(
  BuildContext context,
) {
  return showAppBottomSheet<({OfflineKeepRule rule, int count, bool remove})>(
    context: context,
    builder: (context) => OfflineKeepRuleSheet(
      defaultCount: 3,
      onSelected: (context, rule, count) =>
          Navigator.pop(context, (rule: rule, count: count, remove: false)),
      actions: [
        ListTile(
          leading: const Icon(FluentIcons.bookmark_off_24_regular, size: 22),
          title: Text(context.l10n.manageDownloadsStopKeep),
          onTap: () => Navigator.pop(context, (
            rule: OfflineKeepRule.off,
            count: 0,
            remove: false,
          )),
        ),
        ListTile(
          leading: const Icon(FluentIcons.delete_24_regular, size: 22),
          iconColor: context.colorScheme.error,
          textColor: context.colorScheme.error,
          title: Text(context.l10n.manageDownloadsStopDelete),
          onTap: () => Navigator.pop(context, (
            rule: OfflineKeepRule.off,
            count: 0,
            remove: true,
          )),
        ),
      ],
    ),
  );
}

class OfflineKeepRuleSheet extends ConsumerWidget {
  const OfflineKeepRuleSheet({
    super.key,
    required this.defaultCount,
    required this.onSelected,
    this.current,
    this.actions = const [],
  });

  final int defaultCount;
  final void Function(BuildContext, OfflineKeepRule, int) onSelected;
  final ({OfflineKeepRule rule, int count})? current;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final l10n = context.l10n;
    final subtitleStyle = context.textTheme.bodyMedium?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );

    Widget option(
      OfflineKeepRule rule,
      int count,
      String title,
      IconData icon,
    ) {
      final selected =
          current?.rule == rule &&
          (rule != OfflineKeepRule.nUnread || current?.count == count);
      return ListTile(
        leading: Icon(icon, size: 22),
        title: Text(title),
        selected: selected,
        trailing: selected
            ? const Icon(FluentIcons.checkmark_24_regular, size: 20)
            : null,
        onTap: canDownload ? () => onSelected(context, rule, count) : null,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetHeader(title: l10n.offlineSheetTitle),
        Flexible(
          child: ListTileTheme.merge(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: ListView(
              primary: false,
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(l10n.offlineSheetSubtitle, style: subtitleStyle),
                ),
                if (!canDownload)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      l10n.accountPermissionDenied,
                      style: subtitleStyle?.copyWith(
                        color: context.colorScheme.error,
                      ),
                    ),
                  ),
                for (final n in kOfflineBufferSizes)
                  option(
                    OfflineKeepRule.nUnread,
                    n,
                    l10n.keepOfflineNextUnread(n),
                    FluentIcons.bookmark_add_24_regular,
                  ),
                option(
                  OfflineKeepRule.allUnread,
                  defaultCount,
                  l10n.keepOfflineAllUnread,
                  FluentIcons.book_open_24_regular,
                ),
                option(
                  OfflineKeepRule.all,
                  defaultCount,
                  l10n.keepOfflineAll,
                  FluentIcons.library_24_regular,
                ),
                if (actions.isNotEmpty) ...[
                  const Divider(indent: 20, endIndent: 20, height: 16),
                  ...actions,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
