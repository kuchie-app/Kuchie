import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../../constants/urls.dart';
import '../../../global_providers/package_info.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/launch_url_in_web.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/compact_switch.dart';
import '../../../widgets/kuchie_logo.dart';
import '../../../widgets/server_image.dart';
import '../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../about/data/about_repository.dart';
import '../../about/presentation/about/widget/app_update_dialog.dart';
import '../../security/security_settings_screen.dart';
import '../../settings/presentation/advanced/copy_crash_log_tile.dart';
import '../../settings/presentation/appearance/widgets/app_language/app_language_tile.dart';
import '../../settings/presentation/customize_tabs/customize_tabs_screen.dart';
import '../../settings/presentation/downloads/widgets/downloads_overview.dart';
import '../../settings/presentation/general/widgets/force_portrait_tile.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../../sync/controller/sync_engine_provider.dart';
import '../../sync/presentation/move_to_server_sheet.dart';
import '../data/local_backups.dart';
import '../data/local_browse_preferences.dart';
import '../data/local_catalog.dart';
import '../data/local_collection_services.dart';
import '../data/local_download_queue.dart';
import '../data/local_network_settings.dart';
import '../data/local_preferences.dart';
import '../data/local_reading_stats.dart';
import '../data/local_sources.dart';
import 'local_extension_browser.dart';
import 'local_source_settings.dart';
import 'local_ui.dart';

const _chevron = Icon(FluentIcons.chevron_right_24_regular);

