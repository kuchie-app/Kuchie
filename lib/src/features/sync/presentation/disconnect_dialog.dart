import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../widgets/popup_widgets/app_dialog.dart';
import '../../local_collection/presentation/local_ui.dart';
import '../controller/sync_disconnect.dart';

/// Disconnect, with the optional step of saving the server's chapters here
/// first (design 3.6). Returns whether sync was turned off (or will be,
/// once saving finishes).
Future<bool> showDisconnectDialog(BuildContext context) async {
  final disconnect = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(syncDisconnectProvider);
  final kept = disconnect.serverChapters().catchError(
    (Object _) => null as List<ServerKeptChapter>?,
  );
  final choice = await showAppDialog<_Choice>(
    context: context,
    builder: (dialog) => FutureBuilder<List<ServerKeptChapter>?>(
      future: kept,
      builder: (dialog, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final chapters = snapshot.data;
        return AlertDialog(
          title: Text(
            localText(
              dialog,
              'Disconnect the server?',
              'Putuskan koneksi server?',
            ),
          ),
          content: loading
              ? const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Text(switch (chapters) {
                  null => localText(
                    dialog,
                    "Your library stays on this iPhone. The server can't be reached, so its downloads stay there.",
                    'Library tetap di iPhone ini. Server tidak terjangkau, jadi unduhannya tetap di server.',
                  ),
                  [] => localText(
                    dialog,
                    'Your library, progress and extensions stay on this iPhone. Sync stops.',
                    'Library, progres, dan extension tetap di iPhone ini. Sinkronisasi berhenti.',
                  ),
                  final list => localText(
                    dialog,
                    'There are ${list.length} chapters on the server. Save them all to this iPhone before disconnecting? They stay on the server either way.',
                    'Ada ${list.length} chapter di server. Simpan semuanya ke iPhone sebelum memutus koneksi? Chapter itu tetap ada di server.',
                  ),
                }),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(MaterialLocalizations.of(dialog).cancelButtonLabel),
            ),
            if (!loading && (chapters?.isNotEmpty ?? false))
              TextButton(
                onPressed: () => Navigator.pop(dialog, _Choice.saveFirst),
                child: Text(
                  localText(dialog, 'Save everything', 'Simpan semuanya'),
                ),
              ),
            if (!loading)
              TextButton(
                onPressed: () => Navigator.pop(dialog, _Choice.disconnect),
                child: Text(
                  chapters?.isNotEmpty ?? false
                      ? localText(dialog, 'Just disconnect', 'Putuskan saja')
                      : localText(dialog, 'Disconnect', 'Putuskan'),
                ),
              ),
          ],
        );
      },
    ),
  );
  if (choice == null) return false;
  switch (choice) {
    case _Choice.disconnect:
      await disconnect.disconnect();
    case _Choice.saveFirst:
      final chapters = await kept ?? const [];
      unawaited(disconnect.saveThenDisconnect(chapters));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localText(
                context,
                'Saving ${chapters.length} chapters. Sync turns off when they are here.',
                'Menyimpan ${chapters.length} chapter. Sinkronisasi berhenti setelah semuanya tersimpan.',
              ),
            ),
          ),
        );
      }
  }
  return true;
}

enum _Choice { disconnect, saveFirst }
