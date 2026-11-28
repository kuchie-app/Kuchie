import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../local_collection/presentation/local_ui.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../controller/extension_sync.dart';

/// Extensions that differ between this iPhone and the server, on the Sync
/// page (design 3.5). Nothing shows when they match, sync is off, or the
/// server can't be reached.
class ExtensionSuggestionsSection extends ConsumerStatefulWidget {
  const ExtensionSuggestionsSection({super.key});

  @override
  ConsumerState<ExtensionSuggestionsSection> createState() =>
      _ExtensionSuggestionsSectionState();
}

class _ExtensionSuggestionsSectionState
    extends ConsumerState<ExtensionSuggestionsSection> {
  bool _installing = false;

  Future<void> _installOnServer(ExtensionSuggestions suggestions) async {
    setState(() => _installing = true);
    final failed = await ref
        .read(extensionSyncProvider)
        .installOnServer(suggestions.onlyHere.map((e) => e.package));
    if (!mounted) return;
    setState(() => _installing = false);
    ref.invalidate(extensionSuggestionsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? localText(
                  context,
                  'Installed on the server',
                  'Terpasang di server',
                )
              : localText(
                  context,
                  "The server couldn't install ${failed.join(', ')}",
                  'Server gagal memasang ${failed.join(', ')}',
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = ref.watch(extensionSuggestionsProvider).value;
    if (suggestions == null || suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    String names(Iterable<String> list) => list.join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroupHeading(
          label: localText(context, 'Extensions', 'Extension'),
        ),
        SettingsGroupCard(
          children: [
            if (suggestions.onlyHere.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(
                  localText(
                    context,
                    '${suggestions.onlyHere.length} only on this iPhone',
                    '${suggestions.onlyHere.length} hanya di iPhone ini',
                  ),
                ),
                subtitle: Text(
                  '${names(suggestions.onlyHere.map((e) => e.name))}. '
                  '${localText(context, 'Install them on the server so their series sync.', 'Pasang di server supaya series-nya ikut tersinkron.')}',
                ),
                trailing: _installing
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: () =>
                            unawaited(_installOnServer(suggestions)),
                        child: Text(localText(context, 'Install', 'Pasang')),
                      ),
              ),
            if (suggestions.onlyOnServer.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.phone_iphone_outlined),
                title: Text(
                  localText(
                    context,
                    '${suggestions.onlyOnServer.length} only on the server',
                    '${suggestions.onlyOnServer.length} hanya di server',
                  ),
                ),
                subtitle: Text(
                  '${names(suggestions.onlyOnServer.map((e) => e.name))}. '
                  '${localText(context, 'Install them in Browse → Extensions to read their series here.', 'Pasang lewat Jelajah → Extension supaya series-nya bisa dibaca di sini.')}',
                ),
              ),
            if (suggestions.notInServerStores.isNotEmpty)
              ListTile(
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  localText(
                    context,
                    "Not in the server's stores",
                    'Tidak ada di store server',
                  ),
                ),
                subtitle: Text(
                  '${names(suggestions.notInServerStores)}. '
                  '${localText(context, 'Add the same store on the server to sync these series.', 'Tambahkan store yang sama di server supaya series ini tersinkron.')}',
                ),
              ),
          ],
        ),
      ],
    );
  }
}