/// Settings confirmations use snack bars, like the rest of the Local
/// collection.
void _notify(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

void openLocalGeneralSettings(
  BuildContext context,
  LocalCollectionServices services,
) => _push(context, _LocalGeneralSettings(services: services));

void openLocalLibrarySettings(
  BuildContext context, {
  required VoidCallback onEditCategories,
}) => _push(context, _LocalLibrarySettings(onEditCategories: onEditCategories));

void openLocalDownloadSettings(BuildContext context) =>
    _push(context, const _LocalDownloadSettings());

/// Titles with chapters saved on this iPhone, newest download first. A
/// chapter's folder is last modified when its final page is written.
Future<List<({LocalSeries book, DateTime? savedAt})>>
localSavedTitlesNewestFirst(LocalCatalog catalog) async {
  final saved = <({LocalSeries book, DateTime? savedAt})>[];
  for (final book in await catalog.list()) {
    if (book.chapters.isEmpty) continue;
    DateTime? newest;
    for (final chapter in book.chapters) {
      final folder = chapter.pages.firstOrNull?.parent;
      if (folder == null) continue;
      try {
        final modified = (await folder.stat()).modified;
        if (newest == null || modified.isAfter(newest)) newest = modified;
      } on FileSystemException {
        // Removed while measuring.
      }
    }
    saved.add((book: book, savedAt: newest));
  }
  saved.sort((a, b) {
    final left = a.savedAt;
    final right = b.savedAt;
    if (left == null || right == null) {
      return left == null ? (right == null ? 0 : 1) : -1;
    }
    return right.compareTo(left);
  });
  return saved;
}

void openLocalBrowseSettings(
  BuildContext context,
  LocalCollectionServices services,
) => _push(context, _LocalBrowseSettings(services: services));

void openLocalStorage(BuildContext context, LocalCollectionServices services) =>
    _push(context, _LocalStorageSettings(services: services));

class _LocalLibrarySettings extends StatelessWidget {
  const _LocalLibrarySettings({required this.onEditCategories});

  final VoidCallback onEditCategories;

  @override
  Widget build(BuildContext context) {
    final preferences = LocalPreferences.instance;
    unawaited(preferences.load());
    return SettingsListPage(
      title: context.l10n.library,
      children: [
        SettingsGroupHeading(label: context.l10n.categories, first: true),
        SettingsGroupCard(
          children: [
            SettingsGroupRow(
              icon: FluentIcons.tag_24_regular,
              title: localText(context, 'Edit categories', 'Ubah kategori'),
              trailing: _chevron,
              onTap: onEditCategories,
            ),
            ValueListenableBuilder<bool>(
              valueListenable: preferences.categoryCounts,
              builder: (context, value, _) => SettingsGroupRow(
                icon: FluentIcons.number_symbol_24_regular,
                title: localText(
                  context,
                  'Show number of items',
                  'Tampilkan jumlah item',
                ),
                trailing: CompactSwitch(
                  value: value,
                  onChanged: preferences.setCategoryCounts,
                ),
                onTap: () => preferences.setCategoryCounts(!value),
              ),
            ),
          ],
        ),
        SettingsGroupHeading(label: localText(context, 'Display', 'Tampilan')),
        ListenableBuilder(
          listenable: preferences.library,
          builder: (context, _) => SettingsGroupCard(
            children: [
              SettingsGroupRow(
                icon: FluentIcons.apps_list_24_regular,
                title: localText(context, 'Display mode', 'Mode tampilan'),
                subtitle: preferences.display.value == LocalLibraryDisplay.grid
                    ? localText(context, 'Grid', 'Grid')
                    : localText(context, 'List', 'Daftar'),
                trailing: _chevron,
                onTap: () => preferences.setDisplay(
                  preferences.display.value == LocalLibraryDisplay.grid
                      ? LocalLibraryDisplay.list
                      : LocalLibraryDisplay.grid,
                ),
              ),
              Builder(
                builder: (context) {
                  final columns = preferences.gridColumns.value;
                  final choices = LocalPreferences.gridColumnChoices;
                  return SettingsGroupRow(
                    icon: FluentIcons.grid_24_regular,
                    title: localText(
                      context,
                      'Items per row',
                      'Item per baris',
                    ),
                    // A stepper, as in Tachimanga.
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: localText(context, 'Fewer', 'Lebih sedikit'),
                          icon: const Icon(Icons.remove_circle),
                          onPressed: columns > choices.first
                              ? () => preferences.setGridColumns(columns - 1)
                              : null,
                        ),
                        Text('$columns'),
                        IconButton(
                          tooltip: localText(context, 'More', 'Lebih banyak'),
                          icon: const Icon(Icons.add_circle),
                          onPressed: columns < choices.last
                              ? () => preferences.setGridColumns(columns + 1)
                              : null,
                        ),
                      ],
                    ),
                    onTap: () {},
                  );
                },
              ),
              SettingsGroupRow(
                icon: FluentIcons.number_circle_1_24_regular,
                title: localText(
                  context,
                  'Unread badges',
                  'Lencana belum dibaca',
                ),
                subtitle: localText(
                  context,
                  'Show the number of unread chapters on covers',
                  'Tampilkan jumlah chapter belum dibaca di cover',
                ),
                trailing: CompactSwitch(
                  value: preferences.unreadBadges.value,
                  onChanged: preferences.setUnreadBadges,
                ),
                onTap: () => preferences.setUnreadBadges(
                  !preferences.unreadBadges.value,
                ),
              ),
              SettingsGroupRow(
                icon: FluentIcons.arrow_download_24_regular,
                title: localText(
                  context,
                  'Downloaded badges',
                  'Lencana terunduh',
                ),
                subtitle: localText(
                  context,
                  'Show how many chapters are saved on this iPhone',
                  'Tampilkan jumlah chapter tersimpan di iPhone ini',
                ),
                trailing: CompactSwitch(
                  value: preferences.downloadedBadges.value,
                  onChanged: preferences.setDownloadedBadges,
                ),
                onTap: () => preferences.setDownloadedBadges(
                  !preferences.downloadedBadges.value,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// How Local downloads behave: how many at once, whether they continue in the
/// background, and whether read chapters are removed.
class _LocalDownloadSettings extends StatelessWidget {
  const _LocalDownloadSettings();

  Future<void> _chooseConcurrency(BuildContext context) async {
    final preferences = LocalPreferences.instance;
    final chosen = await pickDownloadConcurrency(
      context,
      current: preferences.downloadConcurrency.value,
      max: LocalDownloadQueue.maxConcurrency,
      note: localText(
        context,
        'Some sources slow down or block many requests at once.',
        'Beberapa sumber melambat atau memblokir terlalu banyak permintaan '
            'sekaligus.',
      ),
    );
    if (chosen != null) await preferences.setDownloadConcurrency(chosen);
  }

  Future<void> _chooseBackground(BuildContext context) async {
    final preferences = LocalPreferences.instance;
    final chosen = await pickBackgroundDownloads(
      context,
      current: preferences.backgroundDownloads.value,
    );
    if (chosen != null) await preferences.setBackgroundDownloads(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final preferences = LocalPreferences.instance;
    unawaited(preferences.load());
    return SettingsListPage(
      title: localText(context, 'Download settings', 'Setelan unduhan'),
      actions: [downloadSettingsHelpButton(context, server: false)],
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([
            preferences.downloadConcurrency,
            preferences.backgroundDownloads,
            preferences.deleteAfterReading,
          ]),
          builder: (context, _) => SettingsGroupCard(
            children: [
              SettingsGroupRow(
                icon: FluentIcons.flash_24_regular,
                title: localText(
                  context,
                  'Concurrent downloads',
                  'Unduhan bersamaan',
                ),
                subtitle: '${preferences.downloadConcurrency.value}',
                trailing: _chevron,
                onTap: () => _chooseConcurrency(context),
              ),
              SettingsGroupRow(
                icon: FluentIcons.arrow_sync_24_regular,
                title: localText(
                  context,
                  'Background Download',
                  'Unduh di Latar Belakang',
                ),
                subtitle: preferences.backgroundDownloads.value
                    ? localText(context, 'Enable', 'Aktif')
                    : localText(context, 'Disable', 'Nonaktif'),
                trailing: _chevron,
                onTap: () => _chooseBackground(context),
              ),
              SettingsGroupRow(
                icon: FluentIcons.delete_24_regular,
                title: localText(
                  context,
                  'Delete download after reading',
                  'Hapus unduhan setelah dibaca',
                ),
                trailing: CompactSwitch(
                  value: preferences.deleteAfterReading.value,
                  onChanged: preferences.setDeleteAfterReading,
                ),
                onTap: () => preferences.setDeleteAfterReading(
                  !preferences.deleteAfterReading.value,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void openLocalAdvancedSettings(
  BuildContext context,
  LocalCollectionServices services,
) => _push(context, _LocalAdvancedSettings(services: services));

void openLocalAbout(BuildContext context) =>
    _push(context, const _LocalAbout());

String _defaultTabLabel(BuildContext context, LocalDefaultTab tab) =>
    switch (tab) {
      LocalDefaultTab.lastOpened => localText(
        context,
        'Last opened tab',
        'Tab terakhir dibuka',
      ),
      LocalDefaultTab.library => context.l10n.library,
      LocalDefaultTab.updates => context.l10n.updates,
      LocalDefaultTab.browse => context.l10n.browse,
      LocalDefaultTab.history => context.l10n.history,
      LocalDefaultTab.more => context.l10n.more,
    };

Future<void> _chooseDefaultTab(BuildContext context) async {
  final preferences = LocalPreferences.instance;
  await preferences.load();
  if (!context.mounted) return;
  final chosen = await showAppBottomSheet<LocalDefaultTab>(
    context: context,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetHeader(title: localText(sheet, 'Default tab', 'Tab awal')),
        for (final tab in LocalDefaultTab.values)
          ListTile(
            title: Text(_defaultTabLabel(sheet, tab)),
            trailing: preferences.defaultTab.value == tab
                ? const Icon(FluentIcons.checkmark_24_regular)
                : null,
            onTap: () => Navigator.pop(sheet, tab),
          ),
        SizedBox(height: MediaQuery.paddingOf(sheet).bottom),
      ],
    ),
  );
  if (chosen != null) await preferences.setDefaultTab(chosen);
}

/// Like Tachimanga's General page: language, then Storage and Advanced.
class _LocalGeneralSettings extends StatelessWidget {
  const _LocalGeneralSettings({required this.services});

  final LocalCollectionServices services;

  @override
  Widget build(BuildContext context) => SettingsListPage(
    title: context.l10n.general,
    children: [
      SettingsGroupCard(
        children: [
          const AppLanguageTile(),
          SettingsGroupRow(
            icon: FluentIcons.apps_list_24_regular,
            title: context.l10n.customizeTabs,
            subtitle: context.l10n.customizeTabsSubtitle,
            trailing: _chevron,
            onTap: () => openCustomizeTabs(context, local: true),
          ),
          ValueListenableBuilder<LocalDefaultTab>(
            valueListenable: LocalPreferences.instance.defaultTab,
            builder: (context, tab, _) => SettingsGroupRow(
              icon: FluentIcons.home_24_regular,
              title: localText(context, 'Default tab', 'Tab awal'),
              subtitle: _defaultTabLabel(context, tab),
              trailing: _chevron,
              onTap: () => _chooseDefaultTab(context),
            ),
          ),
          const ForcePortraitTile(),
          SettingsGroupRow(
            icon: FluentIcons.storage_24_regular,
            title: localText(context, 'Storage', 'Penyimpanan'),
            subtitle: localText(
              context,
              'View & manage storage',
              'Lihat & kelola penyimpanan',
            ),
            trailing: _chevron,
            onTap: () => openLocalStorage(context, services),
          ),
          SettingsGroupRow(
            icon: FluentIcons.code_24_regular,
            title: context.l10n.advanced,
            subtitle: localText(
              context,
              'Clear cache, cookies, and export logs.',
              'Hapus cache, cookie, dan ekspor log.',
            ),
            trailing: _chevron,
            onTap: () => openLocalAdvancedSettings(context, services),
          ),
        ],
      ),
    ],
  );
}

class _LocalBrowseSettings extends StatelessWidget {
  const _LocalBrowseSettings({required this.services});

  final LocalCollectionServices services;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preferences = LocalBrowsePreferences.instance;
    unawaited(preferences.load());
    return SettingsListPage(
      title: l10n.extensions,
      children: [
        SettingsGroupCard(
          children: [
            SettingsGroupRow(
              icon: FluentIcons.puzzle_piece_24_regular,
              title: l10n.extensionStores,
              trailing: _chevron,
              onTap: () => openLocalExtensionStores(context, services.sources),
            ),
            SettingsGroupRow(
              icon: FluentIcons.settings_24_regular,
              title: localText(context, 'Source settings', 'Pengaturan sumber'),
              trailing: _chevron,
              onTap: () => _push(
                context,
                _LocalSourceSettingsList(sources: services.sources),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: preferences.showNsfw,
              builder: (context, value, _) => SettingsGroupRow(
                icon: FluentIcons.eye_off_24_regular,
                title: l10n.nsfw,
                trailing: CompactSwitch(
                  value: value,
                  onChanged: preferences.setShowNsfw,
                ),
                onTap: () => preferences.setShowNsfw(!value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LocalAdvancedSettings extends ConsumerWidget {
  const _LocalAdvancedSettings({required this.services});

  final LocalCollectionServices services;

  String _userAgentLabel(BuildContext context, LocalUserAgent mode) =>
      switch (mode) {
        LocalUserAgent.desktopChrome => context.l10n.userAgentDesktopChrome,
        LocalUserAgent.desktopFirefox => context.l10n.userAgentDesktopFirefox,
        LocalUserAgent.device => context.l10n.userAgentDevice,
        LocalUserAgent.desktopSafari => context.l10n.userAgentDesktopSafari,
        LocalUserAgent.custom => context.l10n.userAgentCustom,
      };

  Future<void> _chooseUserAgent(BuildContext context) async {
    final settings = LocalNetworkSettings.instance;
    final chosen = await showAppBottomSheet<LocalUserAgent>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(title: sheet.l10n.userAgent),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              sheet.l10n.userAgentNote,
              style: Theme.of(sheet).textTheme.bodySmall,
            ),
          ),
          for (final mode in LocalUserAgent.values)
            ListTile(
              title: Text(_userAgentLabel(sheet, mode)),
              subtitle:
                  mode == LocalUserAgent.custom &&
                      settings.customUserAgent.value.isNotEmpty
                  ? Text(
                      settings.customUserAgent.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: settings.userAgent.value == mode
                  ? const Icon(FluentIcons.checkmark_24_regular)
                  : null,
              onTap: () => Navigator.pop(sheet, mode),
            ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    if (chosen != LocalUserAgent.custom) {
      await settings.setUserAgent(chosen);
      return;
    }
    final initial = settings.customUserAgent.value.isEmpty
        ? await settings.effectiveUserAgent()
        : settings.customUserAgent.value;
    if (!context.mounted) return;
    final custom = await localInput(
      context,
      context.l10n.userAgentCustom,
      context.l10n.userAgentCustomHint,
      initial: initial,
    );
    if (custom != null) {
      await settings.setUserAgent(LocalUserAgent.custom, custom: custom);
    }
  }

  Future<void> _clearCookies(BuildContext context) async {
    final l10n = context.l10n;
    if (!await localConfirm(
      context,
      l10n.clearCookies,
      l10n.clearCookiesSubtitle,
    )) {
      return;
    }
    try {
      await LocalNetworkSettings.instance.clearWebViewCookies();
      await services.sources.clearRuntimeCookies();
      if (context.mounted) _notify(context, l10n.cookiesCleared);
    } catch (error) {
      if (context.mounted) localFailure(context, error);
    }
  }

  Future<void> _clearCache(BuildContext context) async {
    final message = context.l10n.cacheCleared;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await services.sources.clearCache();
    // Pages read online are kept in per-chapter temporary folders.
    try {
      await for (final entry in Directory.systemTemp.list()) {
        if (entry is Directory &&
            entry.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('kuchie-preview-')) {
          await entry.delete(recursive: true);
        }
      }
    } on FileSystemException {
      // An open reader may still hold its folder.
    }
    if (context.mounted) _notify(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = LocalNetworkSettings.instance;
    unawaited(settings.load());
    final l10n = context.l10n;
    return SettingsListPage(
      title: l10n.advanced,
      children: [
        SettingsGroupHeading(
          label: localText(context, 'Data usage', 'Penggunaan data'),
          first: true,
        ),
        SettingsGroupCard(
          children: [
            SettingsGroupRow(
              icon: FluentIcons.broom_24_regular,
              title: l10n.clearCache,
              onTap: () => _clearCache(context),
            ),
          ],
        ),
        SettingsGroupHeading(label: l10n.network),
        ListenableBuilder(
          listenable: Listenable.merge([
            settings.autoBypass,
            settings.mutedHosts,
            settings.userAgent,
            settings.customUserAgent,
          ]),
          builder: (context, _) => SettingsGroupCard(
            children: [
              SettingsGroupRow(
                icon: FluentIcons.cookies_24_regular,
                title: l10n.clearCookies,
                subtitle: l10n.clearCookiesSubtitle,
                onTap: () => _clearCookies(context),
              ),
              SettingsGroupRow(
                icon: FluentIcons.shield_checkmark_24_regular,
                title: l10n.cloudflareAutoBypass,
                subtitle: l10n.cloudflareAutoBypassSubtitle,
                trailing: CompactSwitch(
                  value: settings.autoBypass.value,
                  onChanged: settings.setAutoBypass,
                ),
                onTap: () => settings.setAutoBypass(!settings.autoBypass.value),
              ),
              SettingsGroupRow(
                icon: FluentIcons.alert_off_24_regular,
                title: l10n.cloudflareClearMutes,
                subtitle: l10n.cloudflareMutedCount(
                  settings.mutedHosts.value.length,
                ),
                onTap: () async {
                  await settings.clearMutes();
                  if (context.mounted) {
                    _notify(context, l10n.cloudflareMutesCleared);
                  }
                },
              ),
              SettingsGroupRow(
                icon: FluentIcons.globe_person_24_regular,
                title: l10n.userAgent,
                subtitle: _userAgentLabel(context, settings.userAgent.value),
                trailing: _chevron,
                onTap: () => _chooseUserAgent(context),
              ),
            ],
          ),
        ),
        SettingsGroupHeading(
          label: localText(context, 'Troubleshoot', 'Pemecahan masalah'),
        ),
        const SettingsGroupCard(children: [CopyCrashLogTile()]),
      ],
    );
  }
}

class _LocalAbout extends ConsumerStatefulWidget {
  const _LocalAbout();

  @override
  ConsumerState<_LocalAbout> createState() => _LocalAboutState();
}

class _LocalAboutState extends ConsumerState<_LocalAbout> {
  bool _checking = false;

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    final toast = ref.read(toastProvider);
    final l10n = context.l10n;
    try {
      final result = await ref.read(aboutRepositoryProvider).checkUpdate();
      if (!mounted) return;
      result.when(
        data: (Version? latest) {
          if (latest == null) {
            _notify(context, l10n.noUpdatesAvailable);
          } else {
            appUpdateDialog(
              title: ref.read(packageInfoProvider).appName,
              newRelease: 'v$latest',
              context: context,
              toast: toast,
            );
          }
        },
        error: (_, _) => _notify(context, l10n.updateCheckFailed),
        loading: () {},
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final info = ref.watch(packageInfoProvider);
    final toast = ref.watch(toastProvider);
    final version = info.buildNumber.isEmpty
        ? info.version
        : '${info.version} (${info.buildNumber})';
    void open(String url) => launchUrlInWeb(context, url, toast);
    return SettingsListPage(
      title: l10n.about,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              const KuchieLogo(size: 88),
              const SizedBox(height: 12),
              Text(info.appName, style: context.textTheme.titleLarge),
              Text(
                version,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SettingsGroupCard(
          children: [
            SettingsGroupRow(
              icon: FluentIcons.arrow_sync_24_regular,
              title: l10n.checkForUpdates,
              subtitle: _checking ? l10n.checkingForUpdates : null,
              trailing: _checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _checkForUpdates,
            ),
            if (KuchieLinks.releaseNotes.isNotEmpty)
              SettingsGroupRow(
                icon: FluentIcons.sparkle_24_regular,
                title: l10n.whatsNew,
                trailing: _chevron,
                onTap: () => open(KuchieLinks.releaseNotes),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsGroupCard(
          children: [
            if (KuchieLinks.project.isNotEmpty)
              SettingsGroupRow(
                icon: FluentIcons.code_24_regular,
                title: l10n.githubKuchie,
                trailing: _chevron,
                onTap: () => open(KuchieLinks.project),
              ),
            if (KuchieLinks.privacyPolicy.isNotEmpty)
              SettingsGroupRow(
                icon: FluentIcons.shield_24_regular,
                title: l10n.privacyPolicy,
                trailing: _chevron,
                onTap: () => open(KuchieLinks.privacyPolicy),
              ),
            SettingsGroupRow(
              icon: FluentIcons.document_24_regular,
              title: l10n.openSourceLicenses,
              trailing: _chevron,
              onTap: () => showLicensePage(
                context: context,
                applicationName: info.appName,
                applicationVersion: version,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What Kuchie keeps on this iPhone, measured for Storage.
typedef _StorageUsage = ({
  List<({LocalSeries book, int bytes})> titles,
  int cache,
  int covers,
});

Future<int> _folderSize(Directory folder) async {
  var total = 0;
  try {
    if (!await folder.exists()) return 0;
    await for (final entry in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is File) {
        try {
          total += await entry.length();
        } on FileSystemException {
          // Removed while measuring.
        }
      }
    }
  } on FileSystemException {
    // An unreadable folder counts as empty.
  }
  return total;
}

Future<int> _pagesSize(LocalSeries book) async {
  var total = 0;
  for (final chapter in book.chapters) {
    for (final page in chapter.pages) {
      try {
        total += await page.length();
      } on FileSystemException {
        // A missing page counts as nothing.
      }
    }
  }
  return total;
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 || value >= 100 ? 0 : 1)} '
      '${units[unit]}';
}

class _LocalStorageSettings extends StatefulWidget {
  const _LocalStorageSettings({required this.services});

  final LocalCollectionServices services;

  @override
  State<_LocalStorageSettings> createState() => _LocalStorageSettingsState();
}

class _LocalStorageSettingsState extends State<_LocalStorageSettings> {
  late Future<_StorageUsage> _usage = _measure();

  Future<_StorageUsage> _measure() async {
    final services = widget.services;
    final books = [
      for (final book in await services.catalog.list())
        if (book.chapters.isNotEmpty) book,
    ];
    final titles = [
      for (final book in books) (book: book, bytes: await _pagesSize(book)),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    return (
      titles: titles,
      cache: await _folderSize(services.sources.cacheDirectory),
      covers: await _folderSize(services.catalog.sourceCoverDirectory),
    );
  }

  void _reload() => setState(() => _usage = _measure());

  Future<void> _deleteTitle(LocalSeries book) async {
    if (!await localConfirm(
          context,
          localText(context, 'Delete all downloads?', 'Hapus semua unduhan?'),
          localText(
            context,
            '${book.chapters.length} chapters of ${book.title} will be '
                'removed from this iPhone.',
            '${book.chapters.length} chapter ${book.title} akan dihapus dari '
                'iPhone ini.',
          ),
        ) ||
        !mounted) {
      return;
    }
    try {
      for (final chapter in book.chapters) {
        await widget.services.catalog.removeChapter(book.id, chapter.id);
      }
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
    if (mounted) _reload();
  }

  Future<void> _clearCache() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await widget.services.sources.clearCache();
    if (!mounted) return;
    _notify(context, context.l10n.cacheCleared);
    _reload();
  }

  Future<void> _clearCovers() async {
    if (!await localConfirm(
          context,
          localText(context, 'Clear saved covers?', 'Hapus cover tersimpan?'),
          localText(
            context,
            'History and the library show the source link or the first '
                'saved page until a cover is saved again.',
            'Riwayat dan perpustakaan memakai tautan sumber atau halaman '
                'pertama sampai cover disimpan lagi.',
          ),
        ) ||
        !mounted) {
      return;
    }
    await widget.services.catalog.clearSourceCovers();
    PaintingBinding.instance.imageCache.clear();
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsListPage(
      title: localText(context, 'Storage', 'Penyimpanan'),
      children: [
        FutureBuilder<_StorageUsage>(
          future: _usage,
          builder: (context, snapshot) {
            final usage = snapshot.data;
            if (usage == null) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final downloads = usage.titles.fold<int>(
              0,
              (sum, title) => sum + title.bytes,
            );
            final chapters = usage.titles.fold<int>(
              0,
              (sum, title) => sum + title.book.chapters.length,
            );
            final total = downloads + usage.cache + usage.covers;
            final theme = Theme.of(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsGroupCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatBytes(total),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            localText(
                              context,
                              'Used by Kuchie on this iPhone',
                              'Dipakai Kuchie di iPhone ini',
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              height: 8,
                              child: Row(
                                children: [
                                  for (final (bytes, color) in [
                                    (downloads, theme.colorScheme.primary),
                                    (usage.cache, theme.colorScheme.tertiary),
                                    (usage.covers, theme.colorScheme.secondary),
                                  ])
                                    if (bytes > 0)
                                      Expanded(
                                        flex: (bytes * 1000 ~/ total).clamp(
                                          1,
                                          1000,
                                        ),
                                        child: ColoredBox(color: color),
                                      ),
                                  if (total == 0)
                                    Expanded(
                                      child: ColoredBox(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHighest,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.arrow_download_24_regular,
                      title: l10n.downloads,
                      subtitle: localText(
                        context,
                        '${usage.titles.length} titles · $chapters chapters',
                        '${usage.titles.length} judul · $chapters chapter',
                      ),
                      trailing: Text(_formatBytes(downloads)),
                      onTap: () {},
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.broom_24_regular,
                      title: l10n.clearCache,
                      subtitle: localText(
                        context,
                        'Extension data that is downloaded again when needed',
                        'Data ekstensi yang diunduh lagi saat diperlukan',
                      ),
                      trailing: Text(_formatBytes(usage.cache)),
                      onTap: _clearCache,
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.image_multiple_24_regular,
                      title: localText(
                        context,
                        'Saved covers',
                        'Cover tersimpan',
                      ),
                      subtitle: localText(
                        context,
                        'Covers kept for History and the library',
                        'Cover untuk Riwayat dan perpustakaan',
                      ),
                      trailing: Text(_formatBytes(usage.covers)),
                      onTap: _clearCovers,
                    ),
                  ],
                ),
                if (usage.titles.isNotEmpty &&
                    ProviderScope.containerOf(
                      context,
                      listen: false,
                    ).read(syncEngineProvider).enabled) ...[
                  const SizedBox(height: 8),
                  SettingsGroupCard(
                    children: [
                      SettingsGroupRow(
                        icon: FluentIcons.cloud_arrow_up_24_regular,
                        title: localText(
                          context,
                          'Move to server',
                          'Pindahkan ke server',
                        ),
                        subtitle: localText(
                          context,
                          'The server keeps them; this iPhone gets its space back.',
                          'Server menyimpannya; ruang iPhone kembali lega.',
                        ),
                        onTap: () async {
                          if (await showMoveToServerSheet(context) && mounted) {
                            _reload();
                          }
                        },
                      ),
                    ],
                  ),
                ],
                if (usage.titles.isNotEmpty) ...[
                  SettingsGroupHeading(
                    label: localText(
                      context,
                      'Downloads by title',
                      'Unduhan per judul',
                    ),
                  ),
                  SettingsGroupCard(
                    children: [
                      for (final (:book, :bytes) in usage.titles)
                        SettingsGroupRow(
                          icon: FluentIcons.book_24_regular,
                          title: book.title,
                          subtitle: localText(
                            context,
                            '${book.chapters.length} chapters',
                            '${book.chapters.length} chapter',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 8,
                            children: [
                              Text(_formatBytes(bytes)),
                              const Icon(FluentIcons.delete_24_regular),
                            ],
                          ),
                          onTap: () => _deleteTitle(book),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

void openLocalReadingInsights(
  BuildContext context,
  LocalCollectionServices services,
) => openReadingInsights(context, keptCover: services.catalog.keptCover);

/// Reading Insights for either collection. [keptCover] finds covers kept for
/// Local titles; Server titles carry their cover path.
void openReadingInsights(
  BuildContext context, {
  File? Function(String seriesId)? keptCover,
}) => _push(context, _ReadingInsights(keptCover: keptCover));

/// Reading time in total and per title, as in Tachimanga's Reading Insights.
class _ReadingInsights extends StatelessWidget {
  const _ReadingInsights({this.keptCover});

  final File? Function(String seriesId)? keptCover;

  @override
  Widget build(BuildContext context) {
    final stats = LocalReadingStats.instance;
    return Scaffold(
      appBar: detailNavigationAppBar(
        context,
        title: Text(localText(context, 'Reading Insights', 'Statistik Baca')),
      ),
      body: FutureBuilder<void>(
        future: stats.load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListenableBuilder(
            listenable: stats,
            builder: (context, _) {
              final ranked = stats.ranked;
              final theme = Theme.of(context);
              final longest = ranked.firstOrNull?.time.inSeconds ?? 1;
              final since = stats.since;
              final date = since == null
                  ? null
                  : MaterialLocalizations.of(context).formatMediumDate(since);
              return ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: ranked.length + 1,
                itemBuilder: (context, index) {
                  if (index > 0) {
                    final entry = ranked[index - 1];
                    return _ReadingTimeRow(
                      entry: entry,
                      keptCover: keptCover,
                      share: entry.time.inSeconds / longest,
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatReadingTime(stats.total),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        date == null
                            ? localText(
                                context,
                                'Reading time is counted while the reader is open.',
                                'Waktu baca dihitung selama reader terbuka.',
                              )
                            : localText(
                                context,
                                'Reading time counted since $date.',
                                'Waktu baca dihitung sejak $date.',
                              ),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      if (ranked.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              localText(
                                context,
                                'Read a chapter to see your insights.',
                                'Baca satu chapter untuk melihat statistik.',
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ReadingTimeRow extends StatelessWidget {
  const _ReadingTimeRow({
    required this.entry,
    required this.keptCover,
    required this.share,
  });

  final LocalReadingTime entry;
  final File? Function(String seriesId)? keptCover;

  /// This title's time against the longest, from 0 to 1.
  final double share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.book_outlined),
    );
    final kept = keptCover?.call(entry.seriesId);
    final cacheWidth = (40 * MediaQuery.devicePixelRatioOf(context)).round();
    final Widget cover = switch (entry.cover) {
      final path? when path.isNotEmpty => ServerImage(
        imageUrl: path,
        memCacheWidth: cacheWidth,
        fit: BoxFit.cover,
      ),
      _ when kept != null => Image.file(
        kept,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => placeholder,
      ),
      _ => placeholder,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            // A bar as long as this title's share of the longest read.
            FractionallySizedBox(
              widthFactor: share.clamp(0.08, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(width: 40, height: 56, child: cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        formatReadingTime(entry.time),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void openLocalBackups(
  BuildContext context,
  LocalCollectionServices services, {
  required VoidCallback onRestored,
}) => _push(
  context,
  _LocalBackupsPage(services: services, onRestored: onRestored),
);

/// Tachimanga's Backup & Restore: make or restore a backup, back up on a
/// schedule, and manage the backups kept on this iPhone.
class _LocalBackupsPage extends StatefulWidget {
  const _LocalBackupsPage({required this.services, required this.onRestored});

  final LocalCollectionServices services;
  final VoidCallback onRestored;

  @override
  State<_LocalBackupsPage> createState() => _LocalBackupsPageState();
}

class _LocalBackupsPageState extends State<_LocalBackupsPage> {
  final _backups = LocalBackups.instance;
  late Future<List<LocalBackupFile>> _files = _backups.list();

  @override
  void initState() {
    super.initState();
    unawaited(_backups.load());
    _backups.revision.addListener(_reload);
  }

  @override
  void dispose() {
    _backups.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _files = _backups.list());
  }

  LocalCatalog get _catalog => widget.services.catalog;

  Future<void> _create() async {
    try {
      await _backups.create(_catalog);
      _reload();
      if (mounted) {
        _notify(
          context,
          localText(context, 'Backup created', 'Cadangan dibuat'),
        );
      }
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Future<void> _restore(File file) async {
    try {
      final result = await _catalog.restoreMetadata(file);
      widget.onRestored();
      if (!mounted) return;
      _notify(
        context,
        localText(
          context,
          '${result.restored} restored, ${result.skipped} chapters skipped',
          '${result.restored} dipulihkan, ${result.skipped} chapter dilewati',
        ),
      );
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Future<void> _restoreFromFiles() async {
    final picked = await FilePicker.pickFile();
    if (picked?.path case final path? when mounted) {
      await _restore(File(path));
    }
  }

  Future<void> _save(File file) async {
    try {
      await FilePicker.saveFile(
        fileName: file.uri.pathSegments.last,
        bytes: await file.readAsBytes(),
        mimeType: 'application/json',
      );
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Future<void> _backupActions(LocalBackupFile backup) async {
    final choice = await showAppBottomSheet<String>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(
            title: MaterialLocalizations.of(
              sheet,
            ).formatMediumDate(backup.createdAt),
          ),
          ListTile(
            leading: const Icon(FluentIcons.arrow_counterclockwise_24_regular),
            title: Text(localText(sheet, 'Restore', 'Pulihkan')),
            onTap: () => Navigator.pop(sheet, 'restore'),
          ),
          ListTile(
            leading: const Icon(FluentIcons.save_24_regular),
            title: Text(localText(sheet, 'Save to Files', 'Simpan ke File')),
            onTap: () => Navigator.pop(sheet, 'save'),
          ),
          ListTile(
            leading: const Icon(FluentIcons.delete_24_regular),
            title: Text(localText(sheet, 'Delete', 'Hapus')),
            onTap: () => Navigator.pop(sheet, 'delete'),
          ),
          SizedBox(height: MediaQuery.paddingOf(sheet).bottom),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'restore':
        if (await localConfirm(
              context,
              localText(
                context,
                'Restore this backup?',
                'Pulihkan cadangan ini?',
              ),
              localText(
                context,
                'Library entries, categories and reading progress from the '
                    'backup are added to this iPhone.',
                'Judul, kategori, dan progres baca dari cadangan ditambahkan '
                    'ke iPhone ini.',
              ),
            ) &&
            mounted) {
          await _restore(backup.file);
        }
      case 'save':
        await _save(backup.file);
      case 'delete':
        await _backups.delete(backup.file);
    }
  }

  Future<void> _chooseFrequency() async {
    String label(LocalBackupFrequency value) => _frequencyLabel(context, value);
    final chosen = await showAppBottomSheet<LocalBackupFrequency>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(
            title: localText(sheet, 'Backup frequency', 'Frekuensi cadangan'),
          ),
          for (final value in LocalBackupFrequency.values)
            ListTile(
              title: Text(label(value)),
              trailing: _backups.frequency.value == value
                  ? const Icon(FluentIcons.checkmark_24_regular)
                  : null,
              onTap: () => Navigator.pop(sheet, value),
            ),
          SizedBox(height: MediaQuery.paddingOf(sheet).bottom),
        ],
      ),
    );
    if (chosen == null) return;
    await _backups.setFrequency(chosen);
    await _backups.runIfDue(_catalog);
  }

  Future<void> _chooseMax() async {
    final chosen = await showAppBottomSheet<int>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(
            title: localText(sheet, 'Maximum backups', 'Cadangan maksimum'),
          ),
          for (final value in LocalBackups.maxChoices)
            ListTile(
              title: Text('$value'),
              trailing: _backups.maxBackups.value == value
                  ? const Icon(FluentIcons.checkmark_24_regular)
                  : null,
              onTap: () => Navigator.pop(sheet, value),
            ),
          SizedBox(height: MediaQuery.paddingOf(sheet).bottom),
        ],
      ),
    );
    if (chosen != null) await _backups.setMaxBackups(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return SettingsListPage(
      title: localText(context, 'Backup & Restore', 'Backup & Pulihkan'),
      children: [
        SettingsGroupCard(
          children: [
            SettingsGroupRow(
              icon: FluentIcons.add_24_regular,
              title: localText(context, 'Create backup', 'Buat cadangan'),
              subtitle: localText(
                context,
                'Saves titles, categories, bookmarks and reading progress. '
                    'Chapter files are not included.',
                'Menyimpan judul, kategori, penanda, dan progres baca. File '
                    'chapter tidak termasuk.',
              ),
              trailing: _chevron,
              onTap: _create,
            ),
            SettingsGroupRow(
              icon: FluentIcons.history_24_regular,
              title: localText(context, 'Restore backup', 'Pulihkan cadangan'),
              subtitle: localText(
                context,
                'Restore the library from a backup file',
                'Pulihkan perpustakaan dari file cadangan',
              ),
              trailing: _chevron,
              onTap: _restoreFromFiles,
            ),
          ],
        ),
        SettingsGroupHeading(
          label: localText(context, 'Automatic backups', 'Cadangan otomatis'),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([
            _backups.frequency,
            _backups.maxBackups,
            _backups.lastAutomatic,
          ]),
          builder: (context, _) {
            final last = _backups.lastAutomatic.value;
            return SettingsGroupCard(
              children: [
                SettingsGroupRow(
                  icon: FluentIcons.clock_24_regular,
                  title: localText(
                    context,
                    'Backup frequency',
                    'Frekuensi cadangan',
                  ),
                  subtitle: _frequencyLabel(context, _backups.frequency.value),
                  trailing: _chevron,
                  onTap: _chooseFrequency,
                ),
                SettingsGroupRow(
                  icon: FluentIcons.arrow_up_24_regular,
                  title: localText(
                    context,
                    'Maximum backups',
                    'Cadangan maksimum',
                  ),
                  subtitle: '${_backups.maxBackups.value}',
                  trailing: _chevron,
                  onTap: _chooseMax,
                ),
                if (last != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      localText(
                        context,
                        'Last automatically backed up: '
                            '${localizations.formatMediumDate(last)} '
                            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(last))}',
                        'Cadangan otomatis terakhir: '
                            '${localizations.formatMediumDate(last)} '
                            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(last))}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            );
          },
        ),
        SettingsGroupHeading(label: localText(context, 'Backups', 'Cadangan')),
        FutureBuilder<List<LocalBackupFile>>(
          future: _files,
          builder: (context, snapshot) {
            final files = snapshot.data ?? const <LocalBackupFile>[];
            if (files.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  localText(
                    context,
                    'No backups on this iPhone yet.',
                    'Belum ada cadangan di iPhone ini.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            }
            return SettingsGroupCard(
              children: [
                for (final backup in files)
                  SettingsGroupRow(
                    icon: backup.automatic
                        ? FluentIcons.arrow_sync_24_regular
                        : FluentIcons.document_24_regular,
                    title:
                        '${localizations.formatMediumDate(backup.createdAt)} '
                        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(backup.createdAt))}',
                    subtitle:
                        '${backup.automatic ? localText(context, 'Automatic backup', 'Cadangan otomatis') : localText(context, 'Backup', 'Cadangan')} · ${_formatBytes(backup.bytes)}',
                    trailing: const Icon(
                      FluentIcons.more_horizontal_24_regular,
                    ),
                    onTap: () => _backupActions(backup),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _frequencyLabel(BuildContext context, LocalBackupFrequency value) =>
    switch (value) {
      LocalBackupFrequency.off => localText(context, 'Off', 'Mati'),
      LocalBackupFrequency.every6Hours => localText(
        context,
        'Every 6 hours',
        'Setiap 6 jam',
      ),
      LocalBackupFrequency.every12Hours => localText(
        context,
        'Every 12 hours',
        'Setiap 12 jam',
      ),
      LocalBackupFrequency.daily => localText(context, 'Daily', 'Setiap hari'),
      LocalBackupFrequency.every2Days => localText(
        context,
        'Every 2 days',
        'Setiap 2 hari',
      ),
      LocalBackupFrequency.weekly => localText(
        context,
        'Weekly',
        'Setiap minggu',
      ),
    };

/// Sources that offer settings, as Tachimanga's Source Settings lists them.
class _LocalSourceSettingsList extends StatelessWidget {
  const _LocalSourceSettingsList({required this.sources});

  final LocalSources sources;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: detailNavigationAppBar(
      context,
      title: Text(localText(context, 'Source settings', 'Pengaturan sumber')),
    ),
    body: FutureBuilder<List<LocalExtension>>(
      future: sources.sources(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(localErrorMessage(context, snapshot.error!)),
          );
        }
        final all = snapshot.data;
        if (all == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final configurable = [
          for (final source in all)
            if (source.canHaveSettings) source,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (configurable.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                localText(
                  context,
                  'No installed source has settings.',
                  'Belum ada sumber terpasang yang punya pengaturan.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            for (final source in configurable)
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox.square(
                    dimension: 40,
                    child: source.icon == null
                        ? const Icon(FluentIcons.puzzle_piece_24_regular)
                        // The same cached loader as Browse uses for icons.
                        : ServerImage(
                            imageUrl: source.icon.toString(),
                            size: const Size.square(40),
                          ),
                  ),
                ),
                title: Text(source.name),
                subtitle: Text(source.language),
                trailing: _chevron,
                onTap: () => _push(
                  context,
                  LocalSourceSettingsScreen(
                    sources: sources,
                    extension: source,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
