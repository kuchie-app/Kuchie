import 'package:material_ui/material_ui.dart';

import '../../../../../utils/extensions/custom_extensions.dart';

class ExtensionInfoContent extends StatelessWidget {
  const ExtensionInfoContent({
    super.key,
    required this.name,
    required this.language,
    required this.version,
    required this.icon,
    required this.actions,
    required this.sources,
    this.restricted = false,
    this.store,
    this.library,
  });

  final String name;
  final String language;
  final String version;
  final Widget icon;
  final Widget actions;
  final Widget sources;
  final bool restricted;
  final String? store;
  final String? library;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: icon,
          title: Text(name, style: context.textTheme.titleLarge),
        ),
        ListTile(title: Text(l10n.extensionVersion), trailing: Text(version)),
        ListTile(title: Text(l10n.extensionLanguage), trailing: Text(language)),
        if (restricted) ListTile(title: Text(l10n.nsfw18)),
        if (store case final value?)
          ListTile(title: Text(l10n.extensionStore), subtitle: Text(value)),
        if (library case final value?)
          ListTile(title: Text(l10n.extensionLibrary), trailing: Text(value)),
        Align(alignment: Alignment.centerLeft, child: actions),
        const Divider(),
        sources,
      ],
    );
  }
}
