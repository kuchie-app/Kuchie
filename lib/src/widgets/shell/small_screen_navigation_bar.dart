// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../constants/navigation_bar_data.dart';
import '../../features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import '../../features/offline/data/offline_nav_status.dart';
import 'apple_liquid_glass_tab_bar.dart';
import 'nav_badges.dart';
import 'nav_motion_icon.dart';

class SmallScreenNavigationBar extends ConsumerWidget {
  const SmallScreenNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.glassLayout = false,
  });

  final int selectedIndex;
  final bool glassLayout;
  final void Function(int) onDestinationSelected;

  NavigationDestination getNavigationDestination(
    BuildContext context,
    NavigationBarData data,
    bool selected,
    bool downloadsPaused,
    int extensionUpdates,
  ) {
    final icon = NavMotionIcon(data, selected: selected);
    return NavigationDestination(
      icon: badgedNavIcon(icon, data, downloadsPaused, extensionUpdates),
      label: data.label(context),
      tooltip: data.label(context),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsPaused = ref.watch(downloadsPausedBadgeProvider);
    final extensionUpdates =
        ref.watch(extensionUpdateBadgeCountProvider).value ?? 0;
    final navList = glassLayout
        ? NavigationBarData.glassPhoneNavList
        : NavigationBarData.getNavList(context);
    Widget standardBar(BuildContext context) => NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        for (var i = 0; i < navList.length; i++)
          getNavigationDestination(
            context,
            navList[i],
            i == selectedIndex,
            downloadsPaused,
            extensionUpdates,
          ),
      ],
    );
    if (!glassLayout) {
      return standardBar(context);
    }
    return AppleLiquidGlassTabBar(
      tabs: navList,
      selectedIndex: selectedIndex,
      downloadsPaused: downloadsPaused,
      extensionUpdates: extensionUpdates,
      onDestinationSelected: onDestinationSelected,
    );
  }
}
