// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../../widgets/compact_switch.dart';
import '../../../../../../widgets/ios/apple_glass_capability.dart';

part 'liquid_glass_tile.g.dart';

/// The user's choice; null follows the device.
@riverpod
class LiquidGlassPreference extends _$LiquidGlassPreference
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.liquidGlass);
}

/// Glass shows only on capable devices, on unless the user turned it off.
///
/// A limited device stays off even with a saved "on" from another device.
bool effectiveAppleGlass({
  required AppleGlassCapability capability,
  required bool? saved,
}) => capability == AppleGlassCapability.capable && (saved ?? true);

class LiquidGlassTile extends ConsumerWidget {
  const LiquidGlassTile({super.key});

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capability = appleGlassCapabilityOf(context);
    final capable = capability == AppleGlassCapability.capable;
    final l10n = context.l10n;
    return CompactSwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(l10n.liquidGlass),
      subtitle: Text(switch (capability) {
        AppleGlassCapability.capable => l10n.liquidGlassSubtitle,
        AppleGlassCapability.limited => l10n.liquidGlassLimited,
        AppleGlassCapability.unsupported => l10n.liquidGlassUnsupported,
      }),
      value: effectiveAppleGlass(
        capability: capability,
        saved: ref.watch(liquidGlassPreferenceProvider),
      ),
      // Locked off where the device cannot keep the effects smooth.
      onChanged: capable
          ? ref.read(liquidGlassPreferenceProvider.notifier).update
          : null,
    );
  }
}
