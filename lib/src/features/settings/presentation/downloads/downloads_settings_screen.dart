import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../utils/webui_meta/webui_meta_codec.dart';
import '../../../../utils/webui_meta/webui_settings.dart';
import '../../../../widgets/compact_switch.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../account/data/account_providers.dart';
import '../../../library/domain/category/category_model.dart';
import '../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../local_collection/presentation/local_ui.dart';
import '../../../offline/presentation/offline_settings_screen.dart';
import '../../controller/server_controller.dart';
import '../../data/downloads/delete_chapters_settings_repository.dart';
import '../../data/downloads/downloads_settings_repository.dart';
import '../../data/user_settings.dart';
import '../../domain/settings/settings.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import '../browse/data/browse_settings_repository.dart';
import 'widgets/auto_download_categories_dialog.dart';
import 'widgets/downloads_overview.dart';

/// Picks how many sources the server downloads from at once and saves it.
Future<void> chooseServerDownloadConcurrency(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(settingsProvider).value?.maxSourcesInParallel ?? 1;
  final chosen = await pickDownloadConcurrency(
    context,
    current: current,
    max: 10,
    note: localText(
      context,
      'The server downloads from this many sources at once, one chapter per '
          'source. Shared with browsing.',
      'Server mengunduh dari sebanyak ini sumber sekaligus, satu chapter per '
          'sumber. Dipakai juga saat browsing.',
    ),
  );
  if (chosen == null || chosen == current) return;
  final updated = await AppUtils.guard(
    () => ref
        .read(browseSettingsRepositoryProvider)
        .updateSourceInParallel(chosen),
    ref.read(toastProvider),
  );
  if (updated != null) ref.read(settingsProvider.notifier).updateState(updated);
}

