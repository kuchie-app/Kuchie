// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/popup_widgets/confirm_action.dart';
import '../../account/data/account_permission.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_action_button.dart';
import '../data/offline_database.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';
import 'keep_rule_picker.dart';
import 'offline_action_confirmations.dart';

class SeriesOfflineButton extends ConsumerWidget {
  const SeriesOfflineButton({super.key, required this.mangaId});

  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(offlineEnabledProvider)) return const SizedBox.shrink();
    final progress = ref.watch(mangaOfflineProgressProvider(mangaId)).value;
    final downloaded = progress?.downloaded ?? 0;
    final inFlight = progress?.inFlight ?? 0;
    final onDevice = downloaded > 0;
    final downloading = inFlight > 0;
    final config = ref.watch(mangaKeepConfigProvider(mangaId)).value;
    return MangaActionButton(
      active: onDevice || downloading,
      icon: downloading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              onDevice
                  ? FluentIcons.checkmark_circle_24_filled
                  : FluentIcons.arrow_circle_down_24_regular,
            ),
      label: downloading
          ? context.l10n.offlineDownloadingCount(inFlight)
          : _ruleLabel(context, config?.rule, config?.count) ??
                (onDevice
                    ? context.l10n.offlineOnDevice
                    : context.l10n.offlineDownloadAction),
      onPressed: () => _openSheet(context, ref, onDevice),
    );
  }

  String? _ruleLabel(BuildContext context, OfflineKeepRule? rule, int? count) =>
      switch (rule) {
        OfflineKeepRule.all => context.l10n.keepOfflineAllShort,
        OfflineKeepRule.allUnread => context.l10n.keepOfflineAllUnreadShort,
        OfflineKeepRule.nUnread => context.l10n.keepOfflineNextUnreadShort(
          count ?? 5,
        ),
        OfflineKeepRule.off || null => null,
      };

  void _openSheet(BuildContext context, WidgetRef ref, bool onDevice) {
    final config =
        ref.read(mangaKeepConfigProvider(mangaId)).value ??
        (rule: OfflineKeepRule.off, count: 5);
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => OfflineKeepRuleSheet(
        current: config,
        defaultCount: config.count,
        onSelected: (context, rule, count) => _apply(context, ref, rule, count),
        actions: [
          if (onDevice || config.rule != OfflineKeepRule.off)
            ListTile(
              leading: const Icon(FluentIcons.delete_24_regular, size: 22),
              iconColor: sheetContext.colorScheme.error,
              textColor: sheetContext.colorScheme.error,
              title: Text(sheetContext.l10n.offlineRemoveSeries),
              onTap: () async {
                final current = ref
                    .read(authCredentialsStoreProvider.notifier)
                    .captureSession();
                if (!await confirmAction(
                      sheetContext,
                      title: sheetContext.l10n.removeFromDevice,
                      message:
                          sheetContext.l10n.confirmDeleteSeriesDeviceMessage,
                      action: sheetContext.l10n.removeFromDevice,
                      destructive: true,
                    ) ||
                    !sheetContext.mounted ||
                    !current()) {
                  return;
                }
                await _removeAll(sheetContext, ref);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _apply(
    BuildContext sheetContext,
    WidgetRef ref,
    OfflineKeepRule rule,
    int count,
  ) async {
    final messenger = ScaffoldMessenger.of(sheetContext);
    final snackBarMotionStyle = sheetContext.snackBarMotionStyle;
    final toast = sheetContext.l10n.offlineDownloadingToast;
    Navigator.of(sheetContext).pop();
    final current = ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    ref
        .read(accountPermissionGuardProvider)
        .require(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    if (!await confirmAndChangeKeepRule(ref, mangaId, rule, count)) return;
    if (!ref.context.mounted || !current()) return;
    ref.invalidate(mangaKeepRuleProvider(mangaId));
    ref.invalidate(mangaKeepConfigProvider(mangaId));
    ref.invalidate(mangaDownloadedCountProvider(mangaId));
    messenger.showSnackBar(
      SnackBar(content: Text(toast)),
      snackBarAnimationStyle: snackBarMotionStyle,
    );
  }

  Future<void> _removeAll(BuildContext sheetContext, WidgetRef ref) async {
    Navigator.of(sheetContext).pop();
    final current = ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    await removeKeepRuleAndDelete(ref, mangaId);
    if (!ref.context.mounted || !current()) return;
    ref.invalidate(mangaKeepRuleProvider(mangaId));
    ref.invalidate(mangaKeepConfigProvider(mangaId));
    ref.invalidate(mangaDownloadedCountProvider(mangaId));
  }
}
