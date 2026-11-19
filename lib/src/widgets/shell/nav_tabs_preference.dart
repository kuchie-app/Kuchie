import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../constants/navigation_bar_data.dart';
import '../../global_providers/global_providers.dart';

/// A bottom tab of the app shell. [branch] is its index in the server shell's
/// routes; on-device collections use [localSection].
enum AppTab {
  library(0, 0),
  updates(1, 1),
  browse(3, 2),
  history(2, 3),
  downloads(4, null),
  more(5, 4);

  const AppTab(this.branch, this.localSection);

  final int branch;

  /// The tab's section in the Local collection, or null when it has none.
  final int? localSection;

  NavigationBarData get data => NavigationBarData.desktopNavList.firstWhere(
    (tab) => tab.motion.name == name,
    orElse: () => NavigationBarData.phoneNavList.firstWhere(
      (tab) => tab.motion.name == name,
    ),
  );
}

/// Which tabs the bottom bar shows, in what order, and whether with labels.
/// More always stays, so every screen stays reachable.
@immutable
class NavTabs {
  const NavTabs({
    required this.order,
    required this.hidden,
    this.labels = true,
  });

  static const defaults = NavTabs(
    order: [
      AppTab.library,
      AppTab.updates,
      AppTab.browse,
      AppTab.history,
      AppTab.more,
      AppTab.downloads,
    ],
    hidden: {AppTab.downloads},
  );

  final List<AppTab> order;
  final Set<AppTab> hidden;
  final bool labels;

  List<AppTab> get visible => [
    for (final tab in order)
      if (!hidden.contains(tab) || tab == AppTab.more) tab,
  ];

  /// The visible tabs a Local collection can show (it has no Downloads tab).
  List<AppTab> get visibleLocal => [
    for (final tab in visible)
      if (tab.localSection != null) tab,
  ];

  NavTabs copyWith({List<AppTab>? order, Set<AppTab>? hidden, bool? labels}) =>
      NavTabs(
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
        labels: labels ?? this.labels,
      );
}

final navTabsProvider = NotifierProvider<NavTabsNotifier, NavTabs>(
  NavTabsNotifier.new,
);

class NavTabsNotifier extends Notifier<NavTabs> {
  static const _orderKey = 'navTabsOrder';
  static const _hiddenKey = 'navTabsHidden';
  static const _labelsKey = 'navTabsLabels';

  AppTab? _tab(String name) =>
      AppTab.values.where((tab) => tab.name == name).firstOrNull;

  @override
  NavTabs build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = [
      for (final name in prefs.getStringList(_orderKey) ?? const <String>[])
        ?_tab(name),
    ];
    // Tabs added in later versions join at the end.
    final order = [
      ...saved,
      for (final tab in NavTabs.defaults.order)
        if (!saved.contains(tab)) tab,
    ];
    final hiddenNames = prefs.getStringList(_hiddenKey);
    return NavTabs(
      order: order,
      hidden: hiddenNames == null
          ? NavTabs.defaults.hidden
          : {for (final name in hiddenNames) ?_tab(name)},
      labels: prefs.getBool(_labelsKey) ?? true,
    );
  }

  void _save(NavTabs next) {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    prefs
      ..setStringList(_orderKey, [for (final tab in next.order) tab.name])
      ..setStringList(_hiddenKey, [for (final tab in next.hidden) tab.name])
      ..setBool(_labelsKey, next.labels);
  }

  /// Applies a new order of [arranged], a subset of the tabs (the Local
  /// collection leaves Downloads out); the other tabs keep their places.
  void arrange(List<AppTab> arranged) {
    final queue = [...arranged];
    final order = [
      for (final tab in state.order)
        arranged.contains(tab) ? queue.removeAt(0) : tab,
    ];
    _save(state.copyWith(order: order));
  }

  void setVisible(AppTab tab, bool visible) {
    if (tab == AppTab.more) return;
    final hidden = {...state.hidden};
    visible ? hidden.remove(tab) : hidden.add(tab);
    // Keep at least two tabs besides More.
    if (state.copyWith(hidden: hidden).visible.length < 3) return;
    _save(state.copyWith(hidden: hidden));
  }

  void setLabels(bool labels) => _save(state.copyWith(labels: labels));

  void reset() => _save(NavTabs.defaults);
}

/// [data] with its label hidden, for the "Labels" switch.
NavigationBarData navTabData(AppTab tab, {required bool labels}) {
  final data = tab.data;
  if (labels) return data;
  return NavigationBarData(
    icon: data.icon,
    activeIcon: data.activeIcon,
    motion: data.motion,
    label: (_) => '',
  );
}
