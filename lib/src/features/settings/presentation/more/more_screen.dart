// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../constants/enum.dart';
import '../../../../constants/urls.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/compact_switch.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/ios/apple_glass_capability.dart';
import '../../../../widgets/kuchie_logo.dart';
import '../../../../widgets/web_selection_area.dart';
import '../../../account/data/account_providers.dart';
import '../../../account/presentation/sign_out_action.dart';
import '../../../auth/data/auth_session_status.dart';
import '../../../auth/data/auth_state.dart';
import '../../../local_collection/presentation/local_settings.dart';
import '../../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../../quick_open/presentation/unified_search/unified_search_providers.dart';
import '../../../security/security_settings_screen.dart';
import '../../data/server_connection/server_port.dart';
import '../../data/server_connection/server_url.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import '../connection/connection_status.dart';
import '../incognito/incognito_mode.dart';
import '../library/widgets/persistent_search_bar/persistent_search_bar.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authType = ref.watch(authTypeKeyProvider);
    final account = ref.watch(currentAccountProvider);
    final showAccount = ref.watch(showAccountEntryProvider);
    final hasStoredCredentials = ref.watch(hasStoredCredentialsProvider);
    final incognito = ref.watch(incognitoModeProvider);
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final compactIOS = supportsAppleGlass(context);
    final persistentBox =
        phone && ref.watch(libraryPersistentSearchBarProvider).ifNull();
    final topBar = showsMergedTopBar(context);
    const chevron = Icon(FluentIcons.chevron_right_24_regular);
    Widget group(List<Widget> rows) =>
        compactIOS ? Column(children: rows) : SettingsGroupCard(children: rows);

    Widget routeRow(IconData icon, String title, VoidCallback open) =>
        SettingsGroupRow(
          icon: icon,
          title: title,
          trailing: chevron,
          onTap: open,
        );

    final search = DesktopSearchField(
      query: ref.watch(unifiedSearchQueryProvider),
      onChanged: (value) =>
          ref.read(unifiedSearchQueryProvider.notifier).state = value,
      onNavigate: () =>
          ref.read(unifiedSearchQueryProvider.notifier).state = '',
    );

    Widget accountSection() {
      final host = formatServerHost(
        ref.watch(serverUrlProvider),
        ref.watch(serverPortProvider),
        ref.watch(serverPortToggleProvider).ifNull(),
      );
      final statusLabel = switch (connectionAuthStatus(
        ref.watch(authTypeKeyProvider),
        ref.watch(needsReauthProvider) ||
            ((authType ?? AuthType.none) != AuthType.none &&
                !ref.watch(hasStoredCredentialsProvider)),
      )) {
        ConnectionAuthStatus.signedIn => context.l10n.connectionAuthSignedIn,
        ConnectionAuthStatus.noAuth => context.l10n.connectionAuthNone,
        ConnectionAuthStatus.signInNeeded =>
          context.l10n.connectionAuthSignInNeeded,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compactIOS)
            SettingsGroupHeading(
              label: context.l10n.accountTitle,
              first: context.usesDesktopShell,
            ),
          group([
            if (showAccount)
              SettingsGroupRow(
                icon: FluentIcons.person_24_regular,
                title: account?.username ?? context.l10n.accountTitle,
                subtitle: compactIOS
                    ? statusLabel
                    : (host.isEmpty ? null : host),
                trailing: chevron,
                onTap: () => const ConnectionRoute().push(context),
              )
            else
              SettingsGroupRow(
                icon: FluentIcons.server_24_regular,
                title: compactIOS || host.isEmpty
                    ? context.l10n.connection
                    : host,
                subtitle: statusLabel,
                trailing: chevron,
                onTap: () => const ConnectionRoute().push(context),
              ),
            if (showAccount && hasStoredCredentials)
              ListTile(
                leading: Icon(
                  FluentIcons.sign_out_24_regular,
                  color: context.theme.colorScheme.error,
                ),
                title: Text(
                  context.l10n.accountSignOut,
                  style: TextStyle(color: context.theme.colorScheme.error),
                ),
                onTap: () => confirmAndSignOutAccount(context, ref),
              ),
          ]),
        ],
      );
    }

    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              centerTitle: compactIOS ? true : null,
              title: context.usesDesktopShell
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: search,
                      ),
                    )
                  : Text(context.l10n.more),
              bottom: persistentBox
                  ? const PhoneSearchBoxBottom(origin: PhoneSearchOrigin.plain)
                  : null,
              actions: [
                if (phone && !persistentBox)
                  const PhoneSearchEntry(origin: PhoneSearchOrigin.plain),
              ],
            ),
      body: WebSelectionArea(
        child: Center(
          child: ConstrainedBox(
            constraints: settingsPageConstraints(context),
            child: ListView(
              padding: compactIOS
                  ? EdgeInsets.fromLTRB(
                      0,
                      8,
                      0,
                      MediaQuery.paddingOf(context).bottom + 16,
                    )
                  : null,
              children: [
                if (!compactIOS && !context.usesDesktopShell) ...[
                  KuchieLogo(size: context.height * .2),
                ],
                accountSection(),
                if (compactIOS)
                  const Divider(height: 16)
                else
                  SettingsGroupHeading(label: context.l10n.library),
                // The same order as the Local collection's More tab, so both
                // collections read alike.
                group([
                  SettingsGroupRow(
                    icon: FluentIcons.incognito_24_regular,
                    title: context.l10n.incognitoMode,
                    subtitle: context.l10n.incognitoModeDescription,
                    trailing: CompactSwitch(
                      value: incognito,
                      onChanged: (value) =>
                          ref.read(incognitoModeProvider.notifier).set(value),
                    ),
                    onTap: () => ref
                        .read(incognitoModeProvider.notifier)
                        .set(!incognito),
                  ),
                  if (compactIOS)
                    routeRow(
                      FluentIcons.options_24_regular,
                      context.l10n.general,
                      () => const GeneralSettingsRoute().push(context),
                    ),
                  routeRow(
                    FluentIcons.color_24_regular,
                    context.l10n.appearance,
                    () => const AppearanceSettingsRoute().push(context),
                  ),
                  if (compactIOS) ...[
                    routeRow(
                      FluentIcons.library_24_regular,
                      context.l10n.library,
                      () => const LibrarySettingsRoute().push(context),
                    ),
                    routeRow(
                      FluentIcons.book_open_24_regular,
                      context.l10n.reader,
                      () => const ReaderSettingsRoute().push(context),
                    ),
                    routeRow(
                      FluentIcons.cloud_sync_24_regular,
                      context.l10n.sync,
                      () => const SyncRoute().push(context),
                    ),
                    routeRow(
                      FluentIcons.arrow_sync_24_regular,
                      context.l10n.tracking,
                      () => const TrackingSettingsRoute().push(context),
                    ),
                    routeRow(
                      FluentIcons.puzzle_piece_24_regular,
                      context.l10n.extensions,
                      () => const BrowseSettingsRoute().push(context),
                    ),
                  ] else
                    routeRow(
                      FluentIcons.tag_24_regular,
                      context.l10n.categories,
                      () => const EditCategoriesRoute().push(context),
                    ),
                  routeRow(
                    FluentIcons.arrow_counterclockwise_24_regular,
                    context.l10n.backup,
                    () => const BackupRoute().push(context),
                  ),
                  routeRow(
                    FluentIcons.shield_lock_24_regular,
                    context.l10n.securityAndPrivacy,
                    () => openSecuritySettings(context),
                  ),
                  routeRow(
                    FluentIcons.data_trending_24_regular,
                    context.l10n.readingInsights,
                    () => openReadingInsights(context),
                  ),
                  routeRow(
                    FluentIcons.arrow_download_24_regular,
                    context.l10n.downloads,
                    () => const DownloadsRoute().go(context),
                  ),
                ]),
                const SizedBox(height: 16),
                group([
                  // Server, network and data settings; Local keeps these
                  // under General.
                  routeRow(
                    FluentIcons.settings_24_regular,
                    context.l10n.settings,
                    () => const SettingsRoute().push(context),
                  ),
                  routeRow(
                    FluentIcons.share_ios_24_regular,
                    context.l10n.share,
                    () => SharePlus.instance.share(
                      ShareParams(
                        uri: Uri.parse(KuchieLinks.project),
                        title: 'Kuchie',
                      ),
                    ),
                  ),
                  routeRow(
                    FluentIcons.question_circle_24_regular,
                    context.l10n.help,
                    () => launchUrlInWeb(
                      context,
                      AppUrls.serverHelp.url,
                      ref.read(toastProvider),
                    ),
                  ),
                  routeRow(
                    FluentIcons.info_24_regular,
                    context.l10n.about,
                    () => const AboutRoute().push(context),
                  ),
                ]),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
    return topBar
        ? TopBarSlot(
            content: desktopSearchSlotContent(
              search: search,
              actions: const [],
            ),
            minWidth: searchTopBarSlotMinWidth(0),
            child: scaffold,
          )
        : scaffold;
  }
}
