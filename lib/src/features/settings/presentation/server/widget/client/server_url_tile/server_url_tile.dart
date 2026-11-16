// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../../../data/server_connection/server_url.dart';
import '../../../../connection/prompt_sign_in.dart';
import 'server_search_button.dart';

class ServerUrlTile extends ConsumerWidget {
  const ServerUrlTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverExternalUrlProvider);
    return SettingsPropTile(
      title: context.l10n.serverUrl,
      subtitle: serverUrl,
      type: SettingsPropType<void>.textField(
        hintText: context.l10n.serverUrlHintText,
        value: serverUrl,
        onChanged: (value) async {
          if (isDifferentServerHost(serverUrl, normaliseServerUrl(value))) {
            final confirmed = await confirmAction(
              context,
              title: context.l10n.confirmServerOriginTitle,
              message: context.l10n.confirmServerOriginMessage,
              action: context.l10n.save,
            );
            if (!confirmed || !context.mounted) return;
          }
          stayOnConnectionAfterIdentityChange();
          await ref.read(serverExternalUrlProvider.notifier).update(value);
          return;
        },
      ),
    );
  }
}

class ServerLanUrlTile extends ConsumerWidget {
  const ServerLanUrlTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverLanUrlProvider);
    return SettingsPropTile(
      title: context.l10n.serverLanUrl,
      subtitle: serverUrl ?? context.l10n.serverLanUrlOptional,
      trailing: !kIsWeb ? const ServerSearchButton() : null,
      type: SettingsPropType<void>.textField(
        hintText: context.l10n.serverLanUrlHintText,
        value: serverUrl,
        onChanged: (value) async {
          ref.read(serverLanUrlProvider.notifier).update(value);
        },
      ),
    );
  }
}
