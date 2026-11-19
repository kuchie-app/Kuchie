import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../../widgets/shell/nav_tabs_preference.dart';

/// Opens Customize tabs. [local] hides Downloads, which the on-device
/// collection keeps under More.
Future<void> openCustomizeTabs(BuildContext context, {bool local = false}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => CustomizeTabsScreen(local: local)),
    );

/// Arrange the bottom tabs like Tachimanga: a live preview, a Labels switch,
/// and the tabs to show, dragged into order. More always stays.
class CustomizeTabsScreen extends ConsumerWidget {
  const CustomizeTabsScreen({super.key, this.local = false});

  final bool local;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(navTabsProvider);
    final notifier = ref.read(navTabsProvider.notifier);
    final order = [
      for (final tab in tabs.order)
        if (!local || tab.localSection != null) tab,
    ];
    final shown = local ? tabs.visibleLocal : tabs.visible;
    final cs = context.theme.colorScheme;
    return Scaffold(
      appBar: detailNavigationAppBar(
        context,
        title: Text(context.l10n.customizeTabs),
        actions: [
          TextButton(
            onPressed: notifier.reset,
            child: Text(context.l10n.reset),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        children: [
          // Preview of the bar as it will look.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                children: [
                  for (final tab in shown)
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(tab.data.icon, size: 22),
                          if (tabs.labels) ...[
                            const SizedBox(height: 3),
                            Text(
                              tab.data.label(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.labelSmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(FluentIcons.text_font_24_regular),
            title: Text(context.l10n.customizeTabsLabels),
            subtitle: Text(context.l10n.customizeTabsLabelsSubtitle),
            value: tabs.labels,
            onChanged: notifier.setLabels,
          ),
          const Divider(height: 16),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final arranged = [...order];
              arranged.insert(to, arranged.removeAt(from));
              notifier.arrange(arranged);
            },
            children: [
              for (final (index, tab) in order.indexed)
                ListTile(
                  key: ValueKey(tab),
                  leading: Checkbox(
                    value: shown.contains(tab),
                    onChanged: tab == AppTab.more
                        ? null
                        : (on) => notifier.setVisible(tab, on ?? false),
                  ),
                  title: Text(tab.data.label(context)),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(
                      FluentIcons.re_order_dots_vertical_24_regular,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
