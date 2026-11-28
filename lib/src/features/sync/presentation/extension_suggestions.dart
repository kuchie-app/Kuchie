import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../local_collection/presentation/local_ui.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../controller/extension_sync.dart';

/// Installs what the server reads after a confirming sheet (design 3.5:
/// nothing installs without a tap). Returns whether anything was done.
Future<bool> installExtensionsFromServer(
  BuildContext context,
  ExtensionSuggestions suggestions,
) async {
  final count = suggestions.onlyOnServer.length;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localText(
                sheet,
                'Install $count extensions from the server',
                'Pasang $count extension dari server',
              ),
              style: Theme.of(sheet).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              localText(
                sheet,
                '${suggestions.seriesWaiting} series of your server library come in once they are here.',
                '${suggestions.seriesWaiting} series dari library server masuk setelah extension ini terpasang.',
              ),
            ),
            if (suggestions.storesToAdd.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                localText(sheet, 'Stores to add', 'Store yang ditambahkan'),
                style: Theme.of(sheet).textTheme.titleSmall,
              ),
              for (final store in suggestions.storesToAdd)
                Text('• ${store.name}  ${store.indexUrl}'),
            ],
            const SizedBox(height: 12),
            Text(
              localText(sheet, 'Extensions', 'Extension'),
              style: Theme.of(sheet).textTheme.titleSmall,
            ),
            Text(
              [
                for (final extension in suggestions.onlyOnServer)
                  switch (suggestions.seriesByPackage[extension.package]) {
                    final int series when series > 0 =>
                      '${extension.name} ($series)',
                    _ => extension.name,
                  },
              ].join(', '),
            ),
            const SizedBox(height: 8),
            Text(
              localText(
                sheet,
                "Each extension is checked against its store's signing key, as when you install one yourself.",
                'Setiap extension diperiksa dengan kunci tanda tangan store-nya, sama seperti saat memasang sendiri.',
              ),
              style: Theme.of(sheet).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(sheet, true),
              child: Text(localText(sheet, 'Install', 'Pasang')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheet, false),
              child: Text(MaterialLocalizations.of(sheet).cancelButtonLabel),
            ),
          ],
        ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final step = ValueNotifier<String?>(null);
  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<String?>(
            valueListenable: step,
            builder: (dialog, name, _) => Row(
              children: [
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    name == null
                        ? localText(dialog, 'Syncing…', 'Menyinkronkan…')
                        : localText(
                            dialog,
                            'Installing $name…',
                            'Memasang $name…',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  ServerExtensionsReport? report;
  Object? failure;
  try {
    report = await container
        .read(extensionSyncProvider)
        .installFromServer(suggestions, onStep: (name) => step.value = name);
    step.value = null;
  } catch (error) {
    failure = error;
  } finally {
    navigator.pop();
    step.dispose();
  }
  container.invalidate(extensionSuggestionsProvider);
  if (!context.mounted) return true;
  final message = switch ((report, failure)) {
    (_, final error?) => '$error',
    (final done?, _) when done.failed.isEmpty => localText(
      context,
      'Installed ${done.installed.length} extensions. Your library is syncing.',
      '${done.installed.length} extension terpasang. Library sedang disinkronkan.',
    ),
    (final done?, _) => localText(
      context,
      'Installed ${done.installed.length}; not installed: ${done.failed.keys.join(', ')}.',
      '${done.installed.length} terpasang; tidak terpasang: ${done.failed.keys.join(', ')}.',
    ),
    _ => '',
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  return true;
}

/// Shown on the empty Local library while sync is on and the server holds
/// series this iPhone can't read yet: the first thing after connecting.
class ServerLibraryWaitingCard extends ConsumerWidget {
  const ServerLibraryWaitingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(extensionSuggestionsProvider).value;
    if (suggestions == null || suggestions.onlyOnServer.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localText(
                context,
                '${suggestions.seriesWaiting} series on your server',
                '${suggestions.seriesWaiting} series di server Anda',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              localText(
                context,
                'They come here once this iPhone has the same ${suggestions.onlyOnServer.length} extensions as the server.',
                'Series itu masuk setelah iPhone ini punya ${suggestions.onlyOnServer.length} extension yang sama dengan server.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.download_rounded),
              onPressed: () =>
                  unawaited(installExtensionsFromServer(context, suggestions)),
              label: Text(
                localText(
                  context,
                  'Install from the server',
                  'Pasang dari server',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
                  '${localText(context, '${suggestions.seriesWaiting} series wait for them.', '${suggestions.seriesWaiting} series menunggu extension ini.')}',
                ),
                trailing: TextButton(
                  onPressed: () => unawaited(
                    installExtensionsFromServer(context, suggestions),
                  ),
                  child: Text(localText(context, 'Install', 'Pasang')),
                ),
              ),
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
