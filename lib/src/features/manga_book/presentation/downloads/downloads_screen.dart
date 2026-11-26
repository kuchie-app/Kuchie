// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/desktop/desktop_page_frame.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../../widgets/ios/apple_page_title.dart';
import '../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../../widgets/server_image.dart';
import '../../../account/data/account_providers.dart';
import '../../../library/presentation/library/widgets/desktop_library_toolbar.dart';
import '../../../local_collection/presentation/local_ui.dart';
import '../../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../../quick_open/presentation/unified_search/unified_search_providers.dart';
import '../../../settings/controller/server_controller.dart';
import '../../../settings/presentation/downloads/downloads_settings_screen.dart';
import '../../../settings/presentation/downloads/widgets/downloads_overview.dart';
import '../../../settings/presentation/library/widgets/persistent_search_bar/persistent_search_bar.dart';
import '../../data/downloads/downloads_repository.dart';
import '../../data/downloads/server_downloaded_titles.dart';
import '../../domain/downloads/downloads_model.dart';
import '../../domain/downloads_queue/downloads_queue_model.dart';
import 'controller/downloads_controller.dart';
import 'widgets/download_completion_feedback.dart';
import 'widgets/only_my_downloads.dart';
import 'widgets/server_downloads_body.dart';

const _downloadsTextButtonChrome = 16.0 + 16.0 + 18.0 + 8.0;
const _downloadsFilledButtonChrome = 16.0 + 24.0 + 18.0 + 8.0;

// Compact controls first so the search retains its preferred width.
bool _downloadsToolbarIsCompact(
  BuildContext context,
  BoxConstraints constraints, {
  required bool showRetry,
  required bool showClear,
  required bool showToggle,
  required String retryLabel,
  required String clearLabel,
  required String toggleLabel,
}) {
  if (!constraints.hasBoundedWidth) return false;
  double textWidth(String value) => measureToolbarLabelWidth(context, value);

  final actionCount =
      (showRetry ? 1 : 0) + (showClear ? 1 : 0) + (showToggle ? 1 : 0);
  final neededBesidesSearch =
      2 * kDesktopToolbarSlotHPadding +
      actionCount * kDesktopTopBarGap +
      (showRetry ? _downloadsTextButtonChrome + textWidth(retryLabel) : 0.0) +
      (showClear ? _downloadsTextButtonChrome + textWidth(clearLabel) : 0.0) +
      (showToggle
          ? _downloadsFilledButtonChrome + textWidth(toggleLabel)
          : 0.0);
  return constraints.maxWidth - neededBesidesSearch <
      kTopBarSearchPreferredWidth;
}

class DownloadsScreen extends HookConsumerWidget {
  const DownloadsScreen({super.key, this.openOnDevice = false});

