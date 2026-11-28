import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../local_collection/presentation/local_ui.dart';
import '../controller/extension_sync.dart';

/// Where an extension is installed while sync is on: iPhone, Server or
/// both (design 3.5). Information only; nothing to choose.
class ExtensionLocationBadge extends ConsumerWidget {
  const ExtensionLocationBadge({
    super.key,
    required this.package,
    required this.installedHere,
  });

  final String package;
  final bool installedHere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverExtensionPackagesProvider).value;
    if (server == null) return const SizedBox.shrink();
    final onServer = server.contains(package);
    final label = switch ((installedHere, onServer)) {
      (true, true) => localText(context, 'iPhone + Server', 'iPhone + Server'),
      (true, false) => 'iPhone',
      (false, true) => 'Server',
      (false, false) => null,
    };
    if (label == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
