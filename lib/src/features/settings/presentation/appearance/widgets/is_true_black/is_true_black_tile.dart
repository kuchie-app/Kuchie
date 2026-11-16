// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/app_theme.dart';
import '../../../../../../constants/db_keys.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../../widgets/compact_switch.dart';
import '../../../../../../widgets/ios/apple_glass_capability.dart';
import '../app_theme_selector/app_theme_providers.dart';

part 'is_true_black_tile.g.dart';

@riverpod
class IsTrueBlack extends _$IsTrueBlack with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.isTrueBlack);
}

/// Pure black stays on until chosen otherwise for Indigo Night with Liquid Glass.
///
/// The only source of the default, so the switch and every theme agree.
bool effectiveTrueBlack({
  required bool? saved,
  required AppTheme theme,
  required bool appleGlass,
}) => saved ?? (appleGlass && theme == AppTheme.indigoNight);

class IsTrueBlackTile extends HookConsumerWidget {
  const IsTrueBlackTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CompactSwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(context.l10n.pureBlackAmoled),
      onChanged: ref.read(isTrueBlackProvider.notifier).update,
      value: effectiveTrueBlack(
        saved: ref.watch(isTrueBlackProvider),
        theme: ref.watch(appThemeKeyProvider) ?? AppTheme.indigoNight,
        appleGlass: appleGlassEnabled(context),
      ),
    );
  }
}