  final bool openOnDevice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final downloadsChapterIds = ref.watch(downloadsChapterIdsProvider);
    final queueStatus = ref.watch(downloadStatusProvider);
    final downloaderRunState = ref.watch(downloaderRunStateProvider);
    final visibility = ref.watch(downloadsVisibilityProvider);
    final visibleIds = visibility.visibleIds;
    final visibleSet = visibleIds.toSet();
    final erroredChapterIds = ref.watch(downloadsErroredChapterIdsProvider);
    final visibleErrored = [
      for (final id in erroredChapterIds)
        if (visibleSet.contains(id)) id,
    ];
    if (canDownload) {
      ref.listen(downloadUpdatesProvider, (_, next) {
        final updates = next.asData?.value;
        if (updates == null ||
            updates.omittedUpdates ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        final onlyMine =
            !visibility.manageAll ||
            (ref.read(onlyMyDownloadsProvider) ?? false);
        final completed = {
          for (final update in updates.updates)
            if (update.type == DownloadUpdateType.FINISHED &&
                (!onlyMine || isMyDownload(update.download)))
              update.download.chapter.id,
        };
        if (completed.isNotEmpty) {
          showDownloadCompletionFeedback(context, completed.length);
        }
      });
    }
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final persistentBox =
        phone && ref.watch(libraryPersistentSearchBarProvider).ifNull();
    final desktop = context.usesDesktopShell;
    // The shell hosts desktop actions and search.
    final topBar = showsMergedTopBar(context);
    final search = DesktopSearchField(
      query: ref.watch(unifiedSearchQueryProvider),
      onChanged: (value) =>
          ref.read(unifiedSearchQueryProvider.notifier).state = value,
      onNavigate: () =>
          ref.read(unifiedSearchQueryProvider.notifier).state = '',
    );
    Widget queueAction({
      required String id,
      required String symbol,
      required String label,
      required IconData icon,
      required VoidCallback? onPressed,
      String? tooltip,
      bool compact = false,
    }) => desktop && !compact
        ? Tooltip(
            message: tooltip ?? label,
            child: TextButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
          )
        : AppleGlassToolbarButton(
            id: id,
            symbol: symbol,
            label: tooltip ?? label,
            onPressed: onPressed,
            fallbackIcon: icon,
          );
    final showRetry = visibleErrored.isNotEmpty;
    final showClear = visibleIds.isNotBlank;
    final running = downloaderRunState == DownloaderState.STARTED;
    final canManageSettings = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final concurrency =
        ref.watch(settingsProvider).value?.maxSourcesInParallel ?? 1;
    Future<void> toggleDownloads() async {
      final repo = ref.read(downloadsRepositoryProvider);
      (await AsyncValue.guard(
        running ? repo.stopDownloads : repo.startDownloads,
      )).showToastOnError(ref.read(toastProvider));
    }

    List<Widget> buildActions({bool compact = false}) => <Widget>[
      if (phone && !persistentBox)
        const PhoneSearchEntry(origin: PhoneSearchOrigin.plain),
      if (showRetry)
        queueAction(
          id: 'retry-downloads',
          symbol: 'arrow.clockwise',
          label: context.l10n.retryAll,
          compact: compact,
          onPressed: () async {
            final toast = ref.read(toastProvider);
            final repo = ref.read(downloadsRepositoryProvider);
            final result = await AsyncValue.guard(() async {
              for (final id in visibleErrored) {
                await repo.removeChapterFromDownloadQueue(id);
              }
              await repo.addChaptersBatchToDownloadQueue(visibleErrored);
            });
            result.showToastOnError(toast);
          },
          icon: FluentIcons.replay_24_regular,
        ),
      if (showClear)
        queueAction(
          id: 'clear-downloads',
          symbol: 'trash',
          label: context.l10n.confirmClearQueueTitle,
          compact: compact,
          tooltip: canDownload ? null : context.l10n.accountPermissionDenied,
          onPressed: !canDownload
              ? null
              : () async {
                  final clearEntireQueue = visibility.manageAll;
                  if (!await confirmAction(
                        context,
                        title: clearEntireQueue
                            ? context.l10n.confirmClearQueueTitle
                            : context.l10n.cancelDownloadsTitle(
                                visibleIds.length,
                              ),
                        message: clearEntireQueue
                            ? context.l10n.confirmClearQueueMessage
                            : context.l10n.cancelDownloadsMessage,
                        action: clearEntireQueue
                            ? context.l10n.confirmClearQueueTitle
                            : context.l10n.cancelDownloads,
                        destructive: true,
                      ) ||
                      !context.mounted) {
                    return;
                  }
                  final clear = clearEntireQueue
                      ? ref.read(downloadsMapProvider.notifier).clearAll
                      : () => ref
                            .read(downloadsMapProvider.notifier)
                            .cancelQueuedChapters(visibleIds);
                  await AppUtils.guard(clear, ref.read(toastProvider));
                },
          icon: FluentIcons.delete_dismiss_24_regular,
        ),
      queueAction(
        id: 'download-settings',
        symbol: 'gearshape',
        label: localText(context, 'Download settings', 'Setelan unduhan'),
        compact: compact,
        onPressed: () => const DownloadsSettingsRoute().push(context),
        icon: FluentIcons.settings_24_regular,
      ),
    ];
    final actions = buildActions();
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // On desktop the header starts on the shared page line.
        Padding(
          padding: EdgeInsets.zero.onDesktopPageLine(context, top: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecentlyDownloadedRow(
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => RecentlyDownloadedPage(
                      load: () async {
                        ref.invalidate(serverDownloadedTitlesProvider);
                        final titles = await ref.read(
                          serverDownloadedTitlesProvider.future,
                        );
                        return [
                          for (final title in titles)
                            (
                              cover: ServerImage(
                                imageUrl: title.thumbnailUrl ?? '',
                                fit: BoxFit.cover,
                              ),
                              title: title.title,
                              chapters: title.chapters,
                              downloadedAt: title.downloadedAt,
                              onTap: () => MangaRoute(
                                mangaId: title.mangaId,
                              ).push(context),
                              onLongPress: null,
                            ),
                        ];
                      },
                    ),
                  ),
                ),
              ),
              DownloadsQueueActions(
                running: running,
                onToggle: canDownload && visibleIds.isNotEmpty
                    ? toggleDownloads
                    : null,
                concurrency: concurrency,
                onConcurrency: canManageSettings
                    ? () => chooseServerDownloadConcurrency(context, ref)
                    : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: _ServerDownloads(
            downloadsChapterIds: downloadsChapterIds,
            queueStatus: queueStatus,
          ),
        ),
      ],
    );
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              title: desktop
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: search,
                      ),
                    )
                  : ApplePageTitle(context.l10n.downloads),
              bottom: !desktop && persistentBox
                  ? const PhoneSearchBoxBottom(origin: PhoneSearchOrigin.plain)
                  : null,
              actions: actions,
            ),
      body: body,
    );
    return topBar
        ? TopBarSlot(
            content: LayoutBuilder(
              builder: (context, constraints) {
                final compact = _downloadsToolbarIsCompact(
                  context,
                  constraints,
                  showRetry: showRetry,
                  showClear: showClear,
                  showToggle: false,
                  retryLabel: context.l10n.retryAll,
                  clearLabel: context.l10n.confirmClearQueueTitle,
                  toggleLabel: '',
                );
                return desktopSearchSlotContent(
                  search: search,
                  actions: buildActions(compact: compact),
                  spacedActionCount: compact ? 0 : actions.length,
                );
              },
            ),
            minWidth: searchTopBarSlotMinWidth(actions.length),
            child: scaffold,
          )
        : scaffold;
  }
}

class _ServerDownloads extends ConsumerWidget {
  const _ServerDownloads({
    required this.downloadsChapterIds,
    required this.queueStatus,
  });

  final List<int> downloadsChapterIds;

  /// Use the queue query because mass enqueue can silence the live feed for minutes.
  final AsyncValue<DownloadStatusDto?> queueStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ServerDownloadsBody(
      downloadsChapterIds: downloadsChapterIds,
      queueStatus: queueStatus,
      toast: ref.watch(toastProvider),
    );
  }
}
