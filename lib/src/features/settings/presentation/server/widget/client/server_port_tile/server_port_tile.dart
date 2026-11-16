// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../widgets/compact_switch.dart';
import '../../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../data/server_connection/server_port.dart';

class ServerPortTile extends ConsumerWidget {
  const ServerPortTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverPort = ref.watch(serverPortProvider);
    final serverToggle = ref.watch(serverPortToggleProvider).ifNull();
    return SettingsPropTile(
      title: context.l10n.serverPort,
      subtitle: serverToggle ? serverPort.toString() : null,
      leading: const Icon(FluentIcons.server_24_regular),
      trailing: CompactSwitch(
        value: serverToggle,
        onChanged: (value) async {
          await ref.read(serverPortToggleProvider.notifier).update(value);
        },
      ),
      type: SettingsPropType<void>.numberPicker(
        min: 0,
        max: 65535,
        value: serverPort,
        onChanged: serverToggle
            ? (port) async {
                await ref.read(serverPortProvider.notifier).update(port);
                return;
              }
            : null,
      ),
    );
  }
}
