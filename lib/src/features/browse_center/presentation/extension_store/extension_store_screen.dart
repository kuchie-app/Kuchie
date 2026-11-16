// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/brand_icons.dart';
import '../../../../constants/urls.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/ios/apple_glass_capability.dart';
import '../../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../../widgets/popup_widgets/app_dialog.dart';
import '../../../../widgets/popup_widgets/pop_button.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../../widgets/web_selection_area.dart';
import '../../../account/data/account_providers.dart';
import '../../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../../data/extension_store_repository/extension_store_repository.dart';
import '../../domain/extension_store/extension_store_model.dart';
import 'widgets/add_store_dialog.dart';

final kStoreHelpUrl = AppUrls.serverExtensions.url;

class ExtensionStoreScreen extends ConsumerWidget {
  const ExtensionStoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_EXTENSION_STORES);
    final storeData = ref.watch(extensionStoreListProvider);
    refresh() => ref.refresh(extensionStoreListProvider.future);

    void addStore() {
      showDialog<void>(
        context: context,
        builder: (_) => AddStoreDialog(
          existingUrls: {
            ...?storeData.value?.stores.map((store) => store.indexUrl),
          },
        ),
        animationStyle: context.motionStyle,
      );
    }

    Future<void> removeStore(ExtensionStore store) => AppUtils.guard(() async {
      await ref
          .read(extensionStoreRepositoryProvider)
          .removeStore(store.indexUrl);
      if (!context.mounted) return;
      // ignore: unused_result
      unawaited(ref.refresh(extensionStoreListProvider.future));
    }, ref.read(toastProvider));

    final topBar = showsMergedTopBar(context);
    final glass = !topBar && supportsAppleGlass(context);
    final backButton = detailNavigationBackButton(context);
    final title = Text(l10n.extensionStores);
    final refreshAction = AppleGlassToolbarAction(
      id: 'refresh-extension-stores',
      symbol: 'arrow.clockwise',
      label: l10n.refresh,
      fallbackIcon: FluentIcons.arrow_clockwise_24_regular,
      onPressed: refresh,
    );
    final actions = <Widget>[
      IconButton(
        tooltip: l10n.refresh,
        icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
        onPressed: refresh,
      ),
    ];
    final body = WebSelectionArea(
      child: Center(
        child: ConstrainedBox(
          constraints: settingsPageConstraints(context),
          child: Column(
            children: [
              if (!canManage)
                ListTile(subtitle: Text(context.l10n.accountPermissionDenied)),
              Expanded(
                child: storeData.showUiWhenData(context, (data) {
                  final stores = data?.stores ?? const <ExtensionStore>[];
                  if (stores.isEmpty) {
                    return Emoticons(
                      title: context.l10n.extensionStoresEmpty,
                      button: TextButton.icon(
                        onPressed: () => launchUrlInWeb(
                          context,
                          kStoreHelpUrl,
                          ref.read(toastProvider),
                        ),
                        icon: const Icon(
                          FluentIcons.question_circle_24_regular,
                        ),
                        label: Text(context.l10n.help),
                      ),
                    );
                  }
                  return ListView(
                    padding: settingsPagePadding(context, KEdgeInsets.a8.size),
                    children: [
                      SettingsGroupCard(
                        children: [
                          for (final store in stores)
                            ListTile(
                              leading: const Icon(
                                FluentIcons.puzzle_piece_24_regular,
                                size: 48,
                              ),
                              title: Text(store.name),
                              subtitle: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (store.contactWebsite.isNotBlank)
                                    IconButton(
                                      tooltip: l10n.openInBrowser,
                                      icon: const Icon(
                                        FluentIcons.globe_24_regular,
                                      ),
                                      onPressed: () => launchUrlInWeb(
                                        context,
                                        store.contactWebsite,
                                        ref.read(toastProvider),
                                      ),
                                    ),
                                  if (store.contactDiscord != null)
                                    IconButton(
                                      tooltip: l10n.discord,
                                      icon: const Icon(BrandIcons.discord),
                                      onPressed: () => launchUrlInWeb(
                                        context,
                                        store.contactDiscord!,
                                        ref.read(toastProvider),
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: MaterialLocalizations.of(
                                      context,
                                    ).copyButtonLabel,
                                    icon: const Icon(
                                      FluentIcons.copy_24_regular,
                                    ),
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: store.indexUrl),
                                      );
                                      if (context.mounted) {
                                        ref
                                            .read(toastProvider)
                                            ?.show(context.l10n.copied);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    tooltip: l10n.removeExtensionStore,
                                    icon: const Icon(
                                      FluentIcons.delete_24_regular,
                                    ),
                                    onPressed: !canManage
                                        ? null
                                        : () => showDialog(
                                            context: context,
                                            builder: (_) => AdaptiveAppAlert(
                                              title: Text(
                                                context
                                                    .l10n
                                                    .removeExtensionStore,
                                              ),
                                              content: Text(
                                                context.l10n
                                                    .removeExtensionStoreBody(
                                                      store.name,
                                                      store.indexUrl,
                                                    ),
                                              ),
                                              actions: [
                                                const PopButton(),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    Navigator.pop(context);
                                                    removeStore(store);
                                                  },
                                                  child: Text(context.l10n.ok),
                                                ),
                                              ],
                                            ),
                                            animationStyle: context.motionStyle,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                }, refresh: refresh),
              ),
            ],
          ),
        ),
      ),
    );
    final scaffold = Scaffold(
      appBar: topBar || glass
          ? null
          : AppBar(leading: backButton, title: title, actions: actions),
      floatingActionButton: canManage && !glass
          ? FloatingActionButton(
              tooltip: l10n.addExtensionStore,
              onPressed: addStore,
              child: const Icon(FluentIcons.add_24_regular),
            )
          : null,
      body: glass
          ? SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                          backButton == null ? 16 : 68,
                          4,
                          canManage ? 116 : 68,
                          4,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Semantics(
                              header: true,
                              namesRoute: true,
                              child: Text(
                                l10n.extensionStores,
                                style: context.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: body),
                    ],
                  ),
                  // Paint native controls after the Flutter content so it stays
                  // in the base layer rather than the platform-view overlay.
                  if (backButton != null)
                    PositionedDirectional(start: 12, top: 4, child: backButton),
                  PositionedDirectional(
                    end: 12,
                    top: 4,
                    child: AppleGlassToolbar(
                      joined: true,
                      actions: [
                        refreshAction,
                        if (canManage)
                          AppleGlassToolbarAction(
                            id: 'add-extension-store',
                            symbol: 'plus',
                            label: l10n.addExtensionStore,
                            fallbackIcon: FluentIcons.add_24_regular,
                            onPressed: addStore,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : body,
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: backButton,
      title: title,
      actions: actions,
      child: scaffold,
    );
  }
}