/// How the server's downloader behaves: the three settings both collections
/// share, then the server's own options.
class DownloadsSettingsScreen extends StatelessWidget {
  const DownloadsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topBar = showsMergedTopBar(context);
    final title = Text(
      localText(context, 'Download settings', 'Setelan unduhan'),
    );
    final content = ListTileTheme(
      data: ListTileThemeData(
        subtitleTextStyle: TextStyle(
          color: context.theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Scaffold(
        appBar: topBar
            ? null
            : detailNavigationAppBar(
                context,
                title: title,
                actions: [downloadSettingsHelpButton(context, server: true)],
              ),
        body: const _ServerDownloadsPage(),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: content,
    );
  }
}

class _ServerDownloadsPage extends ConsumerWidget {
  const _ServerDownloadsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadAheadLimit = ref.watch(downloadAheadLimitProvider);
    final canWriteMeta = ref.watch(webUiSettingsProvider).hasValue;
    Future<void> writeAhead(int limit) async {
      await AppUtils.guard(
        () => ref
            .read(webUiSettingsProvider.notifier)
            .write('downloadAheadLimit', encodeWebUiInt(limit)),
        ref.read(toastProvider),
      );
    }

    final repository = ref.watch(downloadsSettingsRepositoryProvider);
    final serverSettings = ref.watch(settingsProvider);
    final personalSettings = ref.watch(personalSettingsProvider);
    final access = ref.watch(settledAccountAccessProvider);
    final canManage = access.allows(Enum$UserPermission.MANAGE_SETTINGS);
    final personalState = ref.watch(personalSettingsStateProvider);
    final canEditPersonal = personalState == PersonalSettingsState.ready;
    final serverDelete =
        ref.watch(deleteChaptersSettingsControllerProvider).value ??
        const DeleteChaptersSettings();
    final serverDeleteController = ref.read(
      deleteChaptersSettingsControllerProvider.notifier,
    );
    final categories =
        ref.watch(categoryControllerProvider).value ?? const <CategoryDto>[];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(userSettingsProvider);
        ref.invalidate(settingsProvider);
        ref.invalidate(autoDownloadIgnoreReUploadsProvider);
        await ref.read(settingsProvider.future);
      },
      child: serverSettings.showUiWhenData(context, (data) {
        final DownloadsSettingsDto? downloadsSettingsDto = canEditPersonal
            ? personalSettings.value
            : data;
        if (downloadsSettingsDto == null) {
          return Emoticons(
            title: context.l10n.noPropFound(context.l10n.settings),
          );
        }
        // Permission and personal-setting gates disable rows without unmounting them.
        return SettingsHighlightScope(
          child: Center(
            child: ConstrainedBox(
              constraints: settingsPageConstraints(context),
              child: ListView(
                padding: settingsPagePadding(context),
                children: [
                  SettingsGroupCard(
                    children: [
                      SettingsHighlightTarget(
                        id: 'serverConcurrentDownloads',
                        child: SettingsGroupRow(
                          icon: FluentIcons.flash_24_regular,
                          title: localText(
                            context,
                            'Concurrent downloads',
                            'Unduhan bersamaan',
                          ),
                          subtitle: canManage
                              ? '${data?.maxSourcesInParallel ?? 1}'
                              : context.l10n.manageSettingsPermissionRequired,
                          trailing: canManage
                              ? const Icon(FluentIcons.chevron_right_24_regular)
                              : null,
                          onTap: canManage
                              ? () => chooseServerDownloadConcurrency(
                                  context,
                                  ref,
                                )
                              : () {},
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'serverBackgroundDownloads',
                        child: SettingsGroupRow(
                          icon: FluentIcons.arrow_sync_24_regular,
                          title: localText(
                            context,
                            'Background Download',
                            'Unduh di Latar Belakang',
                          ),
                          subtitle: localText(
                            context,
                            'Always on',
                            'Selalu aktif',
                          ),
                          trailing: Icon(
                            FluentIcons.checkmark_circle_24_filled,
                            color: context.theme.colorScheme.primary,
                          ),
                          onTap: () =>
                              showDownloadSettingsHelp(context, server: true),
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'serverDeleteAfterReading',
                        child: SettingsGroupRow(
                          icon: FluentIcons.delete_24_regular,
                          title: localText(
                            context,
                            'Delete download after reading',
                            'Hapus unduhan setelah dibaca',
                          ),
                          trailing: CompactSwitch(
                            value: serverDelete.deleteWhileReading != 0,
                            onChanged: (value) => AppUtils.guard(
                              () => serverDeleteController
                                  .setDeleteWhileReading(value ? 1 : 0),
                              ref.read(toastProvider),
                            ),
                          ),
                          onTap: () => AppUtils.guard(
                            () => serverDeleteController.setDeleteWhileReading(
                              serverDelete.deleteWhileReading != 0 ? 0 : 1,
                            ),
                            ref.read(toastProvider),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SettingsGroupHeading(
                    label: localText(context, 'Server', 'Server'),
                  ),
                  SettingsGroupCard(
                    children: [
                      SettingsHighlightTarget(
                        id: 'downloadLocation',
                        child: SettingsPropTile(
                          title: context.l10n.downloadLocation,
                          description: context.l10n.downloadLocationHint,
                          type: SettingsPropType.textField(
                            hintText: context.l10n.enterProp(
                              context.l10n.downloadLocation,
                            ),
                            value: downloadsSettingsDto.downloadsPath,
                            onChanged: canManage
                                ? repository.updateDownloadsLocation
                                : null,
                          ),
                          subtitle: !canManage
                              ? context.l10n.manageSettingsPermissionRequired
                              : downloadsSettingsDto.downloadsPath.isNotBlank
                              ? downloadsSettingsDto.downloadsPath
                              : context.l10n.defaultFolderPath,
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'saveAsCbz',
                        child: SettingsPropTile(
                          title: context.l10n.saveAsCBZArchive,
                          subtitle: canManage
                              ? null
                              : context.l10n.manageSettingsPermissionRequired,
                          type: SettingsPropType.switchTile(
                            value: downloadsSettingsDto.downloadAsCbz,
                            onChanged: canManage
                                ? repository.updateDownloadAsCbz
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ...deleteChaptersSection(
                    context,
                    title: context.l10n.deleteServerDownloads,
                    description: context.l10n.deleteServerDownloadsDescription,
                    settings: serverDelete,
                    onManual:
                        serverDeleteController.setDeleteManuallyMarkedRead,
                    onWhileReading: (value) => AppUtils.guard(
                      () => serverDeleteController.setDeleteWhileReading(value),
                      ref.read(toastProvider),
                    ),
                    onBookmark: serverDeleteController.setDeleteWithBookmark,
                    targetIdPrefix: 'server',
                  ),
                  SettingsGroupHeading(label: context.l10n.autoDownload),
                  if (personalState == PersonalSettingsState.unavailable)
                    ListTile(
                      title: Text(context.l10n.accountSettingsUnavailable),
                    ),
                  SettingsGroupCard(
                    children: [
                      SettingsHighlightTarget(
                        id: 'autoDownloadNewChapters',
                        child: SettingsPropTile(
                          title: context.l10n.autoDownloadNewChapters,
                          type: SettingsPropType.switchTile(
                            value: downloadsSettingsDto.autoDownloadNewChapters,
                            onChanged: canEditPersonal
                                ? repository.toggleAutoDownloadNewChapters
                                : null,
                          ),
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'excludeEntryWithUnreadChapters',
                        child: SettingsPropTile(
                          title: context.l10n.excludeEntryWithUnreadChapters,
                          type: SettingsPropType.switchTile(
                            value: downloadsSettingsDto
                                .excludeEntryWithUnreadChapters,
                            onChanged: canEditPersonal
                                ? repository
                                      .toggleExcludeEntryWithUnreadChapters
                                : null,
                          ),
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'autoDownloadCategories',
                        child: ListTile(
                          enabled: downloadsSettingsDto.autoDownloadNewChapters,
                          title: Text(context.l10n.autoDownloadCategories),
                          subtitle: Text(
                            autoDownloadCategoriesSummary(context, categories),
                          ),
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                const AutoDownloadCategoriesDialog(),
                            animationStyle: context.motionStyle,
                          ),
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'chapterDownloadLimit',
                        child: SettingsPropTile(
                          title: context.l10n.chapterDownloadLimit,
                          description: context.l10n.chapterDownloadLimitDesc,
                          type: SettingsPropType.numberSlider(
                            value: downloadsSettingsDto
                                .autoDownloadNewChaptersLimit,
                            min: 0,
                            max: 20,
                            onChanged: canEditPersonal
                                ? repository.updateAutoDownloadNewChaptersLimit
                                : null,
                          ),
                          subtitle: context.l10n.nChapters(
                            downloadsSettingsDto.autoDownloadNewChaptersLimit,
                          ),
                        ),
                      ),
                      if (ref
                              .watch(autoDownloadIgnoreReUploadsProvider)
                              .value !=
                          null)
                        SettingsHighlightTarget(
                          id: 'ignoreReuploadedChapters',
                          child: SettingsPropTile(
                            title: context.l10n.ignoreReuploadedChapters,
                            type: SettingsPropType.switchTile(
                              value:
                                  ref
                                      .watch(
                                        autoDownloadIgnoreReUploadsProvider,
                                      )
                                      .value ??
                                  false,
                              onChanged:
                                  canEditPersonal &&
                                      downloadsSettingsDto
                                          .autoDownloadNewChapters
                                  ? (value) async {
                                      final result = await AppUtils.guard(
                                        () => repository
                                            .toggleAutoDownloadIgnoreReUploads(
                                              value,
                                            ),
                                        ref.read(toastProvider),
                                      );
                                      if (result != null && context.mounted) {
                                        ref.invalidate(
                                          autoDownloadIgnoreReUploadsProvider,
                                        );
                                      }
                                    }
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SettingsGroupHeading(label: context.l10n.downloadAhead),
                  SettingsGroupCard(
                    children: [
                      SettingsHighlightTarget(
                        id: 'autoDownloadWhileReading',
                        child: SettingsPropTile(
                          title: context.l10n.autoDownloadWhileReading,
                          type: SettingsPropType.switchTile(
                            value: downloadAheadLimit != 0,
                            onChanged: canWriteMeta
                                ? (value) => writeAhead(value ? 2 : 0)
                                : null,
                          ),
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'downloadAheadLimit',
                        child: SettingsPropTile(
                          title: context.l10n.downloadAheadLimit,
                          subtitle:
                              '${downloadAheadLimit == 0 ? 2 : downloadAheadLimit}',
                          type: SettingsPropType.numberPicker(
                            min: 2,
                            max: 10,
                            value: downloadAheadLimit == 0
                                ? 2
                                : downloadAheadLimit,
                            onChanged: canWriteMeta && downloadAheadLimit != 0
                                ? writeAhead
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
