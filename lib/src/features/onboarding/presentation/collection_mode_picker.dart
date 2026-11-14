import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/ios/apple_page_title.dart';
import '../data/collection_mode.dart';
import 'collection_choice_step.dart';

String collectionModeTitle(BuildContext context) =>
    collectionText(context, 'Collection mode', 'Mode koleksi');

Future<void> showServerCollectionPicker(
  BuildContext context,
  WidgetRef ref, {
  required String section,
}) async {
  final mode = await showCollectionModePicker(context, CollectionMode.server);
  if (mode == CollectionMode.local && context.mounted) {
    await openLocalCollection(context, ref, section);
  }
}

String collectionModeLabel(BuildContext context, CollectionMode mode) =>
    switch (mode) {
      CollectionMode.server => context.l10n.server,
      CollectionMode.local => collectionText(context, 'Local', 'Lokal'),
    };

IconData collectionModeIcon(CollectionMode mode, {bool connected = true}) =>
    switch (mode) {
      CollectionMode.local => Icons.phone_iphone_rounded,
      CollectionMode.server =>
        connected ? Icons.cloud_outlined : Icons.cloud_off_outlined,
    };

Future<CollectionMode?> showCollectionModePicker(
  BuildContext context,
  CollectionMode selected,
) => showAppBottomSheet<CollectionMode>(
  context: context,
  isScrollControlled: false,
  builder: (sheetContext) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppSheetHeader(title: collectionModeTitle(sheetContext)),
      for (final mode in CollectionMode.values.reversed)
        ListTile(
          leading: Icon(collectionModeIcon(mode)),
          title: Text(collectionModeLabel(sheetContext, mode)),
          trailing: mode == selected ? const Icon(Icons.check_rounded) : null,
          selected: mode == selected,
          onTap: () => Navigator.of(sheetContext).pop(mode),
        ),
    ],
  ),
);

class CollectionModePageTitle extends StatelessWidget {
  const CollectionModePageTitle(
    this.title, {
    super.key,
    required this.mode,
    required this.onPressed,
    this.connected = true,
  });

  final String title;
  final CollectionMode mode;
  final bool connected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: ApplePageTitle(title)),
      IconButton(
        tooltip: collectionModeTitle(context),
        icon: Icon(collectionModeIcon(mode, connected: connected)),
        onPressed: onPressed,
      ),
    ],
  );
}
