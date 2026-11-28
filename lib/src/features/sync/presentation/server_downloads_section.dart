import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../local_collection/presentation/local_ui.dart';
import '../controller/server_transfers.dart';
import '../controller/sync_engine_provider.dart';
import '../data/sync_journal.dart';

/// The server's part of Downloads (design 3.6): chapters on their way to
/// the server, as last seen, with retry for failed ones.
class ServerDownloadsSection extends ConsumerStatefulWidget {
  const ServerDownloadsSection({super.key});

  @override
  ConsumerState<ServerDownloadsSection> createState() =>
      _ServerDownloadsSectionState();
}

class _ServerDownloadsSectionState
    extends ConsumerState<ServerDownloadsSection> {
  late final ServerTransfers _transfers = ref.read(serverTransfersProvider);
  List<SyncTransfer> _list = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_transfers.run().then((_) => _load()).catchError((Object _) {}));
  }

  Future<void> _load() async {
    try {
      final list = await _transfers.all();
      if (mounted) setState(() => _list = list);
    } catch (_) {
      // The Local queue below still shows.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(syncEngineProvider).enabled || _list.isEmpty) {
      return const SizedBox.shrink();
    }
    int count(Set<SyncTransferState> states) =>
        _list.where((transfer) => states.contains(transfer.state)).length;
    final working = count({
      SyncTransferState.queued,
      SyncTransferState.requested,
      SyncTransferState.verified,
    });
    final failed = count({SyncTransferState.failed});
    final done = count({SyncTransferState.done});
    final last = _list
        .map((transfer) => transfer.updatedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final local = MaterialLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localText(context, 'On the server', 'Di server'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (working > 0)
                  localText(
                    context,
                    '$working downloading',
                    '$working sedang diunduh',
                  ),
                if (done > 0) localText(context, '$done done', '$done selesai'),
                if (failed > 0)
                  localText(context, '$failed failed', '$failed gagal'),
                localText(
                  context,
                  'last seen ${local.formatTimeOfDay(TimeOfDay.fromDateTime(last.toLocal()))}',
                  'terakhir dilihat ${local.formatTimeOfDay(TimeOfDay.fromDateTime(last.toLocal()))}',
                ),
              ].join(' · '),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (failed > 0)
                  TextButton(
                    onPressed: () async {
                      await _transfers.retryFailed();
                      await _load();
                    },
                    child: Text(localText(context, 'Try again', 'Coba lagi')),
                  ),
                if (failed + done > 0)
                  TextButton(
                    onPressed: () async {
                      await _transfers.clearFinished();
                      await _load();
                    },
                    child: Text(localText(context, 'Clear', 'Bersihkan')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
