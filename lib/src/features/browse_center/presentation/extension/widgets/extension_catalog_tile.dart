import 'package:material_ui/material_ui.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../utils/extensions/custom_extensions.dart';

class ExtensionCatalogTile extends StatelessWidget {
  const ExtensionCatalogTile({
    super.key,
    required this.name,
    required this.language,
    required this.version,
    required this.icon,
    required this.trailing,
    required this.onTap,
    this.restricted = false,
    this.permissionLabel,
    this.badge,
  });

  final String name;
  final String language;
  final String version;
  final Widget icon;
  final Widget trailing;
  final VoidCallback onTap;
  final bool restricted;
  final String? permissionLabel;

  /// Shown at the end of the second line, such as where the extension is
  /// installed.
  final Widget? badge;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: ClipRRect(borderRadius: KBorderRadius.r8.radius, child: icon),
    title: Text(name, overflow: TextOverflow.ellipsis),
    subtitle: Text.rich(
      TextSpan(
        text: '$language ',
        style: const TextStyle(fontWeight: FontWeight.w600),
        children: [
          if (permissionLabel case final label?)
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          if (version.isNotBlank)
            TextSpan(
              text: '$version ',
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          if (restricted)
            TextSpan(
              text: '${context.l10n.nsfw18} ',
              style: TextStyle(
                fontWeight: FontWeight.w400,
                color: context.colorScheme.error,
              ),
            ),
          if (badge case final badge?)
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: badge),
        ],
      ),
    ),
    trailing: trailing,
  );
}
